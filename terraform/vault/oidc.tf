# OIDC Identity Provider Configuration
# This configures Vault as an OIDC provider for SSO across services

# Enable the identity secrets engine (if not already enabled)
resource "vault_identity_group" "homelab_users" {
  name     = "homelab-users"
  type     = "internal"
  policies = ["default", "nomad-workloads"]
  
  metadata = {
    description = "Homelab users with access to services"
  }
}

# Create an OIDC key for signing tokens
resource "vault_identity_oidc_key" "homelab" {
  name               = "homelab"
  algorithm          = "RS256"
  rotation_period    = 86400  # 24 hours
  verification_ttl   = 86400
  allowed_client_ids = ["*"]
}

# Create OIDC role for Grafana
resource "vault_identity_oidc_role" "grafana" {
  name = "grafana"
  key  = vault_identity_oidc_key.homelab.name
  
  client_id = "grafana"
  ttl       = 86400  # 24 hours
  
  template = <<EOF
{
  "email": {{identity.entity.metadata.email}},
  "username": {{identity.entity.name}},
  "groups": {{identity.entity.groups.names}}
}
EOF
}

# Create OIDC role for Nomad
resource "vault_identity_oidc_role" "nomad" {
  name = "nomad"
  key  = vault_identity_oidc_key.homelab.name
  
  client_id = "nomad-ui"
  ttl       = 86400
  
  template = <<EOF
{
  "email": {{identity.entity.metadata.email}},
  "username": {{identity.entity.name}},
  "groups": {{identity.entity.groups.names}}
}
EOF
}

# Create OIDC role for other services
resource "vault_identity_oidc_role" "services" {
  name = "services"
  key  = vault_identity_oidc_key.homelab.name
  
  client_id = "homelab-services"
  ttl       = 86400
  
  template = <<EOF
{
  "email": {{identity.entity.metadata.email}},
  "username": {{identity.entity.name}},
  "groups": {{identity.entity.groups.names}}
}
EOF
}

# Create userpass auth backend for local authentication
resource "vault_auth_backend" "userpass" {
  type = "userpass"
  path = "userpass"
  
  tune {
    default_lease_ttl = "1h"
    max_lease_ttl     = "24h"
  }
}

# Output OIDC discovery URL
output "oidc_discovery_url" {
  value       = "${var.vault_address}/v1/identity/oidc/provider/homelab/.well-known/openid-configuration"
  description = "OIDC discovery URL for service configuration"
}

output "oidc_issuer" {
  value       = "${var.vault_address}/v1/identity/oidc/provider/homelab"
  description = "OIDC issuer URL"
}
