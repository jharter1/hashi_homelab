# Development Environment Outputs

output "nomad_server_ips" {
  description = "Nomad server IP addresses"
  value       = module.nomad_servers.server_ips
}

output "nomad_client_ips" {
  description = "Nomad client IP addresses"
  value       = module.nomad_clients.client_ips
}

output "nomad_ui_url" {
  description = "Nomad UI URL"
  value       = module.nomad_servers.nomad_address
}

output "consul_ui_url" {
  description = "Consul UI URL"
  value       = module.nomad_servers.consul_address
}

output "server_ssh_commands" {
  description = "SSH commands for servers"
  value       = module.nomad_servers.ssh_commands
}

output "client_ssh_commands" {
  description = "SSH commands for clients"
  value       = module.nomad_clients.ssh_commands
}

output "cluster_info" {
  description = "Cluster information"
  value = {
    environment    = var.environment
    datacenter     = var.datacenter
    region         = var.region
    server_count   = var.nomad_server_count
    client_count   = var.nomad_client_count
    consul_version = var.consul_version
    nomad_version  = var.nomad_version
    vault_version  = var.vault_version
  }
}
