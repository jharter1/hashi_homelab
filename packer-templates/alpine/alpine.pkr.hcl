packer {
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.2"
    }
  }
}

variable "proxmox_password" {
  type      = string
  sensitive = true
  default   = env("PROXMOX_PASSWORD")
}

variable "ssh_username" {
  type    = string
  # Alpine cloud-init template uses 'alpine' user
  default = env("ALPINE_SSH_USERNAME")
}

variable "ssh_password" {
  type      = string
  sensitive = true
  default   = env("SSH_PASSWORD")
}

variable "proxmox_node" {
  type    = string
  default = env("PROXMOX_NODE")
}

variable "proxmox_url" {
  type    = string
  default = env("PROXMOX_URL")
}

variable "clone_vm_id" {
  type    = number
  default = 9001
}

variable "proxmox_username" {
  type    = string
  default = env("PROXMOX_USERNAME")
}

locals {
  # Alpine uses doas instead of sudo
  sudo_command = "doas sh -c '{{ .Vars }} {{ .Path }}'"
}

source "proxmox-clone" "alpine" {
  proxmox_url              = var.proxmox_url
  insecure_skip_tls_verify = true
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node

  vm_name     = "packer-alpine-nomad-temp"
  clone_vm_id = var.clone_vm_id
  full_clone  = true
  task_timeout = "10m"
  
  scsi_controller = "virtio-scsi-pci"

  template_name        = "alpine-minimal-template"
  template_description = "Lightweight Alpine Linux template with Consul only - for non-containerized tasks (Nomad/Docker not compatible)"

  cores  = 2
  memory = 2048

  network_adapters {
    bridge = "vmbr0"
    model  = "virtio"
  }

  ssh_username = var.ssh_username
  ssh_password = var.ssh_password
  ssh_timeout  = "10m"
}

build {
  sources = ["source.proxmox-clone.alpine"]

  # Install sudo and qemu-guest-agent first (cloud-init should have already done this)
  provisioner "shell" {
    inline = [
      "echo '[INFO] Verifying qemu-guest-agent is installed...'",
      "if ! command -v qemu-ga >/dev/null 2>&1; then",
      "  echo 'qemu-guest-agent not found, cloud-init may still be running'",
      "  sleep 10",
      "fi",
      "echo '[INFO] Guest agent check complete'"
    ]
  }

  # Update Alpine and install base packages
  provisioner "shell" {
    execute_command = local.sudo_command
    inline = [
      "echo '[INFO] Updating Alpine and installing base packages...'",
      "apk update",
      "apk add --no-cache curl unzip bash ca-certificates"
    ]
  }

  # Install HashiCorp tools (Consul only)
  provisioner "shell" {
    execute_command = local.sudo_command
    inline = [
      "echo '[INFO] Installing Consul...'",
      "curl -fsSL https://releases.hashicorp.com/consul/1.18.0/consul_1.18.0_linux_amd64.zip -o /tmp/consul.zip",
      "unzip -q /tmp/consul.zip -d /tmp",
      "mv /tmp/consul /usr/local/bin/",
      "chmod +x /usr/local/bin/consul",
      "rm /tmp/consul.zip",
      "/usr/local/bin/consul --version",
      
      "echo '[INFO] Note: Nomad requires glibc and does not work on Alpine (musl)'",
      "echo '[INFO] Docker not installed - this template is for non-containerized tasks only'",
      "echo '[INFO] Use Ubuntu template for Nomad/Docker workloads'"
    ]
  }

  # Cleanup
  provisioner "shell" {
    execute_command = local.sudo_command
    inline = [
      "echo '[INFO] Cleaning up...'",
      "rm -rf /tmp/*",
      "rm -rf /var/cache/apk/*",
      "rm -f /home/${var.ssh_username}/.bash_history",
      "echo '[INFO] Cleanup complete'"
    ]
  }
}
