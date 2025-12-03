# Packer Variable Definitions with Validation
# This file defines all variables used across Packer templates

# ProxMox Connection Variables
variable "proxmox_host" {
  type        = string
  description = "ProxMox server URL (https://host:8006)"
  default     = ""
  validation {
    condition     = var.proxmox_host == "" || can(regex("^https://", var.proxmox_host))
    error_message = "ProxMox host must be a valid HTTPS URL or empty (to be set via pkrvars)."
  }
}

variable "proxmox_node" {
  type        = string
  description = "ProxMox node name"
  default     = ""
}

variable "proxmox_username" {
  type        = string
  description = "ProxMox API username"
  default     = "root@pam"
}

variable "proxmox_password" {
  type        = string
  description = "ProxMox API password"
  sensitive   = true
  default     = ""
}

# Storage Configuration
variable "storage_pool" {
  type        = string
  description = "ProxMox storage pool name"
  default     = ""
}

# VM Configuration Variables
variable "vm_name" {
  type        = string
  description = "VM template name"
  default     = "ubuntu-hashicorp-template"
}

variable "vm_memory" {
  type        = number
  description = "VM memory in MB"
  default     = 2048
  validation {
    condition     = var.vm_memory >= 1024 && var.vm_memory <= 32768
    error_message = "VM memory must be between 1024MB and 32768MB."
  }
}

variable "vm_cores" {
  type        = number
  description = "Number of CPU cores"
  default     = 2
  validation {
    condition     = var.vm_cores >= 1 && var.vm_cores <= 16
    error_message = "VM cores must be between 1 and 16."
  }
}

variable "vm_disk_size" {
  type        = string
  description = "VM disk size (e.g., 20G)"
  default     = "20G"
  validation {
    condition     = can(regex("^[0-9]+[GM]$", var.vm_disk_size))
    error_message = "Disk size must be in format like '20G' or '2048M'."
  }
}

# Network Configuration Variables
variable "network_bridge" {
  type        = string
  description = "Network bridge name"
  default     = "vmbr0"
}

variable "network_cidr" {
  type        = string
  description = "Network CIDR block"
  default     = ""
  validation {
    condition     = var.network_cidr == "" || can(cidrhost(var.network_cidr, 0))
    error_message = "Must be a valid CIDR block (e.g., 10.0.0.0/24) or empty (to be set via pkrvars)."
  }
}

variable "gateway_ip" {
  type        = string
  description = "Default gateway IP address"
  default     = ""
  validation {
    condition     = var.gateway_ip == "" || can(regex("^(?:[0-9]{1,3}\\.){3}[0-9]{1,3}$", var.gateway_ip))
    error_message = "Gateway IP must be a valid IPv4 address or empty (to be set via pkrvars)."
  }
}

variable "dns_servers" {
  type        = list(string)
  description = "List of DNS server IP addresses"
  default     = ["1.1.1.1", "8.8.8.8"]
  validation {
    condition     = length(var.dns_servers) > 0
    error_message = "At least one DNS server must be specified."
  }
}

variable "vlan_tag" {
  type        = number
  description = "VLAN tag (optional, use 0 for no VLAN)"
  default     = 0
  validation {
    condition     = var.vlan_tag == 0 || (var.vlan_tag >= 1 && var.vlan_tag <= 4094)
    error_message = "VLAN tag must be between 1 and 4094, or 0 for no VLAN tagging."
  }
}

# SSH Configuration Variables
variable "ssh_username" {
  type        = string
  description = "SSH username for template access"
  default     = "packer"
  validation {
    condition     = length(var.ssh_username) > 0
    error_message = "SSH username cannot be empty."
  }
}

variable "ssh_password" {
  type        = string
  description = "SSH password for template access (used for clone-based builds)"
  sensitive   = true
  default     = ""
}

# Alpine-specific Configuration Variables
variable "alpine_ssh_username" {
  type        = string
  description = "SSH username for Alpine templates (Alpine cloud-init uses 'alpine' user)"
  default     = "alpine"
  validation {
    condition     = length(var.alpine_ssh_username) > 0
    error_message = "Alpine SSH username cannot be empty."
  }
}

variable "alpine_clone_vm_id" {
  type        = number
  description = "VM ID of the Alpine base template to clone from"
  default     = 9001
  validation {
    condition     = var.alpine_clone_vm_id >= 100 && var.alpine_clone_vm_id <= 999999999
    error_message = "Alpine clone VM ID must be between 100 and 999999999."
  }
}

