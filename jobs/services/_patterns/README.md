# Nomad Service Patterns

This directory documents the common architectural patterns used across our 22+ production services. Use these patterns when creating new services to maintain consistency and enable better AI code generation.

## Pattern 1: PostgreSQL-Backed Service

**Used by:** 14+ services (grafana, uptime-kuma, vaultwarden, speedtest, freshrss, gitea, authelia, etc.)

**Characteristics:**
- Uses centralized PostgreSQL database
- Vault workload identity for secret injection
- Consul service discovery for DB connection
- Host network mode with static ports
- Traefik ingress with Authelia SSO
- NFS host volumes for persistent data

**Example:** See [`../observability/grafana/grafana.nomad.hcl`](../observability/grafana/grafana.nomad.hcl)

**Key Components:**
```hcl
job "service-name" {
  datacenters = ["dc1"]
  type        = "service"

  group "service-name" {
    count = 1

    network {
      mode = "host"
      port "http" { static = 3000 }  # Service-specific port
    }

    volume "service_data" {
      type      = "host"
      read_only = false
      source    = "service_data"  # Pre-provisioned by Ansible
    }

    task "service-name" {
      driver = "docker"

      vault {}  # Enable Vault workload identity

      config {
        image        = "vendor/image:latest"
        network_mode = "host"
        ports        = ["http"]
        dns_servers  = ["10.0.0.10", "1.1.1.1"]
      }

      volume_mount {
        volume      = "service_data"
        destination = "/var/lib/data"
      }

      # Vault template for database password
      template {
        destination = "secrets/db.env"
        env         = true
        data        = <<EOH
GF_DATABASE_PASSWORD={{ with secret "secret/data/postgres/service" }}{{ .Data.data.password }}{{ end }}
GF_DATABASE_HOST=postgresql.home:5432
EOH
      }

      service {
        name = "service-name"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.service.rule=Host(`service.lab.hartr.net`)",
          "traefik.http.routers.service.entrypoints=websecure",
          "traefik.http.routers.service.tls=true",
          "traefik.http.routers.service.tls.certresolver=letsencrypt",
          "traefik.http.routers.service.middlewares=authelia@file",
        ]
      }

      resources {
        cpu    = 500
        memory = 512
      }
    }
  }
}
```

---

## Pattern 2: Simple Host Volume Service

**Used by:** 6 services (minio, loki, prometheus, alertmanager, homepage, calibre)

**Characteristics:**
- No database dependency (self-contained)
- Static configuration or file-based storage
- Host volumes for data persistence
- Embedded configs via template blocks
- Traefik ingress (some without Authelia)

**Example:** See [`../observability/prometheus/prometheus.nomad.hcl`](../observability/prometheus/prometheus.nomad.hcl)

**Key Components:**
```hcl
job "service-name" {
  datacenters = ["dc1"]
  type        = "service"
  priority    = 60  # Higher priority for infrastructure services

  group "service-name" {
    count = 1

    network {
      mode = "host"
      port "http" { static = 9090 }
    }

    volume "service_data" {
      type   = "host"
      source = "service_data"
    }

    task "service-name" {
      driver = "docker"

      config {
        image        = "vendor/image:latest"
        network_mode = "host"
        ports        = ["http"]
        args         = ["--config.file=/etc/config.yml"]
        volumes      = ["local/config.yml:/etc/config.yml"]
      }

      volume_mount {
        volume      = "service_data"
        destination = "/data"
      }

      # Embedded configuration
      template {
        destination = "local/config.yml"
        data        = <<EOH
# Service-specific YAML config
server:
  port: 9090
EOH
      }

      service {
        name = "service-name"
        port = "http"
        tags = [
          "traefik.enable=true",
          "traefik.http.routers.service.rule=Host(`service.home`)",
        ]
      }
    }
  }
}
```

---

## Pattern 3: Multi-Container Service (Sidecars)

**Used by:** Services requiring multiple coordinated containers (main + UI/proxy/sidecar)

**Characteristics:**
- Multiple tasks in a single group
- Shared network namespace
- Service mesh pattern (main + UI/proxy)
- Separate Traefik routes per container

**Example:** Harbor (registry with UI), FreshRSS (app + cron)

**Key Components:**
```hcl
job "service-name" {
  group "service-group" {
    count = 1

    network {
      mode = "host"
      port "main"  { static = 5000 }
      port "sidecar" { static = 5001 }
    }

    task "main-service" {
      driver = "docker"
      config {
        image = "vendor/main:latest"
        network_mode = "host"
        ports = ["main"]
      }
      service {
        name = "main-service"
        port = "main"
        tags = ["traefik.enable=true", ...]
      }
    }

    task "ui-sidecar" {
      driver = "docker"
      config {
        image = "vendor/ui:latest"
        network_mode = "host"
        ports = ["sidecar"]
      }
      env {
        REGISTRY_URL = "http://localhost:5000"
      }
      service {
        name = "ui-service"
        port = "sidecar"
        tags = ["traefik.enable=true", ...]
      }
    }
  }
}
```

