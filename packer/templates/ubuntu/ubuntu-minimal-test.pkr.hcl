# Minimal Ubuntu Test Template
# Purpose: Establish a working baseline with just qemu-guest-agent

packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

# Minimal variable declarations
variable "proxmox_host" {
  type = string
}

variable "proxmox_node" {
  type = string
}

variable "proxmox_username" {
  type    = string
  default = "root@pam"
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "storage_pool" {
  type = string
}

variable "iso_storage_pool" {
  type    = string
  default = "local"
}

variable "network_bridge" {
  type    = string
  default = "vmbr0"
}

variable "ssh_username" {
  type    = string
  default = "packer"
}

variable "ssh_password" {
  type      = string
  sensitive = true
  default   = "packer"
}

# Minimal ProxMox ISO Builder
source "proxmox-iso" "ubuntu-minimal" {
  # ProxMox Connection
  proxmox_url              = "${var.proxmox_host}/api2/json"
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # VM Configuration
  vm_id                = 9999
  vm_name              = "ubuntu-minimal-test"
  template_description = "Minimal Ubuntu test template"
  os                   = "l26"

  # ISO Configuration
  boot_iso {
    iso_url          = "https://releases.ubuntu.com/jammy/ubuntu-22.04.5-live-server-amd64.iso"
    iso_checksum     = "sha256:9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0"
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  # Hardware Configuration
  memory   = 2048
  cores    = 2
  sockets  = 1
  cpu_type = "x86-64-v2-AES"
  bios     = "seabios"

  # Storage Configuration
  scsi_controller = "virtio-scsi-single"
  disks {
    disk_size    = "20G"
    storage_pool = var.storage_pool
    type         = "scsi"
    format       = "raw"
    cache_mode   = "writeback"
    io_thread    = true
  }

  # Network Configuration
  network_adapters {
    bridge = var.network_bridge
    model  = "virtio"
  }

  # Additional VM configuration
  onboot = false

  # QEMU Agent
  qemu_agent = true

  # Serial console
  serials = ["socket"]

  # SSH Configuration
  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_timeout            = "20m"
  ssh_handshake_attempts = 30

  # Boot Configuration
  boot      = "c"
  boot_wait = "5s"
  boot_command = [
    "<esc><wait>",
    "e<wait>",
    "<down><down><down><end>",
    "<bs><bs><bs><bs><wait>",
    "autoinstall ds=nocloud-net\\;s=http://{{ .HTTPIP }}:{{ .HTTPPort }}/ ---<wait>",
    "<f10><wait>"
  ]

  # HTTP Server for autoinstall
  http_directory    = "packer/templates/ubuntu/http"
  http_bind_address = "0.0.0.0"
  http_port_min     = 8000
  http_port_max     = 8100
}

# Minimal Build Configuration
build {
  name    = "ubuntu-minimal-test"
  sources = ["source.proxmox-iso.ubuntu-minimal"]

  # Wait for cloud-init to complete
  provisioner "shell" {
    inline = [
      "while [ ! -f /var/lib/cloud/instance/boot-finished ]; do echo 'Waiting for cloud-init...'; sleep 1; done",
      "echo 'Cloud-init completed'",
      "cloud-init status --wait"
    ]
    timeout = "10m"
  }

  # Verify qemu-guest-agent is running (already installed via autoinstall)
  provisioner "shell" {
    inline = [
      "echo '=== Checking qemu-guest-agent status ==='",
      "sudo systemctl status qemu-guest-agent --no-pager",
      "echo '=== Verifying guest agent socket ==='",
      "ls -la /dev/virtio-ports/org.qemu.guest_agent.0 || echo 'Guest agent socket not found'",
      "echo '=== Network configuration ==='",
      "ip addr show",
      "ip route",
      "echo '=== Console configuration ==='",
      "cat /proc/cmdline",
      "echo 'Guest agent verification complete'"
    ]
    timeout = "5m"
  }

  # Test console access
  provisioner "shell" {
    inline = [
      "echo 'Testing serial console output...'",
      "dmesg | grep -i 'console\\|ttyS0' || true",
      "echo 'Console test complete'"
    ]
  }

  # Minimal cleanup
  provisioner "shell" {
    inline = [
      "echo 'Minimal cleanup...'",
      "sudo apt-get autoremove -y",
      "sudo apt-get autoclean",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "sudo truncate -s 0 /etc/machine-id",
      "sudo sync",
      "echo 'Cleanup done'"
    ]
  }
}
