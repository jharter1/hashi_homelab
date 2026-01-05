# ============================================================================
# Vault Policies for Nomad Integration
# ============================================================================

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
