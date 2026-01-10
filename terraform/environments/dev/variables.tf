# Development Environment Variables

# ProxMox Configuration
variable "proxmox_host" {
  description = "ProxMox API URL"
  type        = string
}

variable "proxmox_node" {
  description = "ProxMox node name (deprecated, use proxmox_nodes)"
  type        = string
  default     = "pve1"
}

variable "proxmox_nodes" {
  description = "List of ProxMox nodes for VM distribution"
  type        = list(string)
  default     = ["pve1"]
}

variable "proxmox_username" {
  description = "ProxMox API username"
  type        = string
  default     = "root@pam"
}

variable "proxmox_password" {
  description = "ProxMox API password"
  type        = string
  sensitive   = true
}

variable "proxmox_tls_insecure" {
  description = "Skip TLS verification"
  type        = bool
  default     = true
}

variable "proxmox_ssh_user" {
  description = "SSH user for ProxMox host"
  type        = string
  default     = "root"
}

variable "proxmox_host_ip" {
  description = "ProxMox host IP address"
  type        = string
}

# Template Configuration
variable "nomad_server_template_name" {
  description = "Nomad server template name or ID"
  type        = string
  default     = "ubuntu-nomad-server-template"
}

variable "nomad_server_template_ids" {
  description = "List of template IDs per ProxMox node (optional, uses template_name if not set)"
  type        = list(string)
  default     = []
}

variable "nomad_client_template_name" {
  description = "Nomad client template name or ID"
  type        = string
  default     = "ubuntu-nomad-client-template"
}

variable "nomad_client_template_ids" {
  description = "List of template IDs per ProxMox node (optional, uses template_name if not set)"
  type        = list(string)
  default     = []
}

# Storage Configuration
variable "storage_pool" {
  description = "Storage pool name"
  type        = string
}

variable "vm_storage_pool" {
  description = "VM Storage pool name"
  type        = string
  default    = ""
}

# Network Configuration
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
}

variable "network_gateway" {
  description = "Network gateway"
  type        = string
}

variable "dns_servers" {
  description = "DNS servers"
  type        = list(string)
  default     = ["1.1.1.1", "8.8.8.8"]
}

# Nomad Server Configuration
variable "nomad_server_count" {
  description = "Number of Nomad servers"
  type        = number
  default     = 3
}

variable "nomad_server_cores" {
  description = "CPU cores per server"
  type        = number
  default     = 2
}

variable "nomad_server_memory" {
  description = "Memory per server (MB)"
  type        = number
  default     = 4096
}

variable "nomad_server_disk_size" {
  description = "Disk size per server (must be larger than template)"
  type        = string
  default     = "50G"
}

variable "nomad_server_ip_start" {
  description = "Starting IP offset for servers"
  type        = number
  default     = 101
}

# Nomad Client Configuration
variable "nomad_client_count" {
  description = "Number of Nomad clients"
  type        = number
  default     = 2
}

variable "nomad_client_cores" {
  description = "CPU cores per client"
  type        = number
  default     = 4
}

variable "nomad_client_memory" {
  description = "Memory per client (MB)"
  type        = number
  default     = 8192
}

variable "nomad_client_disk_size" {
  description = "Disk size per client (must be larger than template)"
  type        = string
  default     = "50G"
}

variable "nomad_client_ip_start" {
  description = "Starting IP offset for clients"
  type        = number
  default     = 111
}

variable "nomad_client_node_class" {
  description = "Nomad client node class"
  type        = string
  default     = "compute"
}

# SSH Configuration
variable "ssh_public_keys" {
  description = "SSH public keys (newline separated)"
  type        = string
}

variable "ssh_private_key" {
  description = "SSH private key for provisioning"
  type        = string
  sensitive   = true
  default     = ""
}

# HashiCorp Tool Versions
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

variable "vault_version" {
  description = "Vault version"
  type        = string
  default     = "1.16.0"
}

variable "docker_version" {
  description = "Docker version"
  type        = string
  default     = "24.0.7"
}

# Cluster Configuration
variable "datacenter" {
  description = "Datacenter name"
  type        = string
  default     = "dc1"
}

variable "region" {
  description = "Region name"
  type        = string
  default     = "global"
}

# Environment Configuration
variable "environment" {
  description = "Environment name"
  type        = string
  default     = "dev"
}

variable "auto_bootstrap" {
  description = "Automatically bootstrap cluster"
  type        = bool
  default     = false
}

variable "auto_start_services" {
  description = "Automatically start services"
  type        = bool
  default     = false
}

variable "additional_tags" {
  description = "Additional tags"
  type        = list(string)
  default     = []
}
