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
  type    = number
  default = env("UBUNTU_BASE_VMID")
}

locals {
  # Common provisioner settings
  sudo_command = "echo '${var.proxmox_password}' | sudo -S sh -c '{{ .Vars }} {{ .Path }}'"
  noninteractive_env = ["DEBIAN_FRONTEND=noninteractive"]
}

source "proxmox-clone" "golden_template" {
  proxmox_url              = var.proxmox_url
  insecure_skip_tls_verify = true
  username                 = env("PROXMOX_USERNAME")
  password                 = var.proxmox_password
  node                     = var.proxmox_node

  vm_name     = "packer-build-temp"
  clone_vm_id = var.clone_vm_id
  full_clone  = true
  task_timeout = "10m"

  scsi_controller = "virtio-scsi-pci"

  template_name        = "golden-ubuntu-template"
  template_description = "Base Ubuntu cloud-init template with HashiCorp tools and Docker"

  cores  = 2
  memory = 2048

  network_adapters {
    bridge = "vmbr0"
    model  = "virtio"
  }

  ssh_username           = var.ssh_username
  ssh_password           = var.proxmox_password
  ssh_timeout            = "20m"
  ssh_handshake_attempts = 30
}

build {
  sources = ["source.proxmox-clone.golden_template"]

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

  # Install HashiCorp tools
  provisioner "file" {
    source      = "install_hashicorp.sh"
    destination = "/tmp/install_hashicorp.sh"
  }

  provisioner "shell" {
    execute_command  = local.sudo_command
    environment_vars = local.noninteractive_env
    inline = [
      "df -h",
      "chmod +x /tmp/install_hashicorp.sh",
      "/tmp/install_hashicorp.sh"
    ]
  }

  # Install Docker for Nomad container runtime
  provisioner "shell" {
    execute_command  = local.sudo_command
    environment_vars = local.noninteractive_env
    inline = [
      "echo '[INFO] Installing Docker Engine...'",
      "apt-get install -y ca-certificates curl gnupg lsb-release",
      "install -m 0755 -d /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc",
      "chmod a+r /etc/apt/keyrings/docker.asc",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu $(. /etc/os-release && echo $VERSION_CODENAME) stable\" > /etc/apt/sources.list.d/docker.list",
      "apt-get update -y",
      "apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
      "usermod -aG docker ${var.ssh_username}",
      "systemctl enable docker",
      "systemctl start docker",
      "docker --version",
      "echo '[INFO] Docker installed successfully'"
    ]
  }

  # Cleanup and optimize template
  provisioner "shell" {
    execute_command  = local.sudo_command
    environment_vars = local.noninteractive_env
    inline = [
      "echo '[INFO] Starting template cleanup and optimization...'",
      "rm -f /tmp/install_hashicorp.sh",
      "rm -f /home/${var.ssh_username}/.bash_history",
      "rm -f /home/${var.ssh_username}/.ssh/authorized_keys",
      "rm -rf /home/${var.ssh_username}/.ssh",
      "rm -f /root/.bash_history",
      "find /var/log -type f -delete",
      "find /var/log -type f -name '*.gz' -delete",
      "apt-get clean",
      "apt-get autoclean",
      "rm -rf /var/lib/apt/lists/*",
      "rm -rf /tmp/*",
      "rm -rf /var/tmp/*",
      "truncate -s 0 /etc/machine-id",
      "echo '[INFO] Cleanup complete'"
    ]
  }

  # Harden SSH configuration
  provisioner "shell" {
    execute_command = local.sudo_command
    inline = [
      "echo '[INFO] Hardening SSH configuration...'",
      "sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication no/' /etc/ssh/sshd_config",
      "sed -i 's/^#*ChallengeResponseAuthentication.*/ChallengeResponseAuthentication no/' /etc/ssh/sshd_config",
      "sed -i 's/^#*UsePAM.*/UsePAM no/' /etc/ssh/sshd_config",
      "sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' /etc/ssh/sshd_config",
      "echo '[INFO] SSH hardened - key-based authentication only'"
    ]
  }

  # Reset cloud-init for template use
  provisioner "shell" {
    execute_command = local.sudo_command
    inline = [
      "echo '[INFO] Resetting cloud-init for template...'",
      "cloud-init clean --logs --seed",
      "rm -rf /var/lib/cloud/instances/*",
      "rm -rf /var/lib/cloud/instance",
      "rm -rf /var/lib/cloud/data",
      "echo '[INFO] Cloud-init reset complete'"
    ]
  }

  # Zero out free space for efficient storage
  provisioner "shell" {
    execute_command = local.sudo_command
    inline = [
      "echo '[INFO] Zeroing out free disk space for optimal compression...'",
      "echo 'This may take several minutes...'",
      "dd if=/dev/zero of=/EMPTY bs=1M || echo 'dd completed (expected error when disk full)'",
      "rm -f /EMPTY",
      "sync",
      "echo '[INFO] Disk optimization complete'"
    ]
  }
}