---

## Common Configuration Elements

### Traefik Integration

All production services use this Traefik tag pattern:
```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.SERVICE.rule=Host(`SERVICE.lab.hartr.net`)",
  "traefik.http.routers.SERVICE.entrypoints=websecure",
  "traefik.http.routers.SERVICE.tls=true",
  "traefik.http.routers.SERVICE.tls.certresolver=letsencrypt",
  "traefik.http.routers.SERVICE.middlewares=authelia@file",  # SSO-protected
]
```

### Vault Secret Injection

Standard pattern for PostgreSQL credentials:
```hcl
vault {}  # Enable workload identity in task block

template {
  destination = "secrets/db.env"
  env         = true
  data        = <<EOH
DB_PASSWORD={{ with secret "secret/data/postgres/SERVICE" }}{{ .Data.data.password }}{{ end }}
DB_HOST={{ range service "postgresql" }}{{ .Address }}{{ end }}:5432
EOH
}
```

### DNS Configuration

Services requiring DNS resolution of local hostnames:
```hcl
config {
  dns_servers = ["10.0.0.10", "1.1.1.1"]  # Consul DNS + Cloudflare fallback
}
```

### Resource Allocation

**Default resources** (adjust based on monitoring):
```hcl
resources {
  cpu    = 500   # MHz
  memory = 512   # MB (increase for heavy services: Grafana=1024, Seafile=2048)
}
```

---

## Service Organization

Services are organized by functional category:

```
jobs/services/
├── observability/    # Monitoring: Prometheus, Grafana, Loki, Alertmanager, Uptime Kuma
├── databases/        # Data stores: PostgreSQL, MariaDB
├── auth/             # Security: Authelia, Redis, Vaultwarden
├── media/            # Content: FreshRSS, Calibre, Audiobookshelf, Seafile
├── development/      # Dev tools: Gitea, Gollum, Code Server, Docker Registry
└── infrastructure/   # Core services: MinIO, Homepage, Speedtest, Whoami
```

---

## Creating a New Service

1. **Choose a pattern** based on requirements (database? storage only? multi-container?)
2. **Create directory**: `jobs/services/<category>/<service-name>/`
3. **Copy reference job** from the pattern's example
4. **Customize**:
   - Job/group/task names
   - Container image
   - Port allocation (check [../../../docs/CHEATSHEET.md](../../../docs/CHEATSHEET.md) for used ports)
   - Volume names (must be pre-provisioned by Ansible in `/mnt/nas/`)
   - Vault secret paths (create secrets via `scripts/setup-*.fish`)
   - Traefik routes and middleware
5. **Update Ansible** [`ansible/roles/base-system/tasks/main.yml`](../../../ansible/roles/base-system/tasks/main.yml):
   - Add volume directory creation
   - Add host volume definition to Nomad client config
6. **Update Taskfile** [`Taskfile.yml`](../../../Taskfile.yml):
   - Add deploy task if needed
7. **Deploy**: `nomad job validate` → `nomad job run`

---

## Outliers & Special Cases

### Infrastructure Services Without Authelia
Services like Prometheus/Grafana omit the Authelia middleware for internal access:
```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.SERVICE.rule=Host(`SERVICE.home`)",
  # No Authelia middleware
]
```

### System Jobs (Not in `jobs/services/`)
Services in [`jobs/system/`](../../system/) use `type = "system"` and run on all/most clients:
- Traefik (reverse proxy on all clients)
- Grafana Alloy (metrics collection on all clients)

### Dynamic Port Services
Code Server uses dynamic ports (no static assignment):
```hcl
network {
  mode = "bridge"
  port "http" {}  # Nomad assigns dynamically
}
```

---

## Pattern Migration Status

✅ **Completed:** All 22 services migrated to organized structure (2026-02-11)  
📋 **TODO:** Create Nomad Pack templates for each pattern  
📋 **TODO:** Add Terraform module for automated volume provisioning  

---

## References

- [Nomad Job Specification](https://developer.hashicorp.com/nomad/docs/job-specification)
- [Vault Integration](../../../docs/VAULT.md)
- [Service Discovery](../../../docs/NEW_SERVICES_DEPLOYMENT.md)
- [Resource Survey](../../../docs/RESOURCE_SURVEY.md)
