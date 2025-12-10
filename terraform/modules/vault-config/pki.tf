# ============================================================================
# PKI Secrets Engine - Root CA
# ============================================================================

resource "vault_mount" "pki" {
  path                      = "pki"
  type                      = "pki"
  description               = "Root PKI for homelab"
  default_lease_ttl_seconds = 315360000 # ~10 years
  max_lease_ttl_seconds     = 315360000
}

resource "vault_pki_secret_backend_config_urls" "pki_config" {
  backend = vault_mount.pki.path
  issuing_certificates = [
    "${var.vault_address}/v1/pki/ca"
  ]
  crl_distribution_points = [
    "${var.vault_address}/v1/pki/crl"
  ]
}

resource "vault_pki_secret_backend_root_cert" "root" {
  backend     = vault_mount.pki.path
  type        = "internal"
  common_name = "Homelab Root CA"
  ttl         = var.pki_root_ttl
  issuer_name = "root-ca"

  exclude_cn_from_sans = true
  key_type             = "rsa"
  key_bits             = 4096
}

# ============================================================================
# PKI Secrets Engine - Intermediate CA
# ============================================================================

resource "vault_mount" "pki_int" {
  path                      = "pki_int"
  type                      = "pki"
  description               = "Intermediate PKI for issuing certificates"
  default_lease_ttl_seconds = 157680000 # ~5 years
  max_lease_ttl_seconds     = 157680000
}

resource "vault_pki_secret_backend_intermediate_cert_request" "intermediate" {
  backend     = vault_mount.pki_int.path
  type        = "internal"
  common_name = "Homelab Intermediate CA"
  key_type    = "rsa"
  key_bits    = 4096
}

resource "vault_pki_secret_backend_root_sign_intermediate" "intermediate" {
  backend              = vault_mount.pki.path
  csr                  = vault_pki_secret_backend_intermediate_cert_request.intermediate.csr
  common_name          = "Homelab Intermediate CA"
  ttl                  = var.pki_intermediate_ttl
  issuer_ref           = vault_pki_secret_backend_root_cert.root.issuer_id
  exclude_cn_from_sans = true
}

resource "vault_pki_secret_backend_intermediate_set_signed" "intermediate" {
  backend     = vault_mount.pki_int.path
  certificate = vault_pki_secret_backend_root_sign_intermediate.intermediate.certificate
}

resource "vault_pki_secret_backend_config_urls" "pki_int_config" {
  backend = vault_mount.pki_int.path
  issuing_certificates = [
    "${var.vault_address}/v1/pki_int/ca"
  ]
  crl_distribution_points = [
    "${var.vault_address}/v1/pki_int/crl"
  ]
}

# ============================================================================
# PKI Roles
# ============================================================================

# Server role - for Consul, Nomad servers, and services
resource "vault_pki_secret_backend_role" "server" {
  backend          = vault_mount.pki_int.path
  name             = "server"
  ttl              = 2592000  # 30 days
  max_ttl          = 31536000 # 1 year
  allow_ip_sans    = true
  key_type         = "rsa"
  key_bits         = 2048
  allowed_domains  = var.allowed_domains
  allow_subdomains = true
  allow_glob_domains = true
  allow_bare_domains = true
  allow_localhost    = true
  server_flag        = true
  client_flag        = true
  key_usage = [
    "DigitalSignature",
    "KeyAgreement",
    "KeyEncipherment"
  ]
}

# Client role - for client authentication
resource "vault_pki_secret_backend_role" "client" {
  backend          = vault_mount.pki_int.path
  name             = "client"
  ttl              = 604800   # 7 days
  max_ttl          = 2592000  # 30 days
  allow_ip_sans    = true
  key_type         = "rsa"
  key_bits         = 2048
  allowed_domains  = var.allowed_domains
  allow_subdomains = true
  allow_glob_domains = true
  allow_bare_domains = true
  allow_localhost    = true
  server_flag        = false
  client_flag        = true
  key_usage = [
    "DigitalSignature",
    "KeyAgreement"
  ]
}

# Service role - for Nomad workload certificates (shorter TTL)
resource "vault_pki_secret_backend_role" "service" {
  backend          = vault_mount.pki_int.path
  name             = "service"
  ttl              = 604800  # 7 days
  max_ttl          = 2592000 # 30 days
  allow_ip_sans    = true
  key_type         = "rsa"
  key_bits         = 2048
  allowed_domains  = var.allowed_domains
  allow_subdomains = true
  allow_glob_domains = true
  allow_bare_domains = true
  allow_localhost    = true
  server_flag        = true
  client_flag        = true
  key_usage = [
    "DigitalSignature",
    "KeyAgreement",
    "KeyEncipherment"
  ]
}
