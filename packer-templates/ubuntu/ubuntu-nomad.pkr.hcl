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
}

variable "ssh_username" {
  type    = string
  # Ubuntu cloud-init template uses 'packer' user
  default = env("UBUNTU_SSH_USERNAME")
}

variable "ssh_password" {
  type      = string
  sensitive = true
  default   = env("SSH_PASSWORD")
}

variable "proxmox_node" {
  type    = string
}

variable "proxmox_url" {
  type    = string
}

variable "clone_vm_id" {
  type = number
}

variable "proxmox_username" {
  type    = string
}

locals {
  # Common provisioner settings
  sudo_command = "echo '${var.ssh_password}' | sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
  noninteractive_env = ["DEBIAN_FRONTEND=noninteractive"]
}

source "proxmox-clone" "ubuntu_nomad" {
  proxmox_url              = var.proxmox_url
  insecure_skip_tls_verify = true
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node

  vm_name     = "packer-ubuntu-nomad-temp"
  clone_vm_id = var.clone_vm_id
  full_clone  = true
  task_timeout = "10m"

  scsi_controller = "virtio-scsi-pci"

  template_name        = "ubuntu-nomad-template"
  template_description = "Ubuntu template with Nomad, Consul, and Docker"

  cores  = 2
  memory = 2048

  network_adapters {
    bridge = "vmbr0"
    model  = "virtio"
  }

  ssh_username           = var.ssh_username
  ssh_password           = var.ssh_password
  ssh_timeout            = "20m"
  ssh_handshake_attempts = 30
}

build {
  sources = ["source.proxmox-clone.ubuntu_nomad"]

  # Wait for cloud-init and install base packages
  provisioner "shell" {
    execute_command  = local.sudo_command
    environment_vars = local.noninteractive_env
    inline = [
      "echo 'Waiting for cloud-init and unattended-upgrades to finish...'",
      "while sudo fuser /var/lib/dpkg/lock-frontend >/dev/null 2>&1 || sudo fuser /var/lib/apt/lists/lock >/dev/null 2>&1; do echo 'Waiting for apt lock...'; sleep 5; done",
      "cloud-init status --wait || echo 'cloud-init wait failed, continuing anyway'",
      "apt-get update -y",
      "apt-get install -y qemu-guest-agent curl unzip"
    ]
  }

  # Install HashiCorp Nomad and Consul
  provisioner "shell" {
    execute_command  = local.sudo_command
    environment_vars = local.noninteractive_env
    inline = [
      "curl -fsSL https://releases.hashicorp.com/consul/1.18.0/consul_1.18.0_linux_amd64.zip -o /tmp/consul.zip",
      "unzip -q /tmp/consul.zip -d /tmp",
      "mv /tmp/consul /usr/local/bin/",
      "chmod +x /usr/local/bin/consul",
      "rm /tmp/consul.zip",
      "consul --version",
      
      "echo '[INFO] Installing Nomad...'",
      "curl -fsSL https://releases.hashicorp.com/nomad/1.7.5/nomad_1.7.5_linux_amd64.zip -o /tmp/nomad.zip",
      "unzip -q /tmp/nomad.zip -d /tmp",
      "mv /tmp/nomad /usr/local/bin/",
      "chmod +x /usr/local/bin/nomad",
      "rm /tmp/nomad.zip",
      "nomad --version"
    ]
  }

  # Install Docker
  provisioner "shell" {
    execute_command  = local.sudo_command
    environment_vars = local.noninteractive_env
    inline = [
      "echo '[INFO] Installing Docker...'",
      "DEBIAN_FRONTEND=noninteractive apt-get install -y docker.io docker-compose",
      "systemctl enable docker",
      "systemctl start docker",
      "usermod -aG docker ${var.ssh_username}",
      "docker --version"
    ]
  }

  # Cleanup
  provisioner "shell" {
    execute_command  = local.sudo_command
    environment_vars = local.noninteractive_env
    inline = [
      "echo '[INFO] Cleaning up...'",
      "apt-get clean",
      "rm -rf /tmp/*",
      "rm -rf /var/lib/apt/lists/*",
      "rm -f /home/${var.ssh_username}/.bash_history",
      "echo '[INFO] Cleanup complete'"
    ]
  }
}
