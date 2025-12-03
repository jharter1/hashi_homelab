# Ubuntu template with QEMU Guest Agent
# Builds on: ubuntu-bare-minimum
# Adds: qemu-guest-agent package and service

packer {
  required_plugins {
    proxmox = {
      version = ">= 1.1.3"
      source  = "github.com/hashicorp/proxmox"
    }
  }
}

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

source "proxmox-iso" "ubuntu-qemu-agent" {
  # Proxmox Connection
  proxmox_url              = "${var.proxmox_host}/api2/json"
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # VM Configuration
  vm_id                = 9000
  vm_name              = "ubuntu-qemu-agent"
  template_description = "Ubuntu 22.04 with QEMU Guest Agent"
  os                   = "l26"

  # ISO - Ubuntu 22.04
  boot_iso {
    iso_url          = "https://releases.ubuntu.com/jammy/ubuntu-22.04.5-live-server-amd64.iso"
    iso_checksum     = "sha256:9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0"
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  # Hardware
  memory   = 2048
  cores    = 2
  sockets  = 1
  cpu_type = "x86-64-v2-AES"

  # Storage
  scsi_controller = "virtio-scsi-single"
  disks {
    disk_size    = "20G"
    storage_pool = var.storage_pool
    type         = "scsi"
    format       = "raw"
  }

  # Network
  network_adapters {
    bridge = var.network_bridge
    model  = "virtio"
  }

  # QEMU Agent - enable in VM config
  qemu_agent = true

  # SSH
  ssh_username = "packer"
  ssh_password = "packer"
  ssh_timeout  = "20m"

  # Boot with autoinstall
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

  # HTTP server for autoinstall
  http_directory = "packer/templates/ubuntu/http-qemu-agent"
  http_port_min  = 8000
  http_port_max  = 8100
}

build {
  sources = ["source.proxmox-iso.ubuntu-qemu-agent"]

  # Wait for cloud-init
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait",
      "echo 'Cloud-init completed'"
    ]
  }

  # Verify guest agent is installed and running
  provisioner "shell" {
    inline = [
      "echo '=== Verifying QEMU Guest Agent ==='",
      "dpkg -l | grep qemu-guest-agent",
      "sudo systemctl status qemu-guest-agent --no-pager",
      "ls -la /dev/virtio-ports/org.qemu.guest_agent.0",
      "echo '=== Guest agent verification complete ==='"
    ]
  }

  # Verify network (should have DHCP IP)
  provisioner "shell" {
    inline = [
      "echo '=== Network Status ==='",
      "ip addr show | grep 'inet '",
      "ip route",
      "echo '=== Network verification complete ==='"
    ]
  }
}
