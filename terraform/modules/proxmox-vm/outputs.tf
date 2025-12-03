# ProxMox VM Module Outputs

output "vm_id" {
  description = "The ID of the created VM"
  value       = proxmox_virtual_environment_vm.vm.id
}

output "vm_name" {
  description = "The name of the created VM"
  value       = proxmox_virtual_environment_vm.vm.name
}

output "node_name" {
  description = "The ProxMox node where the VM is deployed"
  value       = proxmox_virtual_environment_vm.vm.node_name
}

output "ipv4_address" {
  description = "The configured IPv4 address"
  value       = var.ip_address
}

output "ipv4_gateway" {
  description = "The configured IPv4 gateway"
  value       = var.gateway
}

output "mac_address" {
  description = "The MAC address of the primary network interface"
  value       = try(proxmox_virtual_environment_vm.vm.network_device[0].mac_address, "")
}
