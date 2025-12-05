packer {
  required_version = ">= 1.9"
  required_plugins {
    proxmox = {
      source  = "github.com/hashicorp/proxmox"
      version = ">= 1.2.0"
    }
  }
}

variable "proxmox_host" {
  type    = string
  default = "https://10.0.0.21:8006"
}

variable "proxmox_node" {
  type    = string
  default = "pve1"
}

variable "proxmox_username" {
  type    = string
  default = "root@pam"
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "iso_url" {
  type    = string
  default = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-13.2.0-amd64-netinst.iso"
}

variable "iso_checksum" {
  type    = string
  default = "sha256:677c4d57aa034dc192b5191870141057574c1b05df2b9569c0ee08aa4e32125d"
}

variable "consul_version" {
  type    = string
  default = "1.18.0"
}

variable "nomad_version" {
  type    = string
  default = "1.10.3"
}

variable "vault_version" {
  type    = string
  default = "1.16.0"
}

source "proxmox-iso" "debian-nomad-server" {
  proxmox_url              = "${var.proxmox_host}/api2/json"
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true
  
  vm_id                = "9500"
  vm_name              = "debian12-nomad-server"
  template_description = "Debian 12 with Consul, Nomad, and Vault for server nodes"
  
  boot_iso {
    iso_url          = var.iso_url
    iso_checksum     = var.iso_checksum
    iso_storage_pool = "local"
    unmount          = true
  }
  
  cores   = 2
  memory  = 4096
  
  scsi_controller = "virtio-scsi-pci"
  
  disks {
    disk_size    = "20G"
    storage_pool = "local-lvm"
    type         = "scsi"
  }
  
  network_adapters {
    model  = "virtio"
    bridge = "vmbr0"
  }
  
  http_directory = "http-iso"
  
  boot_wait = "5s"
  boot_command = [
    "<esc><wait>",
    "install <wait>",
    "auto=true <wait>",
    "priority=critical <wait>",
    "preseed/url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg <wait>",
    "<enter><wait>"
  ]
  
  ssh_username = "root"
  ssh_password = "packer"
  ssh_timeout  = "30m"
}

build {
  sources = ["source.proxmox-iso.debian-nomad-server"]
  
  provisioner "shell" {
    inline = [
      "sudo apt-get update",
      "sudo apt-get install -y openssh-server qemu-guest-agent cloud-init ca-certificates curl gnupg lsb-release unzip wget",
      "sudo systemctl enable qemu-guest-agent",
      "sudo systemctl start qemu-guest-agent"
    ]
  }
  
  # Install Consul
  provisioner "shell" {
    environment_vars = ["CONSUL_VERSION=${var.consul_version}"]
    inline = [
      "echo '=== Installing Consul ==='",
      "cd /tmp",
      "wget https://releases.hashicorp.com/consul/$CONSUL_VERSION/consul_$${CONSUL_VERSION}_linux_amd64.zip",
      "unzip consul_$${CONSUL_VERSION}_linux_amd64.zip",
      "sudo mv consul /usr/local/bin/",
      "sudo chmod +x /usr/local/bin/consul",
      "sudo useradd --system --home /etc/consul.d --shell /bin/false consul || true",
      "sudo mkdir -p /etc/consul.d /opt/consul /var/log/consul",
      "sudo chown -R consul:consul /etc/consul.d /opt/consul /var/log/consul"
    ]
  }
  
  # Install Nomad
  provisioner "shell" {
    environment_vars = ["NOMAD_VERSION=${var.nomad_version}"]
    inline = [
      "set -x",
      "echo '=== Installing Nomad ==='",
      "cd /tmp",
      "wget -q --timeout=30 --tries=3 https://releases.hashicorp.com/nomad/$NOMAD_VERSION/nomad_$${NOMAD_VERSION}_linux_amd64.zip",
      "unzip -o nomad_$${NOMAD_VERSION}_linux_amd64.zip",
      "sudo mv nomad /usr/local/bin/",
      "sudo chmod +x /usr/local/bin/nomad",
      "sudo useradd --system --home /etc/nomad.d --shell /bin/false nomad || true",
      "sudo mkdir -p /etc/nomad.d /opt/nomad /var/log/nomad",
      "sudo chown -R nomad:nomad /etc/nomad.d /opt/nomad /var/log/nomad"
    ]
  }
  
  # Install Vault
  provisioner "shell" {
    environment_vars = ["VAULT_VERSION=${var.vault_version}"]
    inline = [
      "echo '=== Installing Vault ==='",
      "cd /tmp",
      "wget https://releases.hashicorp.com/vault/$VAULT_VERSION/vault_$${VAULT_VERSION}_linux_amd64.zip",
      "unzip vault_$${VAULT_VERSION}_linux_amd64.zip",
      "sudo mv vault /usr/local/bin/",
      "sudo chmod +x /usr/local/bin/vault",
      "sudo useradd --system --home /etc/vault.d --shell /bin/false vault || true",
      "sudo mkdir -p /etc/vault.d /opt/vault /var/log/vault",
      "sudo chown -R vault:vault /etc/vault.d /opt/vault /var/log/vault"
    ]
  }
  
  # Cleanup
  provisioner "shell" {
    inline = [
      "set -x",
      "echo '=== Starting Cleanup ==='",
      "apt-get clean",
      "rm -rf /tmp/* /var/tmp/*",
      "cloud-init clean --logs",
      "echo '=== Zeroing out disk to improve compression (this may take a few minutes) ==='",
      "dd if=/dev/zero of=/EMPTY bs=1M status=progress || true",
      "rm -f /EMPTY",
      "echo '=== Cleanup Complete ==='"
    ]
  }
}
