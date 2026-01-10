# NAS Storage Migration Guide

## Overview
This guide documents the migration of all Nomad service data from local VM disk storage (`/opt/nomad-volumes/`) to persistent NAS storage (`/mnt/nas/`).

**Problem**: Recent HDD swap wiped out Uptime-Kuma and Grafana data because they were stored on VM local disks instead of the NAS.

**Solution**: Move all persistent service data to NAS-backed storage to ensure data survives VM maintenance, HDD swaps, and other infrastructure changes.

## Affected Services

### Services Migrated to NAS
- **Grafana**: `/opt/nomad-volumes/grafana_data` → `/mnt/nas/grafana`
- **Prometheus**: `/opt/nomad-volumes/prometheus_data` → `/mnt/nas/prometheus`
- **Loki**: `/opt/nomad-volumes/loki_data` → `/mnt/nas/loki`
- **Uptime-Kuma**: `local/` ephemeral → `/mnt/nas/uptime-kuma` (fresh start)

### Services Already on NAS
- Minio: `/mnt/nas/minio` ✓
- Docker Registry: `/mnt/nas/registry` ✓
- Jenkins: `/mnt/nas/jenkins` ✓
- Homepage: `/mnt/nas/homepage` ✓
- Calibre: `/mnt/nas/calibre` ✓

## Pre-Migration Checklist

1. **Verify NAS is mounted on all clients**:
   ```bash
   ansible nomad_clients -m command -a "mountpoint /mnt/nas"
   ```

2. **Check available NAS space**:
   ```bash
   ansible nomad_clients -m command -a "df -h /mnt/nas"
   ```

3. **Review current data size**:
   ```bash
   ssh ubuntu@10.0.0.60 "sudo du -sh /opt/nomad-volumes/*"
   ```

4. **Backup critical data** (optional but recommended):
   ```bash
   # Via PVE-VM-Storage or manual rsync
   ```

## Migration Steps

### Step 1: Update Ansible Configuration

The following files have been updated:

1. **ansible/roles/nomad-client/templates/nomad-client.hcl.j2**
   - Changed `grafana_data` path to `{{ nas_mount_point }}/grafana`
   - Changed `prometheus_data` path to `{{ nas_mount_point }}/prometheus`
   - Changed `loki_data` path to `{{ nas_mount_point }}/loki`
   - Added `uptime_kuma_data` volume at `{{ nas_mount_point }}/uptime-kuma`

2. **jobs/services/uptime-kuma.nomad.hcl**
   - Removed ephemeral `local/` volume
   - Added `uptime_kuma_data` host volume mount

### Step 2: Run Migration Playbook

Execute the migration playbook to update all 3 Nomad clients:

```bash
cd /Users/jackharter/Developer/hashi_homelab/ansible
ansible-playbook -i inventory/hosts.yml playbooks/migrate-to-nas-storage.yml
```

**What the playbook does**:
1. Verifies NAS is mounted
2. Creates new NAS directories for each service
3. Stops Nomad client service
4. Copies existing data from `/opt/nomad-volumes/` to `/mnt/nas/`
5. Deploys updated `nomad.hcl` configuration
6. Restarts Nomad client

**Expected runtime**: ~5-10 minutes per client (depends on data size)

### Step 3: Redeploy Services

After all clients are updated, redeploy affected services:

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

### Step 4: Verify Migration

1. **Check service health**:
   ```bash
   nomad job status grafana
   nomad job status prometheus
   nomad job status loki
   nomad job status uptime-kuma
   ```

2. **Verify data integrity**:
   - Access Grafana at http://grafana.service.consul:3000 (admin/admin)
   - Check dashboards and data sources are intact
   - Verify Prometheus has historical metrics
   - Check Loki logs are available
   - Uptime-Kuma will be fresh (data was already lost)

3. **Check NAS directories**:
   ```bash
   ssh ubuntu@10.0.0.60 "ls -lh /mnt/nas/"
   ```

## Post-Migration Tasks

### Optional: Clean Up Old Volumes

After confirming migration success and services are running properly:

```bash
# On each client (10.0.0.60, 10.0.0.61, 10.0.0.62)
ssh ubuntu@<client-ip> "sudo rm -rf /opt/nomad-volumes/grafana_data"
ssh ubuntu@<client-ip> "sudo rm -rf /opt/nomad-volumes/prometheus_data"
ssh ubuntu@<client-ip> "sudo rm -rf /opt/nomad-volumes/loki_data"
```

### Update Uptime-Kuma Configuration

Since Uptime-Kuma data was lost, reconfigure:
1. Access http://uptime-kuma.service.consul:3001
2. Create new admin account
3. Re-add monitoring endpoints
4. Create status page with slug "default" (for Homepage widget)

## Rollback Plan

If migration fails:

1. **Stop Nomad on affected client**:
   ```bash
   ssh ubuntu@<client-ip> "sudo systemctl stop nomad"
   ```

2. **Restore old configuration**:
   ```bash
   # Manually edit /etc/nomad.d/nomad.hcl to use old paths
   # Or re-run Ansible with reverted template
   ```

3. **Restart Nomad**:
   ```bash
   ssh ubuntu@<client-ip> "sudo systemctl start nomad"
   ```

4. **Redeploy services with old job files** (if needed)

## Future Considerations

### Backup Strategy

With all data on NAS:
- **NAS-level backups**: Configure PVE-VM-Storage snapshots
- **Service-level exports**: Schedule regular Grafana dashboard exports
- **Database dumps**: Export Prometheus/Loki data periodically

### Monitoring Storage

Add alerts for NAS storage capacity:
- Prometheus node_exporter metrics for `/mnt/nas`
- Grafana dashboard showing NAS disk usage trends
- Alerts when usage exceeds 80%

### Documentation Updates

Services now using NAS storage:
- All production services have persistent data
- VM maintenance (HDD swaps, disk resizing) won't impact service data
- Only Nomad allocation ephemeral data (logs, task local/) is on VM disks

## Troubleshooting

### Issue: NAS not mounted on client

```bash
# Check NFS mount
ssh ubuntu@<client-ip> "sudo mount | grep nas"

# Remount if needed
ssh ubuntu@<client-ip> "sudo mount -a"
```

### Issue: Permission denied errors

```bash
# Check NAS directory permissions
ssh ubuntu@<client-ip> "ls -ld /mnt/nas/*"

# Fix if needed (run as root on NAS or via client)
sudo chown -R root:root /mnt/nas/grafana
sudo chmod -R 755 /mnt/nas/grafana
```

### Issue: Service won't start after migration

```bash
# Check Nomad logs
nomad alloc logs <alloc-id>

# Verify volume mount in allocation
nomad alloc status <alloc-id>

# Check host volume exists on client
ssh ubuntu@<client-ip> "ls -lh /mnt/nas/"
```

## Summary

✅ **Before**: 4 services on vulnerable VM disk storage  
✅ **After**: All 9 services on persistent NAS storage  
✅ **Result**: Data survives VM maintenance, HDD swaps, and infrastructure changes  

---
*Migration completed: [Date]*  
*Migration playbook: `ansible/playbooks/migrate-to-nas-storage.yml`*
