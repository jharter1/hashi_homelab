# Prometheus Nomad Job Implementations - Research Report

## Overview
This document contains findings from analyzing 7 different Prometheus Nomad job definitions from GitHub repositories, with a focus on volume mounting, permission handling, and Docker configuration best practices.

---

## 1. **datasektionen/infra** - Production-Ready with Host Volumes
**Repository**: https://github.com/datasektionen/infra  
**File**: `jobs/monitoring/prometheus.nomad.hcl`  
**Stars**: N/A (Organization)

### Key Configuration Details

#### Volume Mounting Strategy
```hcl
volume "data" {
  type = "host"
  source = "prometheus/data"
}

volume_mount {
  volume = "data"
  destination = "/prometheus"
}
```

#### Docker Configuration
- **Image**: `prom/prometheus:v3.6.0`
- **Network Mode**: Not specified (bridge default)
- **CPU/Memory**: 60 CPU, 100 MB
- **Arguments**: Uses Nomad service discovery with TLS

#### Special Features
- Uses Nomad Service Discovery (nomad_sd_configs)
- Template-based configuration
- TLS certificate mounting for secure Nomad API access
- Integrated Traefik service tags for routing

#### Permission Handling
- ✅ No explicit permission issues mentioned
- Uses default Prometheus container user (65534:65534 - nobody)
- Host volume ownership managed by Docker

---

## 2. **aldoborrero/hashi-homelab** - Multi-Site Deployment
**Repository**: https://github.com/aldoborrero/hashi-homelab  
**File**: `recipes/prometheus/nomad.job`  
**Description**: Hashicorp Homelab with multiple services

### Key Configuration Details

#### Volume Mounting Strategy
```hcl
volumes = [
  "[[ .app.prometheus.volumes.data ]]:/data",
]
```

#### Docker Configuration
- **Image**: `prom/prometheus:v2.24.0`
- **Network Mode**: `host` (important!)
- **Static Port**: 9090
- **User**: `[[ .common.env.puid ]]` (templated, often 1000:1000)
- **Arguments**:
  ```
  --config.file /local/prometheus.yml
  --storage.tsdb.path /data
  --web.listen-address 0.0.0.0:9090
  ```

#### Special Features
- Uses Consul service discovery
- Host network mode for direct host metrics access
- HTTP/HTTPS Traefik routing with redirects
- Health checks with `/-/healthy` endpoint
- Configuration change detection with SIGHUP signal

#### Permission Handling
- ✅ **Explicitly sets user**: `user = "[[ .common.env.puid ]]"`
- Uses templating for dynamic user/group assignment
- Host volume path: `[[ .app.prometheus.volumes.data ]]` (typically `/data` on host)

---

## 3. **perrymanuk/hashi-homelab** - CSI Volume Solution (BEST PRACTICE)
**Repository**: https://github.com/perrymanuk/hashi-homelab  
**File**: `nomad_jobs/observability/prometheus/nomad.job`  
**Description**: Small lightweight homelab with advanced volume handling

### Key Configuration Details

#### Volume Mounting Strategy - CSI Volume
```hcl
volume "prometheus" {
  type      = "csi"
  read_only = false
  source    = "prometheus"
  access_mode = "multi-node-single-writer"
  attachment_mode = "file-system"
}
```

#### Permission Workaround - Prestart Task
```hcl
task "prep-disk" {
  driver = "docker"
  volume_mount {
    volume      = "prometheus"
    destination = "/volume/"
    read_only   = false
  }
  config {
    image        = "busybox:latest"
    command      = "sh"
    args         = ["-c", "chown -R 1000:2000 /volume/"]
  }
  
  lifecycle {
    hook    = "prestart"
    sidecar = false
  }
}
```

#### Docker Configuration
- **Image**: `prom/prometheus:v3.7.3`
- **Network Mode**: `host`
- **User**: `1000:2000` (Prometheus user:group)
- **Arguments**:
  ```
  --storage.tsdb.path /opt/prometheus
  --web.listen-address 0.0.0.0:9090
  --storage.tsdb.retention.time 90d
  ```

#### Volume Mount in Main Task
```hcl
volume_mount {
  volume      = "prometheus"
  destination = "/opt/prometheus"
  read_only   = false
}
```

#### Special Features
- ✅ **Solves Permission Issues with Prestart Task**
- CSI volume for persistent storage
- Job constraints: `meta.shared_mount = "true"`
- Comprehensive alert rules with 15+ alert conditions
- Consul service discovery integration
- Home Assistant integration for additional metrics

