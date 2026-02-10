#!/usr/bin/env fish
# Cleanup duplicate/stopped VMs created during failed terraform operations

# Stopped duplicate VMs to delete (not in Terraform state)
# Based on Proxmox listing - these are stopped clones/duplicates
# Format: vmid node
set VMS_TO_DELETE \
    "112 pve1" \
    "113 pve3" \
    "114 pve2" \
    "115 pve2" \
    "116 pve3" \
    "117 pve1" \
    "118 pve2" \
    "119 pve3" \
    "120 pve1"

# VMs in Terraform state (DO NOT DELETE):
# Servers: 103, 105, 102
# Clients: 104, 101, 100, 109, 111, 110

function get_node_ip
    switch $argv[1]
        case pve1
            echo "10.0.0.21"
        case pve2
            echo "10.0.0.22"
        case pve3
            echo "10.0.0.23"
        case '*'
            echo ""
    end
end

echo "The following STOPPED VMs will be deleted from Proxmox:"
for entry in $VMS_TO_DELETE
    set vmid (echo $entry | awk '{print $1}')
    set node (echo $entry | awk '{print $2}')
    echo "  - VM $vmid on $node"
end

echo ""
read -P "Continue with deletion? [y/N] " -n 1 confirm
echo ""

if test "$confirm" != "y" -a "$confirm" != "Y"
    echo "Aborted"
    exit 0
end

for entry in $VMS_TO_DELETE
    set vmid (echo $entry | awk '{print $1}')
    set node (echo $entry | awk '{print $2}')
    set node_ip (get_node_ip $node)
    
    echo "Deleting VM $vmid from $node ($node_ip)..."
    
    # SSH to the specific node where the VM is located
    set result (ssh -o StrictHostKeyChecking=no root@$node_ip "qm destroy $vmid --purge" 2>&1)
    set status_code $status
    
    if test $status_code -eq 0
        echo "  ✓ Deleted VM $vmid"
    else
        echo "  ✗ Failed to delete VM $vmid: $result"
    end
    
    sleep 0.5
end

echo ""
echo "Cleanup complete!"
