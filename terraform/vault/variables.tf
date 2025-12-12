variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "http://10.0.0.30:8200"
}

variable "vault_token" {
  description = "Vault root token for initial configuration"
  type        = string
  sensitive   = true
}

variable "nomad_address" {
  description = "Nomad server address for JWT OIDC discovery"
  type        = string
  default     = "http://10.0.0.50:4646"
}