#### Permission Handling - KEY INNOVATION
- **Problem**: Permission denied on CSI volume when Prometheus user doesn't own the directory
- **Solution**: Use `prestart` lifecycle task with busybox to fix ownership BEFORE main container starts
- **Result**: No more permission denied errors on `/prometheus`

#### Health Checks
```hcl
check {
  type     = "http"
  path     = "/-/healthy"
  interval = "5s"
  timeout  = "2s"
}
```

---

## 4. **mutablelogic/tf-nomad** - Parameterized Configuration
**Repository**: https://github.com/mutablelogic/tf-nomad  
**File**: `prometheus/nomad/prometheus.hcl`  
**Description**: Terraform-based Nomad configuration

### Key Configuration Details

#### Volume Mounting Strategy
```hcl
volumes = compact([
  var.data == "" ? "" : format("%s:/prometheus", var.data),
  "local:/etc/prometheus",
])
```

#### Docker Configuration
- **Image**: Variable-based (parameterized)
- **Volumes**: Dynamic based on variables
- **Arguments**:
  ```
  --config.file=/etc/prometheus/prometheus.yml
  --storage.tsdb.path=/prometheus
  ```

#### Variables Available
```hcl
variable "data" {
  description = "Data persistence directory"
  type        = string
  default     = ""
}

variable "targets" {
  description = "Targets for the prometheus job"
  type        = map(object({
    interval     = string
    path         = string
    scheme       = string
    bearer_token = string
    targets      = list(string)
  }))
}
```

#### Special Features
- ✅ Highly parameterized for multi-environment deployment
- Supports multiple target configurations
- Flexible host constraints
- Distinct host enforcement
- Clean separation of concerns with variables

#### Permission Handling
- No explicit user specification
- Relies on default Prometheus container user
- Data volume path specified via variable

---

## 5. **hashicorp/nomad-autoscaler-demos** - Official HashiCorp Example
**Repository**: https://github.com/hashicorp/nomad-autoscaler-demos  
**File**: `vagrant/horizontal-app-scaling/jobs/prometheus.nomad`  
**Description**: HashiCorp's official Nomad Autoscaler demo

### Key Configuration Details

#### Volume Mounting Strategy
```hcl
volumes = [
  "local/config:/etc/prometheus/config",
]
```

#### Docker Configuration
- **Image**: `prom/prometheus:v2.38.0`
- **Network Mode**: `host`
- **Arguments**:
  ```
  --config.file=/etc/prometheus/config/prometheus.yml
  --storage.tsdb.path=/prometheus
  --web.listen-address=0.0.0.0:{port}
  --web.console.libraries=/usr/share/prometheus/console_libraries
  --web.console.templates=/usr/share/prometheus/consoles
  ```

#### Special Features
- ✅ Official HashiCorp example - best practices
- Nomad Service Discovery (nomad_sd_configs)
- Dynamic template-based configuration
- Configuration reloading with SIGHUP signal
- Built-in Traefik integration

#### Permission Handling
- No persistent data volume (ephemeral only)
- ✅ No permission issues since no persistent storage
- Configuration stored in local task directory

---

## 6. **GuyBarros/nomad_jobs** - Enterprise-Scale Multi-Datacenter
**Repository**: https://github.com/GuyBarros/nomad_jobs  
**File**: `prometheus.nomad.tpl`  
**Description**: Multi-datacenter enterprise setup

### Key Configuration Details

#### Docker Configuration
- **Image**: `prom/prometheus`
- **Network Mode**: `host`
- **Retention**: `--storage.tsdb.retention.size=150GB`
- **Arguments**:
  ```
  --web.external-url={fabio_url}/prometheus
  --web.route-prefix=/
  --config.file=/etc/prometheus/prometheus.yml
  ```

#### Volume Mounting Strategy
```hcl
volumes = [
  "local/prometheus.yml:/etc/prometheus/prometheus.yml"
]
```

#### Special Features
- Multi-datacenter deployment: 7 datacenters supported
- Fabio load balancer integration
- Vault integration for security policies
- Complex metric relabeling configurations
- Combined Prometheus + Grafana job

#### Permission Handling
- No explicit persistent volume
- Configuration only (ephemeral data)
- Uses local/ephemeral_disk for storage (300MB)

