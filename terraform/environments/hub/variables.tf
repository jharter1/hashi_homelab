variable "proxmox_host" {
  description = "Proxmox host endpoint"
  type        = string
  default     = "https://10.0.0.21:8006"
}

variable "proxmox_username" {
  description = "Proxmox username"
  type        = string
  sensitive   = true
}

variable "proxmox_password" {
  description = "Proxmox password"
  type        = string
  sensitive   = true
}

variable "ssh_public_key" {
  description = "SSH public key for VM access"
  type        = string
}

variable "datacenter" {
  description = "Datacenter identifier"
  type        = string
  default     = "dc1"
}

variable "region" {
  description = "Region identifier"
  type        = string
  default     = "global"
}

variable "vault_cluster_size" {
  description = "Number of Vault servers (1 for dev, 3 for HA)"
  type        = number
  default     = 3
}

variable "proxmox_nodes" {
  description = "List of ProxMox nodes to distribute VMs across (round-robin)"
  type        = list(string)
  default     = ["pve1", "pve2", "pve3"]
}

variable "vault_template_ids" {
  description = "Template IDs per node for Vault servers"
  type        = list(string)
  default     = ["9500", "9502", "9504"]
}

variable "vault_vm_config" {
  description = "Vault VM configuration"
  type = object({
    cores        = number
    memory       = number
    disk_size    = number
    vm_id_start  = number
    ip_start     = number
    storage_pool = string
  })
  default = {
    cores        = 2
    memory       = 2048
    disk_size    = 10
    vm_id_start  = 200
    ip_start     = 30
    storage_pool = "local-lvm"
  }
}