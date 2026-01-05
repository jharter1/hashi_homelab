# Vault Configuration for Dev Environment
# This configures Vault PKI, policies, and secrets after Vault is installed

# Temporarily disabled - Vault master was on pve1 and needs to be redeployed
# After VMs are stable, redeploy Vault as a Nomad job, then uncomment this

# # Vault provider - token should come from .vault-credentials file
# provider "vault" {
#   address = var.vault_address
#   token   = var.vault_token
# }
# 
# module "vault_config" {
#   source = "../../modules/vault-config"
# 
#   vault_address = var.vault_address
#   vault_token   = var.vault_token
# 
#   allowed_domains = [
#     "service.consul",
#     "dc1.consul",
#     "*.consul",
#     "nomad.service.consul",
#     "*.service.consul",
#     "homelab.local",
#     "*.homelab.local",
#     "localhost"
#   ]
# }
# 
# # Output the Nomad server token
# output "nomad_server_token" {
#   description = "Add this token to Nomad server configuration"
#   value       = module.vault_config.nomad_server_token
#   sensitive   = true
# }
# 
# output "root_ca_cert" {
#   description = "Root CA certificate - add to your trust store"
#   value       = module.vault_config.root_ca_certificate
# }

output "setup_complete" {
  value = <<-EOT
  
  ✅ Vault has been configured!
  
  Next steps:
  1. Get the Nomad server token:
     terraform output -raw nomad_server_token
  
  2. Save root CA certificate:
     terraform output -raw root_ca_cert > homelab-root-ca.crt
  
  3. Update Nomad server config with the token
  4. Restart Nomad servers
  
  Test certificate issuance:
  vault write pki_int/issue/service common_name=test.service.consul ttl=24h
  
  EOT
}