---

## 7. **slpcat/docker-images** - Monitoring Stack Complete Setup
**Repository**: https://github.com/slpcat/docker-images  
**File**: `monitoring/prometheus/prometheus.nomad`  
**Description**: Docker images repository with monitoring examples

### Key Configuration Details

#### Docker Configuration
- **Image**: `prom/prometheus:latest`
- **Network Mode**: Not specified (defaults to bridge)
- **Resource Limits**: 500 CPU, 1024 MB memory
- **Advanced Networking**: Custom sysctl tuning

#### Volume Mounting Strategy
```hcl
volumes = [
  "local/webserver_alert.yml:/etc/prometheus/webserver_alert.yml",
  "local/prometheus.yml:/etc/prometheus/prometheus.yml"
]
```

#### Special Features
- ✅ Extensive sysctl tuning for performance
- Alert rules defined inline
- Consul service discovery
- Alertmanager integration
- Comprehensive logging configuration (5 files, 20MB each)

#### Permission Handling
- Configuration volumes only (templates)
- No persistent data storage issues
- Default container permissions sufficient

---

## Summary Comparison Table

| Repository | Volume Type | Permission Handling | Network Mode | Data Persistence |
|------------|-------------|-------------------|--------------|------------------|
| datasektionen | Host Volume | Default | Bridge | Yes |
| aldoborrero | Host Volume | **User Template** | Host | Yes |
| perrymanuk | **CSI Volume** | **Prestart Chown Task** ✅ | Host | Yes |
| mutablelogic | Variable | Default | Bridge | Optional |
| hashicorp | Local Only | N/A | Host | Ephemeral |
| GuyBarros | Local Only | N/A | Host | Ephemeral |
| slpcat | Local Only | N/A | Bridge | Ephemeral |

---

## Key Findings & Recommendations

### 1. **Best Practice for Permission Issues: Prestart Lifecycle Hook**
The **perrymanuk/hashi-homelab** implementation provides the most robust solution:
- Uses a `prestart` lifecycle task to fix ownership before container starts
- Prevents permission denied errors entirely
- Works with any volume type (CSI, host, etc.)

```hcl
task "prep-disk" {
  driver = "docker"
  volume_mount {
    volume = "prometheus"
    destination = "/volume/"
  }
  config {
    image = "busybox:latest"
    command = "sh"
    args = ["-c", "chown -R 1000:2000 /volume/"]
  }
  lifecycle {
    hook = "prestart"
    sidecar = false
  }
}
```

### 2. **Volume Mounting Options**

#### Option A: Host Volumes (Simple, Portable)
```hcl
volume "data" {
  type = "host"
  source = "prometheus/data"
}
```
- Pros: Simple, doesn't require CSI plugin
- Cons: Requires host filesystem setup, less flexible

#### Option B: CSI Volumes (Recommended for Production)
```hcl
volume "prometheus" {
  type = "csi"
  source = "prometheus"
  access_mode = "multi-node-single-writer"
  attachment_mode = "file-system"
}
```
- Pros: Managed storage, better scheduling, supports multiple backends
- Cons: Requires CSI driver plugin installation

### 3. **Docker Configuration Best Practices**

#### Network Mode Selection
- **Host Mode** (`network_mode = "host"`): For scraping local Nomad/system metrics
- **Bridge Mode** (default): For isolated services, less performance overhead

#### User/Group Specification
```hcl
user = "1000:2000"  # uid:gid format
```
Prometheus container typically needs UID 1000+ to avoid permission conflicts.

### 4. **Configuration Management**

#### Template with Signal Reload
```hcl
template {
  data = <<EOH
    # config content
  EOH
  destination = "local/prometheus.yml"
  change_mode = "signal"
  change_signal = "SIGHUP"
}
```
Allows live configuration updates without service restart.

#### Static Configuration
```hcl
volumes = [
  "local/prometheus.yml:/etc/prometheus/prometheus.yml"
]
```
Simpler but requires job restart for config changes.

### 5. **Storage Retention Strategies**

| Strategy | Use Case | Example |
|----------|----------|---------|
| Time-based | Long-term storage | `--storage.tsdb.retention.time=90d` |
| Size-based | Resource-constrained | `--storage.tsdb.retention.size=150GB` |
| Combined | Balanced approach | Both flags set |
| Ephemeral | Testing/demo | No persistence flag |

---

## Troubleshooting Permission Issues

