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
