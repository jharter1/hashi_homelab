variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "http://127.0.0.1:8200"
}

variable "vault_token" {
  description = "Vault root token for initial configuration"
  type        = string
  sensitive   = true
}

variable "pki_root_ttl" {
  description = "TTL for root CA certificate"
  type        = string
  default     = "87600h" # 10 years
}

variable "pki_intermediate_ttl" {
  description = "TTL for intermediate CA certificate"
  type        = string
  default     = "43800h" # 5 years
}

variable "allowed_domains" {
  description = "List of allowed domains for certificate issuance"
  type        = list(string)
  default = [
    "service.consul",
    "dc1.consul",
    "*.consul",
    "nomad.service.consul",
    "*.service.consul",
    "homelab.local",
    "*.homelab.local",
    "home",
    "*.home",
    "localhost"
  ]
}

variable "nomad_token_policies" {
  description = "Policies that Nomad workloads can use"
  type        = list(string)
  default     = ["nomad-workloads", "access-secrets"]
}

variable "nomad_oidc_discovery_url" {
  description = "OIDC discovery URL for Nomad workload identity"
  type        = string
  default     = "https://nomad.service.consul:4646/.well-known/openid-configuration"
}

variable "nomad_jwt_issuer" {
  description = "JWT issuer for Nomad workload identity"
  type        = string
  default     = "https://nomad.service.consul:4646"
}
