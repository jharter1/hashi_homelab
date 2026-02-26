# Common Packer Variables
# This file contains shared variables used across all Packer templates

# HashiCorp Tool Versions
consul_version = "1.18.0"
vault_version  = "1.16.0"
nomad_version  = "1.10.3"
docker_version = "29.2.1"

# Base VM Configuration
vm_name      = "ubuntu-hashicorp-template"
vm_cores     = 2
vm_disk_size = "30G"

# Storage Configuration
# Note: iso_storage_pool must support ISO content type (e.g., 'local', not 'local-lvm')
iso_storage_pool = "local"

# Network Configuration (can be overridden per environment)
network_bridge = "vmbr0"
dns_servers    = ["1.1.1.1", "8.8.8.8"]
vlan_tag       = 0

# SSH Configuration
ssh_username = "packer"
ssh_password = "packer"

# Template Configuration
template_description_prefix = "HashiCorp-ready VM template built with Packer"
build_timeout               = "30m"
ssh_timeout                 = "20m"
ssh_handshake_attempts      = 30

# Cloud-init Configuration
cloud_init_wait_timeout = "10m"

# Security Settings
disable_password_auth = false # Keep password auth enabled for easier access
disable_root_login    = true
enable_ssh_hardening  = false # Disable hardening to keep password auth working

# Build Optimization
enable_disk_optimization = true
enable_template_cleanup  = true