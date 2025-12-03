# ProxMox Host 1 Environment Variables
# Override common variables for the first ProxMox host

# ProxMox Connection Settings
proxmox_host     = "https://10.0.0.21:8006"
proxmox_node     = "pve1"
proxmox_username = "root@pam"
# Note: proxmox_password should be set via environment variable or command line

# SSH Configuration for clone-based builds (Alpine)
# Note: ssh_password should be set via environment variable or command line for security

# Storage Configuration
storage_pool = "local-lvm"  # For VM disks
iso_storage_pool = "local"  # For ISO files (must support ISO content type)

# Network Configuration
network_cidr = "10.0.0.0/24"
gateway_ip   = "10.0.0.1"

# VM Resource Allocation for Host 1
vm_memory = 2048

# Template VM IDs (must not conflict with existing VMs)
base_template_vmid = 9000

# Environment-specific naming
environment_suffix = "host1"