# ============================================================================
# KV v2 Secrets Engine
# ============================================================================

resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secrets engine for application secrets"
}

# ============================================================================
# Random Passwords and Keys
# ============================================================================

resource "random_password" "docker_registry" {
  length  = 32
  special = true
}

resource "random_password" "grafana_admin" {
  length  = 32
  special = true
}

resource "random_password" "grafana_secret_key" {
  length  = 64
  special = true
}

resource "random_password" "prometheus_admin" {
  length  = 32
  special = true
}

# Consul gossip encryption key (32 bytes base64-encoded)
resource "random_bytes" "consul_gossip" {
  length = 32
}

resource "random_password" "minio_root" {
  length  = 32
  special = false  # MinIO prefers alphanumeric
}

# ============================================================================
# Application Secrets
# ============================================================================

resource "vault_kv_secret_v2" "docker_registry" {
  mount = vault_mount.kv.path
  name  = "nomad/docker-registry"

  data_json = jsonencode({
    username = "admin"
    password = random_password.docker_registry.result
  })
}

resource "vault_kv_secret_v2" "grafana" {
  mount = vault_mount.kv.path
  name  = "nomad/grafana"

  data_json = jsonencode({
    admin_password = random_password.grafana_admin.result
    secret_key     = random_password.grafana_secret_key.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

resource "vault_kv_secret_v2" "prometheus" {
  mount = vault_mount.kv.path
  name  = "nomad/prometheus"

  data_json = jsonencode({
    admin_password = random_password.prometheus_admin.result
  })
}

resource "vault_kv_secret_v2" "minio" {
  mount = vault_mount.kv.path
  name  = "nomad/minio"

  data_json = jsonencode({
    root_user     = "admin"
    root_password = random_password.minio_root.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

# Consul gossip encryption key
resource "vault_kv_secret_v2" "consul_encryption" {
  mount = vault_mount.kv.path
  name  = "consul/encryption"

  data_json = jsonencode({
    gossip_key = random_bytes.consul_gossip.base64
  })
}

# ============================================================================
# PostgreSQL Database Passwords
# ============================================================================

resource "random_password" "postgres_admin" {
  length  = 32
  special = true
}

resource "random_password" "postgres_authelia" {
  length  = 32
  special = true
}

resource "random_password" "postgres_freshrss" {
  length  = 32
  special = true
}

resource "random_password" "postgres_gitea" {
  length  = 32
  special = true
}

resource "random_password" "postgres_grafana" {
  length  = 32
  special = true
}

resource "random_password" "postgres_speedtest" {
  length  = 32
  special = true
}

resource "random_password" "postgres_uptimekuma" {
  length  = 32
  special = true
}

resource "random_password" "postgres_vaultwarden" {
  length  = 32
  special = true
}

# PostgreSQL admin password
resource "vault_kv_secret_v2" "postgres_admin" {
  mount = vault_mount.kv.path
  name  = "postgres/admin"

  data_json = jsonencode({
    password = random_password.postgres_admin.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

# Authelia database
resource "vault_kv_secret_v2" "postgres_authelia" {
  mount = vault_mount.kv.path
  name  = "postgres/authelia"

  data_json = jsonencode({
    password = random_password.postgres_authelia.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

# FreshRSS database
resource "vault_kv_secret_v2" "postgres_freshrss" {
  mount = vault_mount.kv.path
  name  = "postgres/freshrss"

  data_json = jsonencode({
    password = random_password.postgres_freshrss.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

# Gitea database
resource "vault_kv_secret_v2" "postgres_gitea" {
  mount = vault_mount.kv.path
  name  = "postgres/gitea"

  data_json = jsonencode({
    password = random_password.postgres_gitea.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

# Grafana database
resource "vault_kv_secret_v2" "postgres_grafana" {
  mount = vault_mount.kv.path
  name  = "postgres/grafana"

  data_json = jsonencode({
    password = random_password.postgres_grafana.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

# Speedtest database
resource "vault_kv_secret_v2" "postgres_speedtest" {
  mount = vault_mount.kv.path
  name  = "postgres/speedtest"

  data_json = jsonencode({
    password = random_password.postgres_speedtest.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

# Uptime Kuma database
resource "vault_kv_secret_v2" "postgres_uptimekuma" {
  mount = vault_mount.kv.path
  name  = "postgres/uptimekuma"

  data_json = jsonencode({
    password = random_password.postgres_uptimekuma.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

# Vaultwarden database
resource "vault_kv_secret_v2" "postgres_vaultwarden" {
  mount = vault_mount.kv.path
  name  = "postgres/vaultwarden"

  data_json = jsonencode({
    password = random_password.postgres_vaultwarden.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

# ============================================================================
# MariaDB Database Passwords
# ============================================================================

resource "random_password" "mariadb_admin" {
  length  = 32
  special = true
}

resource "random_password" "mariadb_seafile" {
  length  = 32
  special = true
}

# MariaDB root password
resource "vault_kv_secret_v2" "mariadb_admin" {
  mount = vault_mount.kv.path
  name  = "mariadb/admin"

  data_json = jsonencode({
    password = random_password.mariadb_admin.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}

# Seafile database password
resource "vault_kv_secret_v2" "mariadb_seafile" {
  mount = vault_mount.kv.path
  name  = "mariadb/seafile"

  data_json = jsonencode({
    password = random_password.mariadb_seafile.result
  })

  lifecycle {
    ignore_changes = [data_json]
  }
}
