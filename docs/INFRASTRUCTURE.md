# Infrastructure & Storage Guide

This guide covers disk configuration, NAS storage architecture, and resource management for the Nomad cluster.

## Table of Contents

1. [Storage Architecture Overview](#storage-architecture-overview)
2. [NAS Storage Configuration](#nas-storage-configuration)
3. [Nomad Disk Space Configuration](#nomad-disk-space-configuration)
4. [NAS Migration History](#nas-migration-history)
5. [Troubleshooting](#troubleshooting)

---

# Storage Architecture Overview

The homelab uses a two-tier storage model:

## Storage Tiers

### Tier 1: NAS (Persistent Data)
- **Mount point**: `/mnt/nas/` on all Nomad clients
- **Protocol**: NFS from Proxmox host (10.0.0.100)
- **Purpose**: All persistent service data
- **Backed up**: Yes (via PVE-VM-Storage)
- **Survives**: VM rebuilds, HDD swaps, infrastructure changes

### Tier 2: VM Local Disk (Ephemeral Data)
- **Location**: `/opt/nomad/` on each client VM
- **Purpose**: Nomad task ephemeral storage, Docker images, logs
- **Backed up**: No
- **Survives**: Only until VM rebuild

## Services on NAS

All production services store data on NAS:

| Service | NAS Path | Size (Approx) | Notes |
|---------|----------|---------------|-------|
| Grafana | `/mnt/nas/grafana_data` | ~500MB | Dashboards, users, data sources |
| Prometheus | `/mnt/nas/prometheus_data` | ~2-5GB | Time-series metrics database |
| Loki | `/mnt/nas/loki_data` | ~1-3GB | Log aggregation storage |
| Minio | `/mnt/nas/minio` | Variable | S3-compatible object storage |
| Docker Registry | `/mnt/nas/registry` | ~5-10GB | Container image cache |
| Jenkins | `/mnt/nas/jenkins` | ~1-2GB | CI/CD jobs and artifacts |
| Homepage | `/mnt/nas/homepage` | ~10MB | Dashboard configuration |
| Calibre | `/mnt/nas/calibre` | Variable | E-book library |
| Uptime-Kuma | `/mnt/nas/uptime_kuma_data` | ~100MB | Monitoring configuration |
| Speedtest | `/mnt/nas/speedtest_data` | ~50MB | Speed test history (SQLite) |
| Immich | `/mnt/nas/immich_data` | Large | Photo/video backup |
| Immich PostgreSQL | `/mnt/nas/immich_postgres` | ~1GB | Photo metadata |
| Immich ML Cache | `/mnt/nas/immich_model-cache` | ~2GB | Machine learning models |
| Tailscale | `/mnt/nas/tailscale_state` | ~10MB | VPN state |

## VM Disk Allocation

### Client VMs (6 nodes: 10.0.0.60-65)
- **Total disk**: 50GB per VM
- **Reserved (system)**: 500MB
- **Available for Nomad**: ~49.5GB
- **Memory**: 6GB RAM per VM (36GB total)

### Server VMs (3 nodes: 10.0.0.50-52)
- **Total disk**: 40GB per VM
- **Reserved (system)**: 500MB
- **Available for Nomad**: ~39.5GB
- **Memory**: Varies by server role

---

# NAS Storage Configuration

## NFS Mount Setup

Configured via Ansible `base-system` role on all Nomad clients.

### Mount Configuration

**File**: `/etc/fstab` on each client

```
10.0.0.100:/mnt/pve-vm-storage  /mnt/nas  nfs  defaults,_netdev  0  0
```

**Options**:
- `defaults`: Standard mount options (rw, suid, dev, exec, auto, nouser, async)
- `_netdev`: Wait for network before mounting (prevents boot failures)

### Verification

```bash
# Check mount on all clients
ansible nomad_clients -m command -a "mountpoint /mnt/nas"

# Check NFS mount status
mount | grep nas

# Check available space
df -h /mnt/nas
```

## Creating Service Volumes

### Automated via Ansible

The `base-system` role creates all NAS directories:

```yaml
# In ansible/roles/base-system/tasks/main.yml
- name: Create NAS directories
  file:
    path: "/mnt/nas/{{ item }}"
    state: directory
    mode: '0755'
  loop:
    - grafana_data
    - prometheus_data
    - loki_data
    - minio
    # ... etc
```

Run configuration:

```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --tags base-system
```

### Manual Creation

If needed:

```bash
# On any Nomad client (10.0.0.60-65)
sudo mkdir -p /mnt/nas/myservice_data
sudo chmod 755 /mnt/nas/myservice_data

# For services requiring specific UID
sudo chown -R 1000:1000 /mnt/nas/myservice_data
```

## Host Volume Registration

After creating NAS directories, register them in Nomad client configuration.

**File**: `/etc/nomad.d/nomad.hcl` (via Ansible template)

```hcl
client {
  host_volume "myservice_data" {
    path      = "/mnt/nas/myservice_data"
    read_only = false
  }
}
```

Restart Nomad to load new volumes:

```bash
sudo systemctl restart nomad
```

## Using Volumes in Jobs

**Pattern in Nomad job file**:

```hcl
job "myservice" {
  group "app" {
    # Declare volume
    volume "data" {
      type      = "host"
      source    = "myservice_data"  # Matches host_volume name
      read_only = false
    }

    task "app" {
      driver = "docker"

      # Mount volume in container
      volume_mount {
        volume      = "data"
        destination = "/data"  # Path inside container
        read_only   = false
      }

      config {
        image = "myservice:latest"
      }
    }
  }
}
```

## Backup Strategy

### NAS-Level Backups

All NAS data backed up via PVE-VM-Storage snapshots:
- Automatic snapshots via Proxmox Backup Server
- Retention policy configured in PVE
- Snapshots stored on separate storage pool

### Service-Level Exports

For critical services:

**Grafana dashboards**:
```bash
# Export all dashboards
curl -s http://admin:admin@grafana.lab.hartr.net/api/search | \
  jq -r '.[].uid' | \
  xargs -I {} curl -s http://admin:admin@grafana.lab.hartr.net/api/dashboards/uid/{} > grafana-backup-{}.json
```

**Prometheus data**:
```bash
# Create snapshot
curl -XPOST http://prometheus.lab.hartr.net/api/v1/admin/tsdb/snapshot

# Copy snapshot directory from /mnt/nas/prometheus_data/snapshots/
```

### Restore Procedures

**Full NAS restore**:
```bash
# Stop all services
task nomad:stop-all

# Restore NAS data from Proxmox backup
# (via PVE UI or pvesm commands)

# Restart services
task deploy:all
```

**Single service restore**:
```bash
# Stop service
nomad job stop myservice

# Restore data
rsync -avz /backup/myservice_data/ /mnt/nas/myservice_data/

# Restart service
nomad job run jobs/services/myservice.nomad.hcl
```

---

# Nomad Disk Space Configuration

## Problem History

Previously, Nomad jobs failed with "Resources exhausted" errors:

```
Resources exhausted on X nodes
Class "compute" exhausted on X nodes
Dimension "disk" exhausted on X nodes
```

**Root causes**:
1. `disk_size` variable defined but never applied to Proxmox VMs
2. Nomad client config didn't reserve system resources
3. VMs were undersized (30GB) for client workloads

## Solution Components

### 1. Proxmox VM Disk Configuration

**File**: `terraform/modules/proxmox-vm/main.tf`

Disk block now actually resizes VMs:

```hcl
resource "proxmox_virtual_environment_vm" "vm" {
  # ... other config ...

  disk {
    datastore_id = var.storage_pool
    interface    = "virtio0"
    size         = var.disk_size  # Now actually used!
  }
}
```

### 2. Nomad Resource Reservation

**File**: `terraform/modules/nomad-client/templates/nomad-client.hcl`

Explicit system resource reservation:

```hcl
client {
  reserved {
    cpu      = 250  # MHz
    memory   = 256  # MB
    disk     = 500  # MB - Reserved for OS, Docker, logs
    # reserved_ports = "22,9090-9099"  # Updated syntax in newer Nomad versions
  }
}
```

**How calculation works**:
- **Total resources**: Detected from VM (e.g., 50GB disk, 10GB RAM)
- **Reserved resources**: Subtracted for system use (500MB disk, 256MB RAM)
- **Available for jobs**: Total - Reserved (49.5GB disk, ~9.75GB RAM)

**Why this matters**:
- Without `reserved` block, Nomad uses conservative defaults
- Explicit reservation ensures proper resource accounting
- Prevents over-allocation and "disk exhausted" errors

### 3. VM Size Adjustments

**File**: `terraform/environments/dev/terraform.tfvars`

Increased VM disk sizes:

```hcl
# Clients (was 30G)
nomad_client_disk_size = "50G"

# Servers (was 20G)
nomad_server_disk_size = "40G"
```

**Client sizing rationale** (50GB):
- Docker images: ~5-10GB
- Task ephemeral storage: ~10-20GB
- System overhead: ~5GB
- Nomad metadata: ~1-2GB
- **Remaining for tasks**: ~35-40GB

**Server sizing rationale** (40GB):
- Consul/Nomad state: ~2-5GB
- Raft logs: ~1-3GB (grows over time)
- System overhead: ~5GB
- **Remaining headroom**: ~30GB for growth

## Current Configuration

### Client Node Resources

**Per client VM** (10.0.0.60-65):

| Resource | Total | Reserved | Available |
|----------|-------|----------|-----------|
| Disk | 50GB | 500MB | ~49.5GB |
| Memory | 10GB | 256MB | ~9.75GB |
| CPU | Varies | 250MHz | ~95% of total |

**Total cluster capacity** (6 clients):
- Disk: ~297GB available
- Memory: ~58.5GB available
- CPU: Varies by node (typically ~20-30 cores total)

### Server Node Resources

**Per server VM** (10.0.0.50-52):

| Resource | Total | Reserved | Available |
|----------|-------|----------|-----------|
| Disk | 40GB | 500MB | ~39.5GB |
| Memory | Varies | Not configured | Varies |
| CPU | Varies | Not configured | Varies |

**Note**: Servers typically don't run workloads, so resource reservation is less critical.

## Deployment & Updates

### Applying Configuration Changes

```bash
cd terraform/environments/dev

# Preview changes
terraform plan

# Apply changes (rebuilds VMs with new disk sizes)
terraform apply
```

**What happens**:
1. VMs destroyed and recreated with new disk sizes
2. Ansible re-runs during provisioning (if configured)
3. Nomad clients restart with updated configuration
4. Resource allocation recalculated automatically

### Verification

**Check VM disk sizes**:

```bash
# SSH to client
ssh ubuntu@10.0.0.60 "df -h /"

# Should show ~50GB total
```

**Check Nomad resource reporting**:

```bash
# Get node ID
nomad node status

# Check detailed node resources
nomad node status <node-id>

# Look for:
# - Allocated Resources section
# - Available: disk should show ~49.5GB
```

**Example output**:

```
Allocated Resources
CPU            Memory        Disk
2500/30000 MHz 5.2 GiB/9.75 GiB 15 GiB/49.5 GiB
```

## Monitoring Storage

### Prometheus Metrics

Monitor disk usage via `node_exporter`:

```promql
# Disk usage percentage
100 - (node_filesystem_avail_bytes{mountpoint="/"} / node_filesystem_size_bytes{mountpoint="/"} * 100)

# NAS disk usage
100 - (node_filesystem_avail_bytes{mountpoint="/mnt/nas"} / node_filesystem_size_bytes{mountpoint="/mnt/nas"} * 100)
```

### Grafana Dashboards

Create alerts for:
- VM root disk usage > 80%
- NAS disk usage > 85%
- Rapid disk growth (derivative > threshold)

### Manual Checks

```bash
# Check all clients
ansible nomad_clients -m command -a "df -h /"

# Check NAS usage
ssh ubuntu@10.0.0.60 "df -h /mnt/nas"

# Check Docker disk usage
ssh ubuntu@10.0.0.60 "docker system df"
```

## Cleanup Strategies

### Docker Cleanup

Remove unused images/containers:

```bash
# On each client
docker system prune -af --volumes

# Or via Ansible
ansible nomad_clients -m command -a "docker system prune -af"
```

### Nomad Allocation Cleanup

Old allocation data accumulates in `/opt/nomad/alloc/`:

```bash
# Check allocation disk usage
ssh ubuntu@10.0.0.60 "du -sh /opt/nomad/alloc/*"

# Manually clean old allocations (Nomad should handle this)
nomad system gc
```

### Log Rotation

Configure log rotation for Docker and Nomad:

**Docker daemon config** (`/etc/docker/daemon.json`):

```json
{
  "log-driver": "json-file",
  "log-opts": {
    "max-size": "10m",
    "max-file": "3"
  }
}
```

## Future Considerations

### Capacity Planning

When to increase disk:
- VM root disk consistently > 75% full
- NAS storage > 80% full
- Frequent "disk exhausted" errors despite cleanup

**Scaling options**:
1. Increase VM disk sizes via Terraform variables
2. Add more Nomad clients (horizontal scaling)
3. Attach additional storage pools to clients
4. Move more data to NAS (if local disks filling up)

### Storage Monitoring

Recommended improvements:
- Prometheus alerts for disk usage thresholds
- Grafana dashboard showing disk trends over time
- Automated cleanup jobs (Nomad periodic jobs)
- Capacity forecasting based on growth rate

### Alternative Storage

Consider for future:
- **Ceph cluster**: Distributed storage across nodes
- **GlusterFS**: Alternative to NFS for HA
- **S3-compatible storage**: Use Minio for object storage needs
- **CSI plugins**: Nomad CSI for more advanced volume management

---

# NAS Migration History

## Background

**Problem**: HDD swap on Proxmox wiped out Uptime-Kuma and Grafana data because they were stored on VM local disks instead of NAS.

**Solution**: Migrated all persistent service data from `/opt/nomad-volumes/` (VM local) to `/mnt/nas/` (NAS) in February 2026.

## Migration Summary

### Services Migrated

| Service | Old Path | New Path | Status |
|---------|----------|----------|--------|
| Grafana | `/opt/nomad-volumes/grafana_data` | `/mnt/nas/grafana_data` | ✅ Migrated |
| Prometheus | `/opt/nomad-volumes/prometheus_data` | `/mnt/nas/prometheus_data` | ✅ Migrated |
| Loki | `/opt/nomad-volumes/loki_data` | `/mnt/nas/loki_data` | ✅ Migrated |
| Uptime-Kuma | `local/` (ephemeral) | `/mnt/nas/uptime_kuma_data` | ✅ Fresh start |

### Services Already on NAS

These services were already correctly configured:
- Minio, Docker Registry, Jenkins, Homepage, Calibre

## Migration Process

### Pre-Migration Checks

**Verification checklist**:

```bash
# 1. Verify NAS mounted on all clients
ansible nomad_clients -m command -a "mountpoint /mnt/nas"

# 2. Check available NAS space
ansible nomad_clients -m command -a "df -h /mnt/nas"

# 3. Review current data size
ssh ubuntu@10.0.0.60 "sudo du -sh /opt/nomad-volumes/*"

# 4. Backup critical data (optional but recommended)
```

### Configuration Updates

**Files modified**:

1. **ansible/roles/nomad-client/templates/nomad-client.hcl.j2**
   - Changed `grafana_data` path: `{{ nas_mount_point }}/grafana_data`
   - Changed `prometheus_data` path: `{{ nas_mount_point }}/prometheus_data`
   - Changed `loki_data` path: `{{ nas_mount_point }}/loki_data`
   - Added `uptime_kuma_data`: `{{ nas_mount_point }}/uptime_kuma_data`

2. **jobs/services/uptime-kuma.nomad.hcl**
   - Removed ephemeral `local/` volume
   - Added `uptime_kuma_data` host volume mount

### Migration Playbook

**Playbook**: `ansible/playbooks/migrate-to-nas-storage.yml`

**Execution**:

```bash
cd ansible
ansible-playbook -i inventory/hosts.yml playbooks/migrate-to-nas-storage.yml
```

**Playbook actions** (per client):
1. Verify NAS is mounted
2. Create new NAS directories for each service
3. Stop Nomad client service
4. Copy existing data from `/opt/nomad-volumes/` to `/mnt/nas/`
5. Deploy updated `nomad.hcl` configuration
6. Restart Nomad client

**Runtime**: ~5-10 minutes per client (depends on data size)

### Service Redeployment

After client updates:

```bash
# Stop old allocations
nomad job stop grafana
nomad job stop prometheus
nomad job stop loki
nomad job stop uptime-kuma

# Wait for graceful shutdown
sleep 10

# Redeploy with new volume paths
nomad job run jobs/services/grafana.nomad.hcl
nomad job run jobs/services/prometheus.nomad.hcl
nomad job run jobs/services/loki.nomad.hcl
nomad job run jobs/services/uptime-kuma.nomad.hcl
```

### Post-Migration Verification

**Health checks**:

```bash
# 1. Check service status
nomad job status grafana
nomad job status prometheus
nomad job status loki
nomad job status uptime-kuma

# 2. Verify data integrity
# - Access Grafana: http://grafana.lab.hartr.net
# - Check dashboards and data sources intact
# - Verify Prometheus has historical metrics
# - Check Loki logs available

# 3. Verify NAS directories
ssh ubuntu@10.0.0.60 "ls -lh /mnt/nas/"
```

## Post-Migration Cleanup

### Remove Old Volumes

After confirming success:

```bash
# On each client (10.0.0.60-65)
ssh ubuntu@<client-ip> "sudo rm -rf /opt/nomad-volumes/grafana_data"
ssh ubuntu@<client-ip> "sudo rm -rf /opt/nomad-volumes/prometheus_data"
ssh ubuntu@<client-ip> "sudo rm -rf /opt/nomad-volumes/loki_data"
```

**Note**: Keep `/opt/nomad-volumes/` directory for potential future use.

### Reconfigure Lost Services

**Uptime-Kuma** (data was already lost):
1. Access: `http://uptime-kuma.lab.hartr.net:3001`
2. Create new admin account
3. Re-add monitoring endpoints
4. Create status page with slug "default" (for Homepage widget)

## Rollback Plan

If migration fails on any client:

**Step 1**: Stop Nomad

```bash
ssh ubuntu@<client-ip> "sudo systemctl stop nomad"
```

**Step 2**: Restore old configuration

```bash
# Option A: Manually edit /etc/nomad.d/nomad.hcl
# Revert paths to /opt/nomad-volumes/*

# Option B: Re-run Ansible with reverted template
cd ansible
git checkout HEAD~1 roles/nomad-client/templates/nomad-client.hcl.j2
ansible-playbook -i inventory/hosts.yml playbooks/site.yml --limit <client-hostname>
```

**Step 3**: Restart Nomad

```bash
ssh ubuntu@<client-ip> "sudo systemctl start nomad"
```

**Step 4**: Redeploy services with old job files (if needed)

## Lessons Learned

### What Went Well

✅ **Ansible automation**: Playbook reduced manual steps and errors  
✅ **NAS reliability**: Data now survives infrastructure changes  
✅ **Staged approach**: Per-client migration allowed testing before full rollout

### Issues Encountered

⚠️ **Data loss**: Uptime-Kuma data already lost before migration  
⚠️ **Downtime**: Services unavailable during migration (~5-10 min per client)  
⚠️ **Permission issues**: Some services required specific UID/GID ownership

### Improvements for Future

1. **Test in dev first**: Always test storage migrations on dev environment
2. **Backup before migration**: Take snapshots before any data movement
3. **Automate verification**: Add post-migration checks to playbook
4. **Document ownership requirements**: Track which services need specific UIDs

---

# Troubleshooting

## NAS Storage Issues

### Issue: NAS Not Mounted

**Symptoms**: Services fail to start, "no such file or directory" errors for `/mnt/nas/`.

**Solutions**:

```bash
# Check mount status
ssh ubuntu@<client-ip> "mount | grep nas"

# Check /etc/fstab entry
ssh ubuntu@<client-ip> "cat /etc/fstab | grep nas"

# Remount manually
ssh ubuntu@<client-ip> "sudo mount -a"

# Or remount NFS specifically
ssh ubuntu@<client-ip> "sudo mount 10.0.0.100:/mnt/pve-vm-storage /mnt/nas"
```

**Prevent boot failures**:
- Ensure `_netdev` option in `/etc/fstab`
- This makes system wait for network before mounting

### Issue: Permission Denied on NAS

**Symptoms**: Services start but can't write to NAS volumes.

**Solutions**:

```bash
# Check directory permissions
ssh ubuntu@<client-ip> "ls -ld /mnt/nas/<service>_data"

# Fix ownership (most services run as UID 1000)
sudo chown -R 1000:1000 /mnt/nas/<service>_data

# Fix permissions
sudo chmod -R 755 /mnt/nas/<service>_data
```

**Service-specific UIDs**:
- PostgreSQL: UID 999
- Most others: UID 1000 or root

### Issue: NAS Out of Space

**Symptoms**: Service writes fail, allocation restarts, NFS errors.

**Solutions**:

```bash
# Check NAS usage
df -h /mnt/nas

# Find largest directories
du -sh /mnt/nas/* | sort -rh | head -10

# Clean up old backups, snapshots, etc.
# (varies by service)
```

**Prevention**:
- Set up Prometheus alerts for NAS disk usage > 85%
- Regular cleanup of old data (logs, snapshots, temp files)

## Disk Space Issues

### Issue: "Disk Exhausted" Errors

**Symptoms**: Nomad jobs fail to place with "Resources exhausted on X nodes, Dimension 'disk' exhausted".

**Solutions**:

```bash
# 1. Check Nomad's view of resources
nomad node status <node-id>
# Look at "Allocated Resources" section

# 2. Check actual disk usage
ssh ubuntu@<client-ip> "df -h /"

# 3. Clean up Docker
ssh ubuntu@<client-ip> "docker system prune -af --volumes"

# 4. Run Nomad garbage collection
nomad system gc

# 5. If still full, increase VM disk size via Terraform
# Edit terraform/environments/dev/terraform.tfvars
# nomad_client_disk_size = "75G"  # Increase from 50G
# terraform apply
```

### Issue: Docker Images Consuming Space

**Symptoms**: `/` filesystem fills up on clients, slow image pulls.

**Solutions**:

```bash
# Check Docker disk usage
docker system df

# Remove unused images
docker image prune -af

# Remove ALL unused data (careful!)
docker system prune -af --volumes

# Configure Docker registry for image caching
# See SERVICES.md - Docker Registry section
```

### Issue: Nomad Allocation Data Growing

**Symptoms**: `/opt/nomad/alloc/` directory consuming significant space.

**Solutions**:

```bash
# Check allocation directory size
du -sh /opt/nomad/alloc/*

# Run garbage collection
nomad system gc

# Manually remove old allocations (if GC doesn't work)
# Stop Nomad first!
sudo systemctl stop nomad
sudo rm -rf /opt/nomad/alloc/<old-alloc-id>
sudo systemctl start nomad
```

## Host Volume Issues

### Issue: Service Can't Find Host Volume

**Symptoms**: Allocation fails with "host volume not found" or "no such volume" errors.

**Solutions**:

```bash
# 1. Verify volume defined in Nomad client config
ssh ubuntu@<client-ip> "cat /etc/nomad.d/nomad.hcl | grep -A3 'host_volume'"

# 2. Check directory exists on host
ssh ubuntu@<client-ip> "ls -ld /mnt/nas/<service>_data"

# 3. Restart Nomad to load config changes
ssh ubuntu@<client-ip> "sudo systemctl restart nomad"

# 4. Verify Nomad sees the volume
nomad node status <node-id> | grep -i volume
```

### Issue: Volume Mount Read-Only

**Symptoms**: Service can read but not write to mounted volume.

**Solutions**:

```bash
# 1. Check volume configuration in job file
# Ensure: read_only = false

# 2. Check host volume definition
# Ensure: read_only = false

# 3. Check directory permissions
ssh ubuntu@<client-ip> "ls -ld /mnt/nas/<service>_data"
# Should show write permissions (755 or 775)

# 4. Check NFS mount options
mount | grep /mnt/nas
# Should show "rw" (read-write), not "ro" (read-only)
```

## Resource Allocation Issues

### Issue: Jobs Not Scheduling

**Symptoms**: "Resources exhausted" despite nodes appearing to have capacity.

**Solutions**:

```bash
# 1. Check actual vs reserved resources
nomad node status <node-id>

# 2. Verify reserved block in client config
ssh ubuntu@<client-ip> "cat /etc/nomad.d/nomad.hcl | grep -A5 'reserved'"

# 3. Check if constraint is too restrictive
# Review job file for:
# constraint { ... }

# 4. Check node eligibility
nomad node eligibility -enable <node-id>
```

### Issue: Memory Allocation Mismatch

**Symptoms**: Nomad shows different available memory than actual VM memory.

**Solutions**:

```bash
# Check actual VM memory
ssh ubuntu@<client-ip> "free -h"

# Check Nomad's view
nomad node status <node-id> | grep Memory

# If mismatch, update Terraform:
# terraform/environments/dev/terraform.tfvars
# nomad_client_memory = 10240  # MB
# terraform apply (recreates VMs)
```

---

**Related Documentation**:
- [CHEATSHEET.md](CHEATSHEET.md) - Quick reference commands
- [SERVICES.md](SERVICES.md) - Service deployment guides
- [NEW_SERVICES_DEPLOYMENT.md](NEW_SERVICES_DEPLOYMENT.md) - Adding new services
- [POSTGRESQL.md](POSTGRESQL.md) - Database management
