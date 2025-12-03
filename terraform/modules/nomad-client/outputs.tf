# Nomad Client Module Outputs

output "client_ids" {
  description = "List of client VM IDs"
  value       = [for client in module.nomad_clients : client.vm_id]
}

output "client_names" {
  description = "List of client names"
  value       = local.client_names
}

output "client_ips" {
  description = "List of client IP addresses (configured static IPs)"
  value       = [for ip in local.client_ips : split("/", ip)[0]]
}

output "ssh_commands" {
  description = "SSH commands for each client"
  value       = [for ip in local.client_ips : "ssh ubuntu@${split("/", ip)[0]}"]
}
