# Nomad HCL Snippets

Reusable HCL patterns to reduce duplication across Nomad job files.

## Available Snippets

### Network Patterns

#### network-static-port.hcl
For services that need a specific port (e.g., Traefik on 80/443):
```hcl
network {
  mode = "host"
  port "http" {
    static = 8080
  }
}
```

#### network-dynamic-port.hcl
For services that can use dynamic port allocation:
```hcl
network {
  port "http" {
    to = 80
  }
}
```

### Resource Patterns

#### resources-lightweight.hcl (512MB)
For simple services without heavy memory requirements:
```hcl
resources {
  cpu = 500
  memory = 512
}
```

#### resources-standard.hcl (1GB)
For typical application services:
```hcl
resources {
  cpu = 1000
  memory = 1024
}
```

#### resources-heavy.hcl (2GB)
For resource-intensive services (Grafana, databases, Immich):
```hcl
resources {
  cpu = 2000
  memory = 2048
}
```

### Vault Integration

#### vault-policy-standard.hcl
Standard Vault policy for Nomad workloads:
```hcl
vault {
  policies = ["nomad-workloads"]
  change_mode = "restart"
}
```

#### vault-postgres-template.hcl
Template for PostgreSQL database connection secrets:
```hcl
template {
  destination = "secrets/db.env"
  env = true
  data = <<EOH
DB_PASSWORD={{ with secret "secret/data/postgres/SERVICE" }}{{ .Data.data.password }}{{ end }}
DB_HOST={{ range service "postgresql" }}{{ .Address }}{{ end }}
DB_PORT=5432
DB_NAME=SERVICE
DB_USER=SERVICE
  EOH
}
```

### Volume Patterns

#### volume-mount-data.hcl
Standard pattern for persistent data volumes:
```hcl
volume "SERVICE_data" {
  type = "host"
  read_only = false
  source = "SERVICE_data"
}

volume_mount {
  volume = "SERVICE_data"
  destination = "/data"
}
```

#### volume-mount-config.hcl
Pattern for configuration file volumes:
```hcl
volume "SERVICE_config" {
  type = "host"
  read_only = true
  source = "SERVICE_config"
}

volume_mount {
  volume = "SERVICE_config"
  destination = "/config"
  read_only = true
}
```

### Traefik Integration

#### traefik-tags-authelia.hcl
Traefik tags for services behind Authelia SSO:
```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.SERVICE.rule=Host(`SERVICE.lab.hartr.net`)",
  "traefik.http.routers.SERVICE.entrypoints=websecure",
  "traefik.http.routers.SERVICE.tls=true",
  "traefik.http.routers.SERVICE.tls.certresolver=letsencrypt",
  "traefik.http.routers.SERVICE.middlewares=authelia@file"
]
```

#### traefik-tags-public.hcl
Traefik tags for publicly accessible services (monitoring):
```hcl
tags = [
  "traefik.enable=true",
  "traefik.http.routers.SERVICE.rule=Host(`SERVICE.home`)",
  "traefik.http.routers.SERVICE.entrypoints=websecure",
  "traefik.http.routers.SERVICE.tls=true",
  "traefik.http.routers.SERVICE.tls.certresolver=letsencrypt"
]
```

## Usage

These snippets are documentation/reference only. Copy and adapt them into your Nomad job files.

Future enhancement: Consider Nomad Pack templates for true reusability.

## Service Categorization

Add metadata to categorize services:
```hcl
meta {
  category = "observability"  # observability, database, auth, media, development, infrastructure
  pattern = "postgres-backed"  # simple-volume, postgres-backed, multi-container
  priority = "high"  # high, medium, low
  depends_on = "postgresql,redis"  # CSV list of dependencies
}
```
