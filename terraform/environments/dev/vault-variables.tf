# Vault Configuration Variables

variable "vault_address" {
  description = "Vault server address"
  type        = string
  default     = "http://10.0.0.50:8200" # nomad-server-1
}

variable "vault_token" {
  description = "Vault root token (from .vault-credentials file)"
  type        = string
  sensitive   = true
  default     = "" # Pass via TF_VAR_vault_token environment variable
}
