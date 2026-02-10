#!/usr/bin/env fish
# Rolling rebuild of VMs to apply new disk sizes
# This recreates VMs one at a time to minimize cluster disruption

set script_dir (dirname (realpath (status --current-filename)))
set project_root (dirname $script_dir)
set tf_dir "$project_root/terraform/environments/dev"
set ansible_dir "$project_root/ansible"

# Nomad server addresses for API calls (with fallback)
set NOMAD_SERVERS "10.0.0.50:4646" "10.0.0.51:4646" "10.0.0.52:4646"

function get_nomad_server
    # Try each Nomad server until we find one that responds
    for server in $NOMAD_SERVERS
        if curl -s --max-time 2 http://$server/v1/status/leader >/dev/null 2>&1
            echo $server
            return 0
        end
    end
    log_error "No Nomad servers are available!"
    return 1
end

function log_info
    echo (set_color green)"[INFO]"(set_color normal) $argv
end

function log_warn
    echo (set_color yellow)"[WARN]"(set_color normal) $argv
end

function log_error
    echo (set_color red)"[ERROR]"(set_color normal) $argv
end

function get_node_id
    set vm_ip $argv[1]
    set node_name $argv[2]
    
    # Strip environment prefix to get the Nomad node name
    set node_name (string replace -r '^dev-' '' $vm_name)
    
    set nomad_server (get_nomad_server)
    if test $status -ne 0
        return 1
    end
    
    # Query Nomad API for node ID by name - only get READY nodes
    set node_id (curl -s http://$nomad_server/v1/nodes | jq -r ".[] | select(.Name == \"$node_name\" and .Status == \"ready\") | .ID" 2>/dev/null)
    
    if test -z "$node_id"
        log_warn "Could not find ready Nomad node ID for $node_name"
        return 1
    end
    
    echo $node_id
    return 0
end
function purge_dead_node
    set vm_name $argv[1]
    
    # Strip environment prefix to get the Nomad node name
    set node_name (string replace -r '^dev-' '' $vm_name)
    
    log_info "Checking if dead nodes named $node_name need to be purged..."
    
    set nomad_server (get_nomad_server)
    if test $status -ne 0
        return 1
    end
    
    # Get ALL nodes with this name (may be duplicates after rebuilds)
    set node_lines (curl -s http://$nomad_server/v1/nodes | jq -r ".[] | select(.Name == \"$node_name\") | \"\(.ID) \(.Status)\"" 2>/dev/null)
    
    if test -z "$node_lines"
        log_info "Node $node_name not found in cluster, no purge needed"
        return 0
    end
    
    # Split into array of lines (each line is "ID STATUS")
    set node_entries (string split \n -- $node_lines)
    
    set purged_count 0
    for entry in $node_entries
        # Skip empty lines
        if test -z "$entry"
            continue
        end
        
        set node_id (echo $entry | awk '{print $1}')
        set node_status (echo $entry | awk '{print $2}')
        
        if test "$node_status" = "down"
            log_info "Purging dead node $node_name ($node_id) from cluster..."
            curl -s -X POST "http://$nomad_server/v1/node/$node_id/purge" >/dev/null
            
            if test $status -eq 0
                log_info "Successfully purged dead node $node_name ($node_id)"
                set purged_count (math $purged_count + 1)
            else
                log_error "Failed to purge node $node_name ($node_id)"
                return 1
            end
        else
            log_info "Node $node_name ($node_id) is $node_status, will be handled normally"
        end
    end
    
    if test $purged_count -gt 0
        log_info "Purged $purged_count dead node(s) for $node_name"
    end
    
    return 0
end
function drain_node
    set node_id $argv[1]
    set node_name $argv[2]
    
    set nomad_server (get_nomad_server)
    if test $status -ne 0
        return 1
    end
    
    log_info "Draining Nomad node $node_name ($node_id)..."
    
    # Enable drain mode (this will reschedule jobs to other nodes)
    curl -s -X POST "http://$nomad_server/v1/node/$node_id/drain" \
        -d '{"DrainSpec":{"Deadline":300000000000,"IgnoreSystemJobs":false}}' >/dev/null
    
    if test $status -ne 0
        log_error "Failed to drain node $node_name"
        return 1
    end
    
    # Wait for drain to complete
    log_info "Waiting for allocations to migrate (max 5 minutes)..."
    set max_wait 30 # 30 * 10s = 5 minutes
    set count 0
    
    while test $count -lt $max_wait
        set allocs (curl -s "http://$nomad_server/v1/node/$node_id/allocations" | jq -r '.[] | select(.ClientStatus == "running") | .ID' 2>/dev/null | wc -l | string trim)
        
        if test "$allocs" = "0"
            log_info "Node $node_name fully drained (no running allocations)"
            return 0
        end
        
        echo -n "."
        sleep 10
        set count (math $count + 1)
    end
    
    log_warn "Drain timeout reached, some allocations may still be running"
    return 0
end

function wait_for_vm
    set vm_name $argv[1]
    set max_attempts 30
    set attempt 0
    
    log_info "Waiting for $vm_name to be ready..."
    
    while test $attempt -lt $max_attempts
        set attempt (math $attempt + 1)
        sleep 10
        
        # Check if VM is responding to SSH (basic health check)
        if ssh -o ConnectTimeout=5 -o StrictHostKeyChecking=no ubuntu@$argv[2] "echo ready" >/dev/null 2>&1
            log_info "$vm_name is ready!"
            return 0
        end
        
        echo -n "."
    end
    
    log_error "$vm_name failed to become ready after $max_attempts attempts"
    return 1
end

function wait_for_nomad_node
    set vm_name $argv[1]
    
    # Strip environment prefix to get the Nomad node name
    set node_name (string replace -r '^dev-' '' $vm_name)
    
    set max_attempts 30
    set attempt 0
    
    log_info "Waiting for Nomad node $node_name to register..."
    
    while test $attempt -lt $max_attempts
        set attempt (math $attempt + 1)
        sleep 10
        
        set nomad_server (get_nomad_server)
        if test $status -ne 0
            log_warn "No Nomad servers available, retrying..."
            continue
        end
        
        # Check if node is registered in Nomad with status 'ready'
        # Only get ready nodes to avoid confusion with duplicate down nodes
        set node_status (curl -s http://$nomad_server/v1/nodes | jq -r ".[] | select(.Name == \"$node_name\" and .Status == \"ready\") | .Status" 2>/dev/null)
        
        if test "$node_status" = "ready"
            log_info "$node_name is registered and ready in Nomad cluster!"
            return 0
        end
        
        echo -n "."
    end
    
    log_error "$node_name failed to register in Nomad after $max_attempts attempts"
    return 1
end

function needs_rebuild
    set target $argv[1]
    
    log_info "Checking if $target needs rebuild..."
    echo -n "  Running terraform plan"
    
    # Use terraform plan with -detailed-exitcode and -refresh=false for speed
    # Exit codes: 0 = no changes, 1 = error, 2 = changes needed
    terraform plan -detailed-exitcode -refresh=false -input=false -target="$target" -compact-warnings >/dev/null 2>&1
    set result $status
    
    echo "" # New line
    
    if test $result -eq 0
        log_info "✓ Already up to date, skipping rebuild"
        return 1
    else if test $result -eq 2
        log_info "✓ Changes detected, will rebuild"
        return 0
    else
        # Exit code 1 means error, but we'll proceed anyway to be safe
        log_warn "! Terraform error, will proceed with rebuild to be safe"
        return 0
    end
end

function configure_with_ansible
    set vm_name $argv[1]
    
    # Strip environment prefix (e.g., "dev-nomad-client-1" -> "nomad-client-1")
    set ansible_host (string replace -r '^dev-' '' $vm_name)
    
    log_info "Configuring $vm_name with Ansible (inventory host: $ansible_host)..."
    
    # Run Ansible playbook limited to this specific host using absolute paths
    pushd $ansible_dir >/dev/null
    ansible-playbook -i inventory/hosts.yml playbooks/site.yml -l "$ansible_host" --diff
    set result $status
    popd >/dev/null
    
    if test $result -ne 0
        log_error "Ansible configuration failed for $vm_name"
        return 1
    end
    
    log_info "Ansible configuration complete for $vm_name"
    return 0
end

cd $tf_dir || begin
    log_error "Failed to change to terraform directory: $tf_dir"
    exit 1
end

log_info "Starting rolling rebuild of VMs with new disk sizes"
log_info "Clients: 100G → 60G, Servers: 50G → 30G"
echo ""

# Prompt for confirmation
read -P "This will recreate all VMs one at a time. Continue? [y/N] " -n 1 confirm
echo ""

if test "$confirm" != "y" -a "$confirm" != "Y"
    log_warn "Aborted by user"
    exit 0
end

# Recreate clients one at a time (6 clients, indices 0-5)
log_info "Phase 1: Recreating Nomad clients (6 VMs)"
for i in (seq 0 5)
    set client_num (math $i + 1)
    set client_ip (math 60 + $i)
    set client_name "dev-nomad-client-$client_num"
    set client_target "module.nomad_clients.module.nomad_clients[$i]"
    
    log_info "Processing $client_name (10.0.0.$client_ip)..."
    
    # Check if this VM actually needs to be rebuilt
    if not needs_rebuild "$client_target"
        log_info "Skipping $client_name (already up to date)"
        echo ""
        continue
    end
    
    # Check if there's a dead node to purge first
    purge_dead_node "$client_name"
    
    # Get node ID and drain before recreating (if node is alive)
    set node_id (get_node_id "10.0.0.$client_ip" "$client_name")
    if test $status -eq 0
        drain_node "$node_id" "$client_name"
    else
        log_warn "Node not found or already purged, skipping drain for $client_name"
    end
    
    log_info "Recreating $client_name..."
    # Use -replace to destroy and recreate in one step (faster than taint + apply)
    # Skip refresh since we're replacing anyway - saves 60+ seconds per VM
    set apply_output (terraform apply -auto-approve -refresh=false \
        -replace="module.nomad_clients.module.nomad_clients[$i].proxmox_virtual_environment_vm.vm" \
        -target="module.nomad_clients.module.nomad_clients[$i]" 2>&1)
    set apply_status $status
    
    # Show output without CLI warnings
    echo "$apply_output" | grep -v "CLI configuration"
    
    if test $apply_status -ne 0
        log_error "Failed to recreate $client_name"
        exit 1
    end
    
    # Wait for VM to be ready
    wait_for_vm "$client_name" "10.0.0.$client_ip"
    if test $status -ne 0
        log_error "$client_name did not become ready, stopping"
        exit 1
    end
    
    # Configure the VM with Ansible
    configure_with_ansible "$client_name"
    if test $status -ne 0
        log_error "Failed to configure $client_name, stopping"
        exit 1
    end
    
    # Wait for Nomad node to register and become ready
    wait_for_nomad_node "$client_name"
    if test $status -ne 0
        log_warn "$client_name did not register in Nomad, continuing anyway..."
    end
    
    log_info "$client_name rebuild complete, waiting 30s before next..."
    sleep 30
    echo ""
end

log_info "All clients recreated successfully!"
echo ""

# Recreate servers one at a time (3 servers, indices 0-2)
log_info "Phase 2: Recreating Nomad servers (3 VMs)"
log_warn "Server recreation may affect cluster availability"
log_warn "Servers will be gracefully removed from Raft consensus before recreation"

for i in (seq 0 2)
    set server_num (math $i + 1)
    set server_ip (math 50 + $i)
    set server_name "dev-nomad-server-$server_num"
    set server_target "module.nomad_servers.module.nomad_servers[$i]"
    
    log_info "Processing $server_name (10.0.0.$server_ip)..."
    
    # Check if this VM actually needs to be rebuilt
    if not needs_rebuild "$server_target"
        log_info "Skipping $server_name (already up to date)"
        echo ""
        continue
    end
    
    # For servers, we don't drain (they don't run workloads)
    # But we should ensure quorum can be maintained
    log_info "Recreating $server_name..."
    # Use -replace to destroy and recreate in one step (faster than taint + apply)
    # Skip refresh since we're replacing anyway - saves 60+ seconds per VM
    set apply_output (terraform apply -auto-approve -refresh=false \
        -replace="module.nomad_servers.module.nomad_servers[$i].proxmox_virtual_environment_vm.vm" \
        -target="module.nomad_servers.module.nomad_servers[$i]" 2>&1)
    set apply_status $status
    
    # Show output without CLI warnings
    echo "$apply_output" | grep -v "CLI configuration"
    
    if test $apply_status -ne 0
        log_error "Failed to recreate $server_name"
        exit 1
    end
    
    # Wait for VM to be ready
    wait_for_vm "$server_name" "10.0.0.$server_ip"
    if test $status -ne 0
        log_error "$server_name did not become ready, stopping"
        exit 1
    end
    
    # Configure the VM with Ansible
    configure_with_ansible "$server_name"
    if test $status -ne 0
        log_error "Failed to configure $server_name, stopping"
        exit 1
    end
    
    # Wait extra time for Raft consensus to stabilize
    log_info "$server_name rebuild complete, waiting 90s for Raft consensus to stabilize..."
    sleep 90
    echo ""
end

log_info "Rolling rebuild complete!"
log_info "Running final terraform apply to ensure clean state..."
terraform apply -auto-approve -refresh=false

log_info "Done! All VMs have been rebuilt and configured with Ansible"
