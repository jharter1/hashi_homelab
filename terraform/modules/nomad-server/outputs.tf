# Nomad Server Module Outputs

output "server_ids" {
  description = "List of server VM IDs"
  value       = [for server in module.nomad_servers : server.vm_id]
}

output "server_names" {
  description = "List of server names"
  value       = local.server_names
}

output "server_ips" {
  description = "List of server IP addresses (configured static IPs)"
  value       = [for ip in local.server_ips : split("/", ip)[0]]
}

output "consul_retry_join" {
  description = "Consul retry_join addresses"
  value       = local.consul_retry_join
}

output "nomad_address" {
  description = "Nomad API address (first server)"
  value       = "http://${split("/", local.server_ips[0])[0]}:4646"
}

output "consul_address" {
  description = "Consul API address (first server)"
  value       = "http://${split("/", local.server_ips[0])[0]}:8500"
}

output "ssh_commands" {
  description = "SSH commands for each server"
  value       = [for ip in local.server_ips : "ssh ubuntu@${split("/", ip)[0]}"]
}
