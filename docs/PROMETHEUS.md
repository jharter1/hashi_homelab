# Prometheus - Monitoring & Metrics

**Last Updated**: February 15, 2026  
**Current Version**: prom/prometheus:latest  
**Status**: ✅ Deployed successfully with host volumes

## Overview

Prometheus is deployed as a Nomad service job for metrics collection and monitoring across the homelab cluster.

**Key Implementation Details:**
- **Storage**: Host volumes (`/mnt/nas/prometheus_data`)
- **Network**: Host mode for direct access to node metrics
- **Configuration**: External YAML file on NAS (Phase 1 externalization)
- **Service Discovery**: Consul SD for automatic target discovery
- **Data Retention**: 90 days (configurable)

**Why Host Volumes?**
After 50+ failed deployment attempts with Docker volumes, host volumes solved permission issues permanently. See [Deployment History](#deployment-history) for details.

---

## Current Deployment

### Architecture

**Nomad Job**: `jobs/services/observability/prometheus/prometheus.nomad.hcl`  
**Config File**: `/mnt/nas/configs/observability/prometheus/prometheus.yml`  
**Data Storage**: `/mnt/nas/prometheus_data` (NFS mount)  
**Access**: `http://prometheus.home` (via Traefik) or `http://10.0.0.60:9090` (direct)

### Job Configuration

```hcl
job "prometheus" {
  type = "service"
  
  group "monitoring" {
    count = 1
    
    # Host volume for persistent data
    volume "prometheus_data" {
      type      = "host"
      source    = "prometheus_data"
      read_only = false
    }
    
    # Configuration volume (external)
    volume "prometheus_config" {
      type      = "host"
      source    = "prometheus_config"
      read_only = true
    }
    
    network {
      mode = "host"
      port "http" { static = 9090 }
    }
    
    task "prometheus" {
      driver = "docker"
      
      volume_mount {
        volume      = "prometheus_data"
        destination = "/prometheus"
      }
      
      volume_mount {
        volume      = "prometheus_config"
        destination = "/etc/prometheus"
      }
      
      config {
        image        = "prom/prometheus:latest"
        network_mode = "host"
        args = [
          "--config.file=/etc/prometheus/prometheus.yml",
          "--storage.tsdb.path=/prometheus",
          "--web.listen-address=0.0.0.0:9090",
          "--storage.tsdb.retention.time=90d",
          "--web.console.libraries=/usr/share/prometheus/console_libraries",
          "--web.console.templates=/usr/share/prometheus/consoles",
        ]
      }
      
      resources {
        cpu    = 500
        memory = 512
      }
      
      service {
        name     = "prometheus"
        port     = "http"
        provider = "consul"
        
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.prometheus.rule=Host(`prometheus.home`)",
          "traefik.http.routers.prometheus.entrypoints=websecure",
          "traefik.http.routers.prometheus.tls=true",
        ]
        
        check {
          type     = "http"
          path     = "/-/healthy"
          interval = "10s"
          timeout  = "2s"
        }
      }
    }
  }
}
```

### Configuration File

External config at `/mnt/nas/configs/observability/prometheus/prometheus.yml`:

```yaml
global:
  scrape_interval: 30s
  evaluation_interval: 30s
  external_labels:
    cluster: 'homelab'
    environment: 'dev'

# Alertmanager integration
alerting:
  alertmanagers:
    - consul_sd_configs:
        - server: 'localhost:8500'
          services: ['alertmanager']

# Alert rules
rule_files:
  - '/etc/prometheus/alerts/*.yml'

# Scrape configurations
scrape_configs:
  # Prometheus self-monitoring
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
  
  # Consul service discovery for all registered services
  - job_name: 'consul-services'
    consul_sd_configs:
      - server: 'localhost:8500'
    relabel_configs:
      - source_labels: [__meta_consul_service]
        target_label: job
      - source_labels: [__meta_consul_node]
        target_label: instance
  
  # Node Exporter (if deployed)
  - job_name: 'node-exporter'
    consul_sd_configs:
      - server: 'localhost:8500'
        services: ['node-exporter']
  
  # Nomad metrics
  - job_name: 'nomad'
    consul_sd_configs:
      - server: 'localhost:8500'
        services: ['nomad', 'nomad-client']
    metrics_path: '/v1/metrics'
    params:
      format: ['prometheus']
```

### Host Volume Setup

**On each Nomad client**, host volumes are defined in `/etc/nomad.d/nomad.hcl`:

```hcl
client {
  enabled = true
  
  host_volume "prometheus_data" {
    path      = "/mnt/nas/prometheus_data"
    read_only = false
  }
  
  host_volume "prometheus_config" {
    path      = "/mnt/nas/configs/observability/prometheus"
    read_only = true
  }
}
```

**Directory permissions:**
```bash
# On NFS server or client
sudo mkdir -p /mnt/nas/prometheus_data
sudo chmod 777 /mnt/nas/prometheus_data  # Or chown 65534:65534 (prometheus user)
```

---

## Deployment History

### The Problem: 50+ Failed Deployments

**Symptoms:**
```
Error opening query log file... permission denied on /prometheus/queries.active
mkdir: cannot create directory '/prometheus': Permission denied
```

**Root Cause:**
- Nomad creates task directories as `root:root` with `755` permissions
- Prometheus Docker container runs as user `65534` (nobody/prometheus)
- Container user cannot write to root-owned directories
- Docker volume mounts (`volumes = ["local/data:/prometheus"]`) inherit Nomad's permissions

### Why Other Approaches Failed

| Approach | Why It Failed | Notes |
|----------|---------------|-------|
| **Docker volumes** | Permission mismatch | Nomad creates paths as root, container user can't write |
| **Lifecycle prestart hooks** | Unsupported in Nomad 1.10.3 | Requires Nomad 1.11+ |
| **Entrypoint scripts with chown** | Race conditions | Permissions reset on new allocations |
| **privileged=true** | Disabled by policy | Nomad agent blocks privileged containers |
| **Host volumes** ✅ | **Works perfectly** | Pre-created with proper permissions |

### The Solution: Host Volumes

Host volumes solve permission issues by:
1. **Pre-creation**: Directories exist before job runs
2. **Explicit permissions**: Set once, persist across restarts
3. **Nomad-managed**: Proper lifecycle management
4. **No privilege escalation**: Standard Docker user works
5. **Production-standard**: Used across many Nomad deployments

This is the **recommended approach** for persistent Prometheus data in Nomad.

---

## Common Issues & Troubleshooting

### Permission Denied on /prometheus

**Symptoms:**
```
level=error caller=main.go:123 msg="Error opening storage" err="open /prometheus: permission denied"
```

**Diagnosis:**
```bash
# Check directory ownership
ssh ubuntu@10.0.0.60 "ls -la /mnt/nas/prometheus_data"

# Check Nomad client config
ssh ubuntu@10.0.0.60 "grep -A 3 'host_volume \"prometheus_data\"' /etc/nomad.d/nomad.hcl"

# Check allocation logs
ALLOC_ID=$(nomad job allocs prometheus | grep running | head -1 | awk '{print $1}')
nomad alloc logs -stderr $ALLOC_ID
```

**Solutions:**

**Option 1: Fix directory permissions (simple)**
```bash
ssh ubuntu@10.0.0.60 "sudo chmod 777 /mnt/nas/prometheus_data"
```

**Option 2: Set container user ownership (secure)**
```bash
# Prometheus runs as UID 65534 (nobody)
ssh ubuntu@10.0.0.60 "sudo chown -R 65534:65534 /mnt/nas/prometheus_data"
```

**Option 3: Use prestart task (if Nomad 1.11+)**
```hcl
task "prep-disk" {
  driver = "docker"
  
  volume_mount {
    volume      = "prometheus_data"
    destination = "/volume/"
  }
  
  config {
    image   = "busybox:latest"
    command = "sh"
    args    = ["-c", "chown -R 65534:65534 /volume/"]
  }
  
  lifecycle {
    hook    = "prestart"
    sidecar = false
  }
  
  resources {
    cpu    = 100
    memory = 64
  }
}
```

---

### Host Volume Not Found

**Symptoms:**
```
Error: volume "prometheus_data" not found
```

**Diagnosis:**
```bash
# Check Nomad client config
ssh ubuntu@10.0.0.60 "cat /etc/nomad.d/nomad.hcl | grep -A 3 prometheus_data"

# Restart Nomad to reload config
ssh ubuntu@10.0.0.60 "sudo systemctl status nomad"
```

**Solution:**

1. **Add host volume to Nomad client config** (`/etc/nomad.d/nomad.hcl`):
   ```hcl
   host_volume "prometheus_data" {
     path      = "/mnt/nas/prometheus_data"
     read_only = false
   }
   ```

2. **Restart Nomad**:
   ```bash
   ssh ubuntu@10.0.0.60 "sudo systemctl restart nomad"
   ```

3. **Verify volume registration**:
   ```bash
   nomad node status -verbose <node-id> | grep -A 5 "Host Volumes"
   ```

---

### Configuration Changes Not Applied

**Symptoms:**
- Updated `prometheus.yml` but Prometheus still uses old config
- No errors in logs

**Diagnosis:**
```bash
# Check current config in container
ALLOC_ID=$(nomad job allocs prometheus | grep running | head -1 | awk '{print $1}')
nomad alloc exec $ALLOC_ID cat /etc/prometheus/prometheus.yml

# Check file on NAS
ssh ubuntu@10.0.0.60 "cat /mnt/nas/configs/observability/prometheus/prometheus.yml"
```

**Solutions:**

**Option 1: Reload via HTTP API**
```bash
curl -X POST http://10.0.0.60:9090/-/reload
```

**Option 2: Restart job**
```bash
nomad job restart prometheus
```

**Option 3: Use signal-based reload (if using templates)**
```hcl
template {
  destination = "local/prometheus.yml"
  change_mode = "signal"
  change_signal = "SIGHUP"
  data = <<EOH
# ... config ...
EOH
}
```

---

### Targets Not Discovered via Consul

**Symptoms:**
- Prometheus Targets page shows no Consul-discovered services
- Only static targets visible

**Diagnosis:**
```bash
# Check Consul is accessible
ALLOC_ID=$(nomad job allocs prometheus | grep running | head -1 | awk '{print $1}')
nomad alloc exec $ALLOC_ID nc -zv localhost 8500

# Check Consul services
consul catalog services

# Check Prometheus service discovery page
# Navigate to: http://prometheus.home/service-discovery
```

**Solutions:**

1. **Verify network mode is host**:
   ```hcl
   config {
     network_mode = "host"  # Required for localhost:8500 access
   }
   ```

2. **Check Consul SD config**:
   ```yaml
   consul_sd_configs:
     - server: 'localhost:8500'  # Or consul.service.consul:8500
   ```

3. **Verify services are registered**:
   ```bash
   consul catalog nodes -service=<service-name>
   ```

---

### High Memory Usage

**Symptoms:**
- Prometheus memory climbing over time
- OOM kills in Nomad logs

**Diagnosis:**
```bash
# Check current memory usage
ALLOC_ID=$(nomad job allocs prometheus | grep running | head -1 | awk '{print $1}')
nomad alloc status $ALLOC_ID | grep -A 5 "Resource Util"

# Check TSDB size
ssh ubuntu@10.0.0.60 "du -sh /mnt/nas/prometheus_data"
```

**Solutions:**

**Option 1: Reduce retention time**
```hcl
args = [
  "--storage.tsdb.retention.time=30d",  # Down from 90d
]
```

**Option 2: Set retention size limit**
```hcl
args = [
  "--storage.tsdb.retention.size=50GB",
]
```

**Option 3: Increase memory allocation**
```hcl
resources {
  memory = 1024  # Up from 512
}
```

**Option 4: Reduce scrape frequency**
```yaml
global:
  scrape_interval: 60s  # Up from 30s
```

---

## Configuration Management

### Making Config Changes

**Workflow:**
1. Edit config file locally: `configs/observability/prometheus/prometheus.yml`
2. Sync to cluster: `task configs:sync`
3. Reload Prometheus: `curl -X POST http://prometheus.home/-/reload`

**Example: Adding a new scrape target**
```yaml
scrape_configs:
  - job_name: 'my-new-app'
    consul_sd_configs:
      - server: 'localhost:8500'
        services: ['my-new-app']
    scrape_interval: 15s
    metrics_path: '/metrics'
```

### Validating Configuration

**Before deployment:**
```bash
# Validate YAML syntax
yamllint configs/observability/prometheus/prometheus.yml

# Validate Prometheus config (requires promtool)
docker run --rm -v $(pwd)/configs/observability/prometheus:/config \
  prom/prometheus:latest \
  promtool check config /config/prometheus.yml
```

**After deployment:**
```bash
# Check config loaded successfully
curl -s http://prometheus.home/api/v1/status/config | jq '.status'
# Expected: "success"

# Verify targets discovered
curl -s http://prometheus.home/api/v1/targets | jq '.data.activeTargets | length'
```

---

## Querying & Usage

### Common PromQL Queries

**Check service health:**
```promql
up{job="prometheus"}
```

**Node CPU usage:**
```promql
100 - (avg by (instance) (irate(node_cpu_seconds_total{mode="idle"}[5m])) * 100)
```

**Container memory usage:**
```promql
container_memory_usage_bytes{image!=""}
```

**Request rate by service:**
```promql
rate(http_requests_total[5m])
```

### HTTP API Examples

**Query current value:**
```bash
curl -G http://prometheus.home/api/v1/query \
  --data-urlencode 'query=up'
```

**Query range:**
```bash
curl -G http://prometheus.home/api/v1/query_range \
  --data-urlencode 'query=up' \
  --data-urlencode 'start=2026-02-15T00:00:00Z' \
  --data-urlencode 'end=2026-02-15T12:00:00Z' \
  --data-urlencode 'step=5m'
```

**List all metrics:**
```bash
curl http://prometheus.home/api/v1/label/__name__/values | jq '.data'
```

---

## Integration with Other Services

### Grafana

Prometheus is configured as a datasource in Grafana:

**Datasource config** (`configs/observability/grafana/datasources.yml`):
```yaml
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus.service.consul:9090
    isDefault: true
```

**Verification:**
```bash
curl -u admin:admin http://grafana.home/api/datasources | jq '.[] | select(.name=="Prometheus")'
```

### Alertmanager

Prometheus sends alerts to Alertmanager:

**Config** (in `prometheus.yml`):
```yaml
alerting:
  alertmanagers:
    - consul_sd_configs:
        - server: 'localhost:8500'
          services: ['alertmanager']
```

### Loki (for logs correlation)

Loki can be added as a secondary datasource in Grafana for logs/metrics correlation.

---

## Alternative Approaches

This section documents alternative deployment patterns researched from the community.

### CSI Volumes (Advanced)

**When to use:**
- Multi-cloud deployments
- Need volume portability
- Complex storage requirements

**Implementation:**
```hcl
volume "prometheus" {
  type            = "csi"
  source          = "prometheus"
  access_mode     = "multi-node-single-writer"
  attachment_mode = "file-system"
}
```

**Pros:**
- Managed storage backend
- Better scheduling flexibility
- Supports snapshots/backups

**Cons:**
- Requires CSI driver installation
- More complex setup
- May still need permission fixes

### Ephemeral Storage (Testing Only)

**When to use:**
- Demo/testing environments
- Non-critical metrics collection
- Temporary deployments

**Implementation:**
```hcl
# No volume declaration - uses local/ephemeral disk
ephemeral_disk {
  size = 1000  # MB
}
```

**Pros:**
- No permission issues
- Simple deployment
- Fast cleanup

**Cons:**
- ❌ Data lost on job restart
- ❌ Not suitable for production
- ❌ Limited retention capacity

### Templated User Configuration

**When to use:**
- Dynamic UID/GID per environment
- Multi-tenant deployments

**Implementation:**
```hcl
config {
  user = "${NOMAD_META_PUID}:${NOMAD_META_PGID}"
}
```

**Pros:**
- Flexible user assignment
- Environment-specific permissions

**Cons:**
- Requires meta variables setup
- More complex troubleshooting

---

## Best Practices

### ✅ DO

1. **Use host volumes** for persistent data
2. **Set retention policies** to prevent disk exhaustion
3. **Use Consul service discovery** for automatic target discovery
4. **Enable health checks** (/-/healthy endpoint)
5. **Monitor Prometheus itself** (self-scraping)
6. **Validate configs** before deployment
7. **Use network_mode=host** for simplicity
8. **Set resource limits** (CPU, memory)
9. **Back up TSDB data** periodically

### ❌ DON'T

1. **Don't use Docker volumes** (`volumes = ["local/data:/prometheus"]`)
2. **Don't run as privileged** (security risk)
3. **Don't skip retention settings** (disk will fill)
4. **Don't hardcode targets** (use Consul SD)
5. **Don't ignore OOM kills** (increase memory or reduce retention)
6. **Don't modify TSDB data manually** (corruption risk)
7. **Don't deploy without health checks**

---

## Performance Tuning

### Memory Optimization

**Rule of thumb**: ~6-8 bytes per sample

Calculate memory needs:
```
Active series × Samples/sec × Retention seconds × 6 bytes
```

**Example:**
- 10,000 active series
- 30s scrape interval (2 samples/min)
- 90 days retention

Memory: `10,000 × 2 × (90×24×60) × 6 ≈ 1.5 GB`

### Storage Optimization

**Compression**: Prometheus TSDB automatically compresses older blocks

**Retention strategies:**
```hcl
args = [
  "--storage.tsdb.retention.time=90d",    # Keep 90 days
  "--storage.tsdb.retention.size=150GB",  # Or max 150GB
  # Whichever limit hits first
]
```

### Scrape Optimization

**Reduce cardinality:**
```yaml
metric_relabel_configs:
  - source_labels: [__name__]
    regex: 'high_cardinality_metric_.*'
    action: drop
```

**Longer intervals for slow-changing metrics:**
```yaml
scrape_configs:
  - job_name: 'slow-metrics'
    scrape_interval: 5m  # Instead of default 30s
```

---

## Backup & Recovery

### Backup TSDB Data

**Snapshot via API:**
```bash
curl -X POST http://prometheus.home/api/v1/admin/tsdb/snapshot
```

**Manual backup:**
```bash
# Stop Prometheus first
nomad job stop prometheus

# Backup data directory
ssh ubuntu@10.0.0.60 "tar -czf prometheus_backup_$(date +%Y%m%d).tar.gz -C /mnt/nas prometheus_data"

# Restart
nomad job run jobs/services/observability/prometheus/prometheus.nomad.hcl
```

### Restore from Backup

```bash
# Stop current Prometheus
nomad job stop prometheus

# Restore data
ssh ubuntu@10.0.0.60 "rm -rf /mnt/nas/prometheus_data/*"
scp prometheus_backup_20260215.tar.gz ubuntu@10.0.0.60:/tmp/
ssh ubuntu@10.0.0.60 "sudo tar -xzf /tmp/prometheus_backup_20260215.tar.gz -C /mnt/nas/"

# Restart
nomad job run jobs/services/observability/prometheus/prometheus.nomad.hcl
```

---

## Related Documentation

- [PHASE1.md](PHASE1.md) - Config externalization (includes Prometheus migration)
- [Grafana Integration](NEW_SERVICES_DEPLOYMENT.md) - Datasource setup
- [Alertmanager](NEW_SERVICES_DEPLOYMENT.md) - Alert routing configuration
- [TROUBLESHOOTING.md](TROUBLESHOOTING.md) - General troubleshooting guide

### External References

For detailed research on alternative Prometheus deployment patterns in Nomad, see:
- [Research: Prometheus Nomad Implementations](archive/PROMETHEUS_NOMAD_RESEARCH.md) - Analysis of 7 production deployments

---

**Deployment Status**: ✅ **Production-ready with host volumes**  
**Recommended Pattern**: Host volumes + Consul service discovery + external configs
