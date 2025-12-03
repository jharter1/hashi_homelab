# Nomad Client Module Variables

variable "client_count" {
  description = "Number of Nomad clients to deploy"
  type        = number
  default     = 2

  validation {
    condition     = var.client_count >= 1 && var.client_count <= 50
    error_message = "Client count must be between 1 and 50."
  }
}

variable "name_prefix" {
  description = "Prefix for client names"
  type        = string
  default     = "nomad-client"
}

variable "proxmox_node" {
  description = "ProxMox node to deploy on (deprecated, use proxmox_nodes)"
  type        = string
  default     = ""
}

variable "proxmox_nodes" {
  description = "List of ProxMox nodes to distribute VMs across"
  type        = list(string)
  default     = []
}

variable "template_name" {
  description = "Name or ID of the Nomad client template"
  type        = string
}

variable "template_ids" {
  description = "List of template IDs per ProxMox node (optional)"
  type        = list(string)
  default     = []
}

variable "cores" {
  description = "CPU cores per client"
  type        = number
  default     = 4
}

variable "memory" {
  description = "Memory in MB per client"
  type        = number
  default     = 4096
}

variable "disk_size" {
  description = "Disk size per client"
  type        = string
  default     = "30G"
}

variable "storage_pool" {
  description = "Storage pool name"
  type        = string
}

variable "network_bridge" {
  description = "Network bridge"
  type        = string
  default     = "vmbr0"
}

variable "vlan_tag" {
  description = "VLAN tag"
  type        = number
  default     = 0
}

variable "network_cidr" {
  description = "Network CIDR block"
  type        = string

  validation {
    condition     = can(cidrhost(var.network_cidr, 0))
    error_message = "Must be a valid CIDR block."
  }
}

variable "ip_start_offset" {
  description = "Starting IP offset within CIDR block"
  type        = number
  default     = 111

  validation {
    condition     = var.ip_start_offset >= 1 && var.ip_start_offset <= 250
    error_message = "IP offset must be between 1 and 250."
  }
}

variable "gateway" {
  description = "Network gateway"
  type        = string
}

variable "dns_servers" {
  description = "DNS servers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

variable "ssh_keys" {
  description = "SSH public keys"
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key for provisioning"
  type        = string
  sensitive   = true
  default     = ""
}

variable "proxmox_ssh_user" {
  description = "SSH user for ProxMox host"
  type        = string
  default     = "root"
}

variable "proxmox_host_ip" {
  description = "ProxMox host IP"
  type        = string
}

variable "server_addresses" {
  description = "List of Nomad server IP addresses"
  type        = list(string)
}

variable "datacenter" {
  description = "Nomad/Consul datacenter name"
  type        = string
  default     = "dc1"
}

variable "region" {
  description = "Nomad region name"
  type        = string
  default     = "global"
}

variable "node_class" {
  description = "Nomad node class"
  type        = string
  default     = "compute"
}

variable "consul_version" {
  description = "Consul version"
  type        = string
  default     = "1.18.0"
}

variable "nomad_version" {
  description = "Nomad version"
  type        = string
  default     = "1.7.5"
}

variable "docker_version" {
  description = "Docker version"
  type        = string
  default     = "24.0.7"
}

variable "environment" {
  description = "Environment (dev, staging, prod)"
  type        = string
  default     = "dev"
}

variable "additional_tags" {
  description = "Additional VM tags"
  type        = list(string)
  default     = []
}

variable "auto_start_services" {
  description = "Automatically start services after deployment"
  type        = bool
  default     = false
}
