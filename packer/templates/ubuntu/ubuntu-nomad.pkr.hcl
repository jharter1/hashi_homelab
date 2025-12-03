# Ubuntu template with HashiCorp Consul + Nomad
# Builds on: ubuntu-consul (VM 9002)
# Adds: HashiCorp Nomad binary installation

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

variable "consul_version" {
  type        = string
  description = "HashiCorp Consul version to install"
}

variable "nomad_version" {
  type        = string
  description = "HashiCorp Nomad version to install"
}

source "proxmox-iso" "ubuntu-nomad" {
  # Proxmox Connection
  proxmox_url              = "${var.proxmox_host}/api2/json"
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # VM Configuration
  vm_id                = 9003
  vm_name              = "ubuntu-nomad"
  template_description = "Ubuntu 22.04 with QEMU Agent + Consul ${var.consul_version} + Nomad ${var.nomad_version}"
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

  # QEMU Agent
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
  sources = ["source.proxmox-iso.ubuntu-nomad"]

  # Wait for cloud-init
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait",
      "echo 'Cloud-init completed'"
    ]
  }

  # Install Consul
  provisioner "shell" {
    environment_vars = [
      "CONSUL_VERSION=${var.consul_version}",
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = [
      "echo '=== Installing Consul ${var.consul_version} ==='",
      "cd /tmp",
      "wget -q https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip",
      "sudo apt-get update -qq",
      "sudo apt-get install -y unzip",
      "unzip consul_$${CONSUL_VERSION}_linux_amd64.zip",
      "sudo mv consul /usr/local/bin/",
      "sudo chmod +x /usr/local/bin/consul",
      "rm consul_$${CONSUL_VERSION}_linux_amd64.zip",
      "consul version"
    ]
  }

  # Install Nomad
  provisioner "shell" {
    environment_vars = [
      "NOMAD_VERSION=${var.nomad_version}",
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = [
      "echo '=== Installing Nomad ${var.nomad_version} ==='",
      "cd /tmp",
      "wget -q https://releases.hashicorp.com/nomad/$${NOMAD_VERSION}/nomad_$${NOMAD_VERSION}_linux_amd64.zip",
      "unzip nomad_$${NOMAD_VERSION}_linux_amd64.zip",
      "sudo mv nomad /usr/local/bin/",
      "sudo chmod +x /usr/local/bin/nomad",
      "rm nomad_$${NOMAD_VERSION}_linux_amd64.zip",
      "echo '=== Verifying Nomad installation ==='",
      "nomad version"
    ]
  }

  # Final verification
  provisioner "shell" {
    inline = [
      "echo '=== Final verification ==='",
      "echo 'Consul version:'",
      "consul version",
      "echo 'Nomad version:'",
      "nomad version",
      "echo 'QEMU Guest Agent:'",
      "sudo systemctl status qemu-guest-agent --no-pager | grep Active",
      "echo 'Network:'",
      "ip addr show | grep 'inet ' | grep -v 127.0.0.1",
      "echo '=== Build complete ==='",
    ]
  }
}
