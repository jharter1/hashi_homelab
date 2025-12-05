# Nomad Cluster Disk Space Configuration

## Overview
This document explains how disk space is configured and allocated in the Nomad cluster to prevent "disk exhausted" errors when deploying jobs.

## Problem
Previously, Nomad jobs would fail to place with error:
```
Resources exhausted on X nodes
Class "compute" exhausted on X nodes
Dimension "disk" exhausted on X nodes
```

This occurred because:
1. **Disk configuration wasn't being applied to VMs** - The `disk_size` variable was defined but never used in the Proxmox VM resource
2. **Nomad wasn't informed of available disk** - The client config didn't explicitly reserve system resources, leaving ambiguity about available disk
3. **VMs were undersized** - 30GB for clients was too small given system overhead

## Solution

### 1. Proxmox VM Disk Configuration
**File**: `terraform/modules/proxmox-vm/main.tf`

Added disk block to actually resize VMs during provisioning:
```hcl
disk {
  datastore_id = var.storage_pool
  interface    = "virtio0"
  size         = var.disk_size  # Now actually used!
}
```

### 2. Nomad Resource Reservation
**File**: `terraform/modules/nomad-client/templates/nomad-client.hcl`

Explicitly defines reserved system resources in the `reserved` block:
```hcl
reserved {
  cpu      = 250  # MHz
  memory   = 256  # MB
  disk     = 500  # MB
  ports    = "22,9090-9099"
}
```

**Why this matters**: 
- Nomad calculates *available* resources as: `Total - Reserved`
- Example: 50GB disk with 500MB reserved = 49.5GB available for jobs
- Without this block, Nomad uses defaults that may be too conservative

### 3. VM Size Adjustments
**File**: `terraform/environments/dev/variables.tf`

Updated default sizes:
- **Client VMs**: 30G → **50G**
  - More headroom for Docker images, task ephemeral storage
  - Accommodates 2-3 concurrent jobs per client
  
- **Server VMs**: 20G → **40G**
  - Servers handle Consul/Nomad state, Raft logs
  - Ensures stability with state growth

## Current Configuration

### Clients (Nomad + Docker)
```
VM Size:           50G
Reserved (System): 500MB
Available for jobs: ~49.5GB
```

### Servers (Consul + Nomad)
```
VM Size:           40G
Reserved (System): 500MB (not configured per server currently)
Available for jobs: ~39.5GB
```

## Deployment

When you next run Terraform:
```bash
cd terraform/environments/dev
terraform apply
```

This will:
1. Rebuild VMs with new 50GB/40GB disk sizes
2. Deploy updated Nomad client config with disk reservations
3. Automatically handle Nomad service restarts to load new config

## Verification

After applying changes:

```bash
# Check VM disk sizes
ssh ubuntu@10.0.0.60 "df -h /"

# Check Nomad reports correct available disk
NOMAD_ADDR=http://10.0.0.50:4646 nomad node status <node-id>
```

You should see significantly more available disk for job placement.

## Future Considerations

- **Monitoring**: Add disk usage alerts via Prometheus when disk reaches 80-90%
- **Cleanup**: Implement job logs rotation or host volume pruning
- **Growth**: If deploying large datasets, consider adding dedicated volumes to clients
- **Host Volumes**: For stateful services (like Prometheus), use host volumes at `/mnt/<service-name>`

## Related Files
- Proxmox VM module: `terraform/modules/proxmox-vm/main.tf`
- Nomad client config: `terraform/modules/nomad-client/templates/nomad-client.hcl`
- Environment variables: `terraform/environments/dev/variables.tf`
- Terraform apply: `terraform/environments/dev/main.tf`
