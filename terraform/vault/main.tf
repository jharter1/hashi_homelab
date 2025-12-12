terraform {
  required_version = ">= 1.0"
  
  required_providers {
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.5"
    }
  }

  backend "local" {
    path = "terraform-vault.tfstate"
  }
}

provider "vault" {
  address = var.vault_address
  token   = var.vault_token
}

# Enable KV v2 secrets engine
resource "vault_mount" "kv" {
  path        = "secret"
  type        = "kv"
  options     = { version = "2" }
  description = "KV v2 secrets engine for application secrets"
}

# Enable PKI secrets engine for root CA
resource "vault_mount" "pki" {
  path                      = "pki"
  type                      = "pki"
  description               = "Root PKI for homelab"
  default_lease_ttl_seconds = 315360000  # 10 years
  max_lease_ttl_seconds     = 315360000  # 10 years
}

# Enable PKI secrets engine for intermediate CA
resource "vault_mount" "pki_int" {
  path                      = "pki_int"
  type                      = "pki"
  description               = "Intermediate PKI for issuing certificates"
  default_lease_ttl_seconds = 157680000  # 5 years
  max_lease_ttl_seconds     = 157680000  # 5 years
}

# Configure PKI URLs for root
resource "vault_pki_secret_backend_config_urls" "pki" {
  backend                 = vault_mount.pki.path
  issuing_certificates    = ["${var.vault_address}/v1/pki/ca"]
  crl_distribution_points = ["${var.vault_address}/v1/pki/crl"]
}

# Configure PKI URLs for intermediate
resource "vault_pki_secret_backend_config_urls" "pki_int" {
  backend                 = vault_mount.pki_int.path
  issuing_certificates    = ["${var.vault_address}/v1/pki_int/ca"]
  crl_distribution_points = ["${var.vault_address}/v1/pki_int/crl"]
}

# Create role for issuing certificates from intermediate CA
resource "vault_pki_secret_backend_role" "homelab" {
  backend          = vault_mount.pki_int.path
  name             = "homelab-dot-local"
  ttl              = 2592000  # 30 days
  max_ttl          = 2592000  # 30 days
  allow_ip_sans    = true
  allowed_domains  = ["homelab.local"]
  allow_subdomains = true
  generate_lease   = true
}

# Enable JWT auth backend for Nomad
resource "vault_jwt_auth_backend" "nomad" {
  path               = "jwt-nomad"
  type               = "jwt"
  oidc_discovery_url = var.nomad_address
  default_role       = "nomad-workloads"
  
  tune {
    default_lease_ttl = "1h"
    max_lease_ttl     = "24h"
  }
}

# Create policy for Nomad workloads
resource "vault_policy" "nomad_workloads" {
  name = "nomad-workloads"

  policy = <<EOT
# Allow reading secrets for Nomad workloads
path "secret/data/nomad/*" {
  capabilities = ["read", "list"]
}

path "secret/metadata/nomad/*" {
  capabilities = ["read", "list"]
}

# Allow reading from intermediate PKI for certificate issuance
path "pki_int/issue/homelab-dot-local" {
  capabilities = ["create", "update"]
}

# Allow reading PKI CA chain
path "pki_int/ca_chain" {
  capabilities = ["read"]
}

path "pki_int/cert/ca" {
  capabilities = ["read"]
}
EOT
}

# Create JWT role for Nomad workloads
resource "vault_jwt_auth_backend_role" "nomad_workloads" {
  backend   = vault_jwt_auth_backend.nomad.path
  role_name = "nomad-workloads"
  role_type = "jwt"

  bound_audiences = ["vault.io"]
  
  user_claim              = "/nomad_job_id"
  user_claim_json_pointer = true
  
  claim_mappings = {
    "/nomad_namespace" = "nomad_namespace"
    "/nomad_job_id"    = "nomad_job_id"
    "/nomad_task"      = "nomad_task"
  }

  token_type            = "service"
  token_policies        = [vault_policy.nomad_workloads.name]
  token_period          = 1800  # 30 minutes
  token_explicit_max_ttl = 3600  # 1 hour
}

# Output configuration for verification
output "vault_config" {
  value = {
    kv_path           = vault_mount.kv.path
    pki_root_path     = vault_mount.pki.path
    pki_int_path      = vault_mount.pki_int.path
    pki_role          = vault_pki_secret_backend_role.homelab.name
    jwt_auth_path     = vault_jwt_auth_backend.nomad.path
    nomad_policy      = vault_policy.nomad_workloads.name
  }
}
