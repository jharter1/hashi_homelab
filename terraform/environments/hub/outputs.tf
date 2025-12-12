output "vault_servers" {
  description = "Vault server information"
  value = {
    for idx in range(var.vault_cluster_size) : idx => {
      name       = module.vault_servers[idx].vm_name
      id         = module.vault_servers[idx].vm_id
      ip_address = "10.0.0.${var.vault_vm_config.ip_start + idx}"
    }
  }
}

output "vault_api_address" {
  description = "Primary Vault API address"
  value       = "http://10.0.0.${var.vault_vm_config.ip_start}:8200"
}

output "vault_cluster_addresses" {
  description = "All Vault cluster node addresses"
  value = [
    for idx in range(var.vault_cluster_size) : "http://10.0.0.${var.vault_vm_config.ip_start + idx}:8200"
  ]
}