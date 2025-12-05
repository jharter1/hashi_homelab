# ProxMox VM Module Variables

variable "vm_name" {
  description = "Name of the VM"
  type        = string

  validation {
    condition     = length(var.vm_name) > 0 && length(var.vm_name) <= 63
    error_message = "VM name must be between 1 and 63 characters."
  }
}

variable "proxmox_node" {
  description = "ProxMox node to deploy on"
  type        = string
}

variable "template_name" {
  description = "Name of the template to clone from"
  type        = string
}

variable "cores" {
  description = "Number of CPU cores"
  type        = number
  default     = 2

  validation {
    condition     = var.cores >= 1 && var.cores <= 32
    error_message = "Cores must be between 1 and 32."
  }
}

variable "sockets" {
  description = "Number of CPU sockets"
  type        = number
  default     = 1

  validation {
    condition     = var.sockets >= 1 && var.sockets <= 4
    error_message = "Sockets must be between 1 and 4."
  }
}

variable "memory" {
  description = "Memory in MB"
  type        = number
  default     = 2048

  validation {
    condition     = var.memory >= 512 && var.memory <= 65536
    error_message = "Memory must be between 512MB and 64GB."
  }
}

variable "disk_size" {
  description = "Disk size (e.g., 20G)"
  type        = string
  default     = "20G"

  validation {
    condition     = can(regex("^[0-9]+[GM]$", var.disk_size))
    error_message = "Disk size must be in format like '20G' or '2048M'."
  }
}

variable "storage_pool" {
  description = "Storage pool name"
  type        = string
  default     = "local-lvm"
}

variable "vm_storage_pool" {
  description = "VM Storage pool name"
  type        = string
}


variable "network_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "vlan_tag" {
  description = "VLAN tag (0 for no VLAN)"
  type        = number
  default     = 0

  validation {
    condition     = var.vlan_tag == 0 || (var.vlan_tag >= 1 && var.vlan_tag <= 4094)
    error_message = "VLAN tag must be 0 or between 1 and 4094."
  }
}

variable "ip_address" {
  description = "IP address with CIDR (e.g., 10.0.0.101/24)"
  type        = string

  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}/[0-9]{1,2}$", var.ip_address))
    error_message = "IP address must be in CIDR format (e.g., 10.0.0.101/24)."
  }
}

variable "gateway" {
  description = "Network gateway IP"
  type        = string

  validation {
    condition     = can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.gateway))
    error_message = "Gateway must be a valid IPv4 address."
  }
}

variable "dns_servers" {
  description = "List of DNS servers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "ssh_keys" {
  description = "SSH public key(s) for ubuntu user"
  type        = string
  default     = ""
}

variable "ssh_private_key" {
  description = "SSH private key for connecting to VM"
  type        = string
  default     = ""
  sensitive   = true
}

variable "cloud_init_user_data" {
  description = "Cloud-init user data content (deprecated, use consul_config and nomad_config)"
  type        = string
  default     = ""
}

variable "consul_config" {
  description = "Consul configuration file content"
  type        = string
  default     = ""
}

variable "nomad_config" {
  description = "Nomad configuration file content"
  type        = string
  default     = ""
}

variable "proxmox_ssh_user" {
  description = "SSH user for ProxMox host (for cloud-init upload)"
  type        = string
  default     = "root"
}

variable "proxmox_host_ip" {
  description = "ProxMox host IP address (for cloud-init upload)"
  type        = string
  default     = ""
}

variable "onboot" {
  description = "Start VM on boot"
  type        = bool
  default     = true
}

variable "environment" {
  description = "Environment tag (dev, staging, prod)"
  type        = string
  default     = "dev"

  validation {
    condition     = contains(["dev", "staging", "prod"], var.environment)
    error_message = "Environment must be dev, staging, or prod."
  }
}

variable "role" {
  description = "VM role tag (nomad-server, nomad-client, etc.)"
  type        = string
}

variable "additional_tags" {
  description = "Additional tags for the VM"
  type        = list(string)
  default     = []
}
