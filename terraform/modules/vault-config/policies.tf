# ============================================================================
# Vault Policies for Nomad Integration
# ============================================================================

# Policy for Nomad servers
resource "vault_policy" "nomad_server" {
  name = "nomad-server"

  policy = <<EOF
# Allow creating tokens under "nomad-cluster" token role
path "auth/token/create/nomad-cluster" {
  capabilities = ["create", "update"]
}

# Allow looking up "nomad-cluster" token role
path "auth/token/roles/nomad-cluster" {
  capabilities = ["read"]
}

# Allow looking up the token passed to Nomad to validate
path "auth/token/lookup-self" {
  capabilities = ["read"]
}

# Allow looking up incoming tokens to validate they have permissions
path "auth/token/lookup" {
  capabilities = ["update"]
}

# Allow revoking tokens that should be expired
path "auth/token/revoke-accessor" {
  capabilities = ["update"]
}

# Allow checking the capabilities of our own token
path "sys/capabilities-self" {
  capabilities = ["update"]
}

# Allow our own token to be renewed
path "auth/token/renew-self" {
  capabilities = ["update"]
}
EOF
}

# Token role for Nomad cluster
resource "vault_token_auth_backend_role" "nomad_cluster" {
  role_name              = "nomad-cluster"
  allowed_policies       = var.nomad_token_policies
  orphan                 = true
  token_period           = "259200" # 72 hours
  renewable              = true
  token_explicit_max_ttl = "0"
}

# Policy for Nomad workloads
resource "vault_policy" "nomad_workloads" {
  name = "nomad-workloads"

  policy = <<EOF
# Allow reading from KV v2 secrets
path "secret/data/nomad/*" {
  capabilities = ["read", "list"]
}

# Allow issuing certificates from PKI
path "pki_int/issue/service" {
  capabilities = ["create", "update"]
}

path "pki_int/issue/client" {
  capabilities = ["create", "update"]
}

# Allow reading PKI configuration
path "pki_int/config/ca" {
  capabilities = ["read"]
}

path "pki_int/cert/ca" {
  capabilities = ["read"]
}
EOF
}

# Policy for services that need full secrets access
resource "vault_policy" "access_secrets" {
  name = "access-secrets"

  policy = <<EOF
# Full access to application secrets under nomad/ path
path "secret/data/nomad/*" {
  capabilities = ["create", "read", "update", "delete", "list"]
}

path "secret/metadata/nomad/*" {
  capabilities = ["list", "read", "delete"]
}

# Access to database dynamic secrets (if configured)
path "database/creds/*" {
  capabilities = ["read"]
}

# Allow reading PKI CA certificates for trusting internal TLS
path "pki_int/cert/ca" {
  capabilities = ["read"]
}

path "pki_int/cert/ca_chain" {
  capabilities = ["read"]
}

path "pki_root/cert/ca" {
  capabilities = ["read"]
}
EOF
}

# Policy for consul-template
resource "vault_policy" "consul_template" {
  name = "consul-template"

  policy = <<EOF
# Allow issuing certificates for services
path "pki_int/issue/*" {
  capabilities = ["create", "update"]
}

# Allow reading secrets for template rendering
path "secret/data/consul/*" {
  capabilities = ["read"]
}

path "secret/data/nomad/*" {
  capabilities = ["read"]
}

# Allow renewing own token
path "auth/token/renew-self" {
  capabilities = ["update"]
}

path "auth/token/lookup-self" {
  capabilities = ["read"]
}
EOF
}
