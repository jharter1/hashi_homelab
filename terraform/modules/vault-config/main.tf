# Enable JWT auth backend for Nomad workload identity
resource "vault_jwt_auth_backend" "nomad" {
  description        = "JWT auth backend for Nomad workload identity"
  path               = "jwt-nomad"
  type               = "jwt"
  oidc_discovery_url = var.nomad_oidc_discovery_url
  bound_issuer       = var.nomad_jwt_issuer
  default_role       = "nomad-workloads"
}

# Default role for Nomad workloads
resource "vault_jwt_auth_backend_role" "nomad_workloads" {
  backend        = vault_jwt_auth_backend.nomad.path
  role_name      = "nomad-workloads"
  token_policies = ["nomad-workloads"]

  bound_audiences   = ["vault.io"]
  user_claim        = "nomad_namespace"
  role_type         = "jwt"
  token_ttl         = 3600
  token_max_ttl     = 86400
  
  # Allow claims from Nomad jobs
  claim_mappings = {
    nomad_namespace = "nomad_namespace"
    nomad_job_id    = "nomad_job_id"
    nomad_task      = "nomad_task"
  }
}

# Policy for Nomad workloads to access secrets
resource "vault_policy" "nomad_workloads" {
  name = "nomad-workloads"

  policy = <<EOT
# Allow workloads to read from their namespace-specific paths
path "secret/data/nomad/{{identity.entity.aliases.${vault_jwt_auth_backend.nomad.accessor}.metadata.nomad_namespace}}/*" {
  capabilities = ["read"]
}

# Allow workloads to read common secrets
path "secret/data/common/*" {
  capabilities = ["read"]
}

# Allow workloads to read database credentials
path "secret/data/postgres/*" {
  capabilities = ["read"]
}

path "secret/data/mariadb/*" {
  capabilities = ["read"]
}

# Allow workloads to renew their own tokens
path "auth/token/renew-self" {
  capabilities = ["update"]
}

# Allow workloads to lookup their own token
path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOT
}

# Policy for Nomad servers to manage tokens
resource "vault_policy" "nomad_server" {
  name = "nomad-server"

  policy = <<EOT
# Allow creating tokens for workloads
path "auth/token/create" {
  capabilities = ["create", "update"]
}

# Allow revoking tokens
path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}

# Allow looking up tokens
path "auth/token/lookup-accessor" {
  capabilities = ["update"]
}

# Allow renewing tokens
path "auth/token/renew-accessor" {
  capabilities = ["update"]
}

# Allow reading Vault capabilities
path "sys/capabilities-self" {
  capabilities = ["update"]
}
EOT
}

# Create a token role for Nomad servers
resource "vault_token_auth_backend_role" "nomad_cluster" {
  role_name              = "nomad-cluster"
  allowed_policies       = ["nomad-server"]
  orphan                 = true
  token_period           = "259200" # 72 hours
  renewable              = true
  token_explicit_max_ttl = "0"
}

# Enable KV-v2 secrets engine for application secrets
resource "vault_mount" "secret" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "KV Version 2 secrets engine for application secrets"
}

# Create initial secret structure
resource "vault_kv_secret_v2" "common_example" {
  mount = vault_mount.secret.path
  name  = "common/example"
  
  data_json = jsonencode({
    example_key = "example_value"
    created_by  = "terraform"
  })
}

resource "vault_kv_secret_v2" "nomad_default_example" {
  mount = vault_mount.secret.path
  name  = "nomad/default/example"
  
  data_json = jsonencode({
    message    = "Secret for default namespace"
    created_by = "terraform"
  })
}
