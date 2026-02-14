# Quick Reference

## Cluster Resource Management

### Check Nomad Cluster Memory

```fish
# Quick memory check (Fish shell)
for node_name in dev-nomad-client-1 dev-nomad-client-2 dev-nomad-client-3 dev-nomad-client-4 dev-nomad-client-5 dev-nomad-client-6
  set node_id (curl -s http://10.0.0.50:4646/v1/nodes | python3 -c "import sys, json; nodes = json.load(sys.stdin); print([n['ID'] for n in nodes if '$node_name' == n['Name']][0])")
  curl -s http://10.0.0.50:4646/v1/node/$node_id | python3 -c "import sys, json; n = json.load(sys.stdin); mem = n.get('NodeResources', {}).get('Memory', {}).get('MemoryMB', 0); print('$node_name: ' + str(mem) + ' MB (' + str(round(mem/1024, 2)) + ' GB)')"
end

# Check actual VM memory
for ip in 10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64 10.0.0.65
  ssh ubuntu@$ip "echo -n '$ip: ' && free -h | grep Mem"
end
```

### Check All Job Statuses

```bash
# List all jobs and their status
curl -s http://10.0.0.50:4646/v1/jobs | python3 -c "import sys, json; jobs = json.load(sys.stdin); [print(f\"{j['Name']}: {j['Status']}\") for j in jobs]"

# Find dead services
nomad job status -address=http://10.0.0.50:4646 | grep dead
```

### Restart Services After Client Reboot

```fish
# Restart all services
for job in jobs/services/*.nomad.hcl
  nomad job run -address=http://10.0.0.50:4646 $job
end

# Or specific service
nomad job run -address=http://10.0.0.50:4646 jobs/services/homepage.nomad.hcl
```

## Vault

### Unseal all nodes

for ip in 10.0.0.30 10.0.0.31 10.0.0.32; do ssh $ip "vault operator unseal"; done

## Check status

vault status

## Adding New Services with Volumes

**CRITICAL CHECKLIST** - Do ALL steps or jobs will fail!

### 1. Add volume to Ansible base-system role

Edit `ansible/roles/base-system/tasks/main.yml`:
```yaml
- name: Create host volume directories
  loop:
    # ... existing volumes ...
    - { name: 'my_new_volume', owner: '1000', group: '1000', mode: '0755' }
```

### 2. Add host_volume to Nomad client template

Edit `ansible/roles/nomad-client/templates/nomad-client.hcl.j2`:
```hcl
client {
  # ... existing volumes ...
  
  host_volume "my_new_volume" {
    path      = "{{ nas_mount_point }}/my_new_volume"
    read_only = false
  }
}
```

### 3. Apply and restart

```bash
# Apply Ansible configuration
task ansible:configure

# MUST manually restart Nomad clients
for ip in 10.0.0.60 10.0.0.61 10.0.0.62 10.0.0.63 10.0.0.64 10.0.0.65
  ssh ubuntu@$ip "sudo systemctl restart nomad"
end

# Verify volumes are registered
nomad node status dev-nomad-client-1 | grep -A 50 "Host Volumes"
```

**Without step 2 and 3, you'll get "missing compatible host volumes" errors!**

## Nomad

### Deploy all services

nomad run jobs/services/*.nomad.hcl

## Watch job

nomad job status -verbose whoami

## Consul

### List services

consul catalog services

## DNS test

dig @10.0.0.50 whoami.service.consul