### Problem 1: Permission Denied on /prometheus
**Symptoms**: 
```
mkdir: cannot create directory '/prometheus': Permission denied
```

**Solution 1: Prestart Chown Task** (Best Practice)
```hcl
task "prep-disk" {
  driver = "docker"
  volume_mount { volume = "prometheus"; destination = "/volume/" }
  config {
    image = "busybox:latest"
    args = ["-c", "chown -R 1000:2000 /volume/"]
  }
  lifecycle { hook = "prestart"; sidecar = false }
}
```

**Solution 2: Set Container User**
```hcl
user = "1000:2000"
```

**Solution 3: Volume-Level Permissions**
Ensure host directory has correct permissions before job launch:
```bash
chmod 777 /path/to/prometheus/data
# or
chown 1000:2000 /path/to/prometheus/data
```

### Problem 2: Port Already in Use
**Solution**: Use dynamic ports in Nomad
```hcl
network {
  port "http" {}  # Dynamic assignment
}
```

### Problem 3: Configuration Changes Not Applied
**Solution**: Use signal-based reload
```hcl
change_mode = "signal"
change_signal = "SIGHUP"
```

---

## Implementation Template

Based on all findings, here's a recommended Prometheus Nomad job template:

```hcl
job "prometheus" {
  type = "service"
  
  group "monitoring" {
    count = 1
    
    # CSI Volume for persistent storage
    volume "prometheus" {
      type      = "csi"
      source    = "prometheus"
      access_mode = "multi-node-single-writer"
      attachment_mode = "file-system"
    }
    
    network {
      port "http" { static = 9090 }
    }
    
    # Fix permissions prestart
    task "prep-disk" {
      driver = "docker"
      volume_mount {
        volume = "prometheus"
        destination = "/volume/"
      }
      config {
        image = "busybox:latest"
        args = ["-c", "chown -R 1000:2000 /volume/"]
      }
      lifecycle {
        hook = "prestart"
        sidecar = false
      }
      resources {
        cpu = 100
        memory = 64
      }
    }
    
    # Main Prometheus task
    task "prometheus" {
      driver = "docker"
      user = "1000:2000"
      
      volume_mount {
        volume = "prometheus"
        destination = "/prometheus"
      }
      
      config {
        image = "prom/prometheus:latest"
        network_mode = "host"
        args = [
          "--config.file=/etc/prometheus/prometheus.yml",
          "--storage.tsdb.path=/prometheus",
          "--web.listen-address=0.0.0.0:9090",
          "--storage.tsdb.retention.time=90d"
        ]
        volumes = [
          "local/prometheus.yml:/etc/prometheus/prometheus.yml"
        ]
      }
      
      template {
        destination = "local/prometheus.yml"
        change_mode = "signal"
        change_signal = "SIGHUP"
        data = <<EOH
global:
  scrape_interval: 30s
  evaluation_interval: 30s

scrape_configs:
  - job_name: 'prometheus'
    static_configs:
      - targets: ['localhost:9090']
EOH
      }
      
      resources {
        cpu = 500
        memory = 512
      }
      
      service {
        name = "prometheus"
        port = "http"
        provider = "nomad"
        check {
          type = "http"
          path = "/-/healthy"
          interval = "10s"
          timeout = "2s"
        }
      }
    }
  }
}
```

---

## References

- **datasektionen/infra**: https://github.com/datasektionen/infra/blob/master/jobs/monitoring/prometheus.nomad.hcl
- **aldoborrero/hashi-homelab**: https://github.com/aldoborrero/hashi-homelab/blob/master/recipes/prometheus/nomad.job
- **perrymanuk/hashi-homelab**: https://github.com/perrymanuk/hashi-homelab/blob/master/nomad_jobs/observability/prometheus/nomad.job
- **mutablelogic/tf-nomad**: https://github.com/mutablelogic/tf-nomad/blob/master/prometheus/nomad/prometheus.hcl
- **hashicorp/nomad-autoscaler-demos**: https://github.com/hashicorp/nomad-autoscaler-demos/blob/main/vagrant/horizontal-app-scaling/jobs/prometheus.nomad
- **GuyBarros/nomad_jobs**: https://github.com/GuyBarros/nomad_jobs/blob/master/prometheus.nomad.tpl
- **slpcat/docker-images**: https://github.com/slpcat/docker-images/blob/master/monitoring/prometheus/prometheus.nomad

