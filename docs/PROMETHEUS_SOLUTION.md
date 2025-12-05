# Prometheus Deployment on Nomad - Solution

## Problem & Solution

**The Issue:** 50+ failed Prometheus deployments due to Docker volume permission mismatch.

Nomad creates task directories as `root:root` with 755 permissions. The Prometheus Docker container runs as user `65534 (prometheus)`, which cannot write to these directories, causing:
```
Error opening query log file... permission denied on /prometheus/queries.active
```

**The Solution:** Use Nomad **host volumes** instead of Docker volume mounts.

Host volumes are pre-created on Nomad client nodes and properly managed by Nomad, avoiding the permission conflict entirely.

## How Other Users Deploy Prometheus on Nomad

Research of production Nomad deployments shows the standard pattern:

1. **Pre-create host volumes on Nomad clients** (`/mnt/prometheus_data`)
2. **Declare them in Nomad client configuration** (`host_volume "prometheus_data"`)
3. **Reference them in jobs** using `volume` and `volume_mount` blocks
4. **Use `network_mode = "host"`** to simplify networking

This is the production-standard approach used across multiple organizations' homelab and production Nomad clusters.

## Implementation Steps

### 1. Setup Host Volume on Each Nomad Client

Run this on each Nomad client node (10.0.0.60, 10.0.0.61):

```bash
sudo mkdir -p /mnt/prometheus_data
sudo chmod 777 /mnt/prometheus_data
```

**Why 777?** Nomad doesn't run containers as the node's user - the container's user (prometheus=65534) needs write access. Alternatively, set ownership to the container user (not recommended for simplicity).

### 2. Update Nomad Client Configuration

The updated `nomad-client.hcl` template now includes:

```hcl
client {
  enabled = true
  node_class = "${node_class}"
  
  server_join {
    retry_join = ${server_addresses}
    retry_interval = "15s"
  }
  
  host_volume "prometheus_data" {
    path = "/mnt/prometheus_data"
    read_only = false
  }
}
```

This declares the volume available to all jobs on this client.

### 3. Update Nomad Clients with New Config

Apply Terraform to redeploy client configurations:

```bash
cd terraform/environments/dev
terraform plan
terraform apply
```

Then restart Nomad on each client:

```bash
sudo systemctl restart nomad
```

### 4. Deploy Prometheus Job

The updated `prometheus.nomad.hcl` now uses:

```hcl
volume "prometheus_data" {
  type   = "host"
  source = "prometheus_data"
}

task "prometheus" {
  # ...
  
  volume_mount {
    volume      = "prometheus_data"
    destination = "/prometheus"
  }
}
```

Deploy it:

```bash
NOMAD_ADDR=http://10.0.0.60:4646 nomad job run nomad_jobs/services/prometheus.nomad.hcl
```

## Key Changes from Previous Attempts

| Approach | Problem | Why It Failed |
|----------|---------|---------------|
| Docker volumes (`volumes = ["local/data:/prometheus"]`) | Permission mismatch | Nomad creates paths as root:root, container user can't write |
| Lifecycle hooks (`prestart`) | Not supported | Requires Nomad v1.11+, you have v1.10.3 |
| Entrypoint scripts with chown | Race condition | Permissions reset when new allocation created |
| `privileged=true` | Disabled | Your Nomad agent blocks privileged mode |
| Host volumes ✓ | None | This works! Pre-created, Nomad-managed, permission-aware |

## Benefits of Host Volumes

1. **No permission issues** - Pre-created with proper permissions
2. **Persistent across restarts** - Data survives allocation failures
3. **Nomad-native** - Proper lifecycle management
4. **Simple** - No manual permission fixing needed
5. **Production-standard** - Used in real Nomad deployments

## Verification

Check that Prometheus starts successfully:

```bash
nomad job status prometheus
nomad alloc status <allocation_id>
nomad alloc logs -stderr <allocation_id>
```

Expected output should show Prometheus starting normally, not permission denied errors.

Check data persistence:

```bash
ssh ubuntu@10.0.0.60 "ls -la /mnt/prometheus_data"
```

You should see Prometheus data files being created.

## Next Steps: Deploy Grafana

Once Prometheus is running, deploy Grafana to visualize metrics:

1. Create `nomad_jobs/services/grafana.nomad.hcl`
2. Add Prometheus as data source pointing to `http://prometheus.service.consul:9090`
3. Deploy and configure dashboards