variable "alpine_vm_name" {
  type        = string
  description = "VM name for Alpine template builds"
  default     = "packer-alpine-nomad-temp"
  validation {
    condition     = length(var.alpine_vm_name) > 0
    error_message = "Alpine VM name cannot be empty."
  }
}

variable "alpine_template_name" {
  type        = string
  description = "Name for the Alpine template"
  default     = "alpine-minimal-template"
  validation {
    condition     = length(var.alpine_template_name) > 0
    error_message = "Alpine template name cannot be empty."
  }
}

variable "alpine_template_description" {
  type        = string
  description = "Description for the Alpine template"
  default     = "Lightweight Alpine Linux template with Consul only - for non-containerized tasks (Nomad/Docker not compatible)"
}

# HashiCorp Tool Version Variables
variable "consul_version" {
  type        = string
  description = "Consul version to install"
  default     = "1.18.0"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.consul_version))
    error_message = "Consul version must be in semantic version format (e.g., 1.18.0)."
  }
}

variable "vault_version" {
  type        = string
  description = "Vault version to install"
  default     = "1.16.0"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.vault_version))
    error_message = "Vault version must be in semantic version format (e.g., 1.16.0)."
  }
}

variable "nomad_version" {
  type        = string
  description = "Nomad version to install"
  default     = "1.7.5"
  validation {
    condition     = can(regex("^[0-9]+\\.[0-9]+\\.[0-9]+$", var.nomad_version))
    error_message = "Nomad version must be in semantic version format (e.g., 1.7.5)."
  }
}

variable "docker_version" {
  type        = string
  description = "Docker version to install"
  default     = "24.0.7"
}

# Template Configuration Variables
variable "base_template_vmid" {
  type        = number
  description = "VM ID for the base template"
  default     = 9000
  validation {
    condition     = var.base_template_vmid >= 100 && var.base_template_vmid <= 999999999
    error_message = "Template VM ID must be between 100 and 999999999."
  }
}

variable "nomad_server_template_vmid" {
  type        = number
  description = "VM ID for the Nomad server template"
  default     = 9001
  validation {
    condition     = var.nomad_server_template_vmid >= 100 && var.nomad_server_template_vmid <= 999999999
    error_message = "Nomad server template VM ID must be between 100 and 999999999."
  }
}

variable "nomad_client_template_vmid" {
  type        = number
  description = "VM ID for the Nomad client template"
  default     = 9002
  validation {
    condition     = var.nomad_client_template_vmid >= 100 && var.nomad_client_template_vmid <= 999999999
    error_message = "Nomad client template VM ID must be between 100 and 999999999."
  }
}

variable "template_description_prefix" {
  type        = string
  description = "Prefix for template descriptions"
  default     = "HashiCorp-ready VM template built with Packer"
}

variable "environment_suffix" {
  type        = string
  description = "Environment suffix for naming (e.g., host1, host2)"
  default     = ""
}

# Build Configuration Variables
variable "build_timeout" {
  type        = string
  description = "Maximum time to wait for build completion"
  default     = "30m"
}

variable "ssh_timeout" {
  type        = string
  description = "SSH connection timeout"
  default     = "20m"
}

variable "ssh_handshake_attempts" {
  type        = number
  description = "Number of SSH handshake attempts"
  default     = 30
  validation {
    condition     = var.ssh_handshake_attempts >= 1 && var.ssh_handshake_attempts <= 100
    error_message = "SSH handshake attempts must be between 1 and 100."
  }
}

variable "cloud_init_wait_timeout" {
  type        = string
  description = "Timeout for cloud-init completion"
  default     = "10m"
}

# Security and Optimization Flags
variable "disable_password_auth" {
  type        = bool
  description = "Disable SSH password authentication"
  default     = true
}

variable "disable_root_login" {
  type        = bool
  description = "Disable SSH root login"
  default     = true
}

variable "enable_ssh_hardening" {
  type        = bool
  description = "Enable SSH security hardening"
  default     = true
}

variable "enable_disk_optimization" {
  type        = bool
  description = "Enable disk space optimization"
  default     = true
}

variable "enable_template_cleanup" {
  type        = bool
  description = "Enable template cleanup procedures"
  default     = true
}