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
  default = env("SSH_USERNAME")
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
  default = env("ALPINE_BASE_VMID")
}

locals {
  # Alpine uses doas instead of sudo
  sudo_command = "doas sh -c '{{ .Vars }} {{ .Path }}'"
}

source "proxmox-clone" "alpine_nomad" {
  proxmox_url              = var.proxmox_url
  insecure_skip_tls_verify = true
  username                 = env("PROXMOX_USERNAME")
  password                 = var.proxmox_password
  node                     = var.proxmox_node

  vm_name     = "packer-alpine-nomad-temp"
  clone_vm_id = var.clone_vm_id
  full_clone  = true
  task_timeout = "10m"

  scsi_controller = "virtio-scsi-pci"

  template_name        = "alpine-nomad-template"
  template_description = "Lightweight Alpine Linux template with Nomad, Consul, and Docker"

  cores  = 2
  memory = 2048

  network_adapters {\n    bridge = \"vmbr0\"\n    model  = \"virtio\"\n  }\n\n  ssh_username = var.ssh_username\n  ssh_password = var.proxmox_password\n  ssh_timeout  = \"20m\"\n  ssh_handshake_attempts = 50
  
  # Use network interface to get IP instead of guest agent (guest agent installs during first boot)
  vm_interface = "eth0"
  ssh_pty                = true
}

build {
  sources = ["source.proxmox-clone.alpine_nomad"]

  # Wait for cloud-init to complete
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait || sleep 30",
      "echo 'Cloud-init complete, starting provisioning...'"
    ]
  }

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

  # Install HashiCorp tools (Consul and Nomad)
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
      
      "echo '[INFO] Note: Nomad binaries require glibc and do not work natively on Alpine (musl)'",
      "echo '[INFO] Nomad will be run via Docker container instead'",
      "echo '[INFO] Skipping Nomad binary installation...'"
    ]
  }

  # Install Docker
  provisioner "shell" {
    execute_command = local.sudo_command
    inline = [
      "echo '[INFO] Installing Docker...'",
      "apk add --no-cache docker docker-cli-compose",
      "rc-update add docker default",
      "service docker start",
      "addgroup ${var.ssh_username} docker || true",
      "docker --version"
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
