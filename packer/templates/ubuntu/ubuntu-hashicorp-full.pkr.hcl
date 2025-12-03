# Ubuntu template with full HashiCorp stack
# Builds on: ubuntu-nomad (VM 9003)
# Adds: HashiCorp Vault to complete the stack

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

variable "vault_version" {
  type        = string
  description = "HashiCorp Vault version to install"
}

source "proxmox-iso" "ubuntu-hashicorp-full" {
  # Proxmox Connection
  proxmox_url              = "${var.proxmox_host}/api2/json"
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # VM Configuration
  vm_id                = 9004
  vm_name              = "ubuntu-hashicorp-full"
  template_description = "Ubuntu 22.04 with full HashiCorp stack: Consul ${var.consul_version}, Nomad ${var.nomad_version}, Vault ${var.vault_version}"
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
  sources = ["source.proxmox-iso.ubuntu-hashicorp-full"]

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
      "sudo apt-get update -qq",
      "sudo apt-get install -y unzip wget",
      "cd /tmp",
      "echo 'Downloading Consul...'",
      "wget --show-progress https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip",
      "unzip consul_$${CONSUL_VERSION}_linux_amd64.zip",
      "sudo mv consul /usr/local/bin/",
      "sudo chmod +x /usr/local/bin/consul",
      "rm consul_$${CONSUL_VERSION}_linux_amd64.zip",
      "consul version"
    ]
  }

  # Configure Consul user and directories
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = [
      "echo '=== Configuring Consul user and directories ==='",
      "# Create consul system user",
      "sudo useradd --system --home /etc/consul.d --shell /bin/false consul",
      "# Create required directories",
      "sudo mkdir -p /etc/consul.d",
      "sudo mkdir -p /opt/consul",
      "sudo mkdir -p /var/log/consul",
      "# Set ownership",
      "sudo chown -R consul:consul /etc/consul.d",
      "sudo chown -R consul:consul /opt/consul",
      "sudo chown -R consul:consul /var/log/consul",
      "# Set permissions",
      "sudo chmod 755 /etc/consul.d",
      "sudo chmod 755 /opt/consul",
      "sudo chmod 755 /var/log/consul",
      "echo '=== Consul directories configured ==='"
    ]
  }

  # Create Consul configuration
  provisioner "shell" {
    inline = [
      "echo '=== Creating Consul configuration ==='",
      "sudo tee /etc/consul.d/consul.hcl > /dev/null <<'EOF'",
      "datacenter = \"dc1\"",
      "data_dir = \"/opt/consul\"",
      "log_file = \"/var/log/consul/consul.log\"",
      "log_level = \"INFO\"",
      "",
      "# Enable service mesh",
      "connect {",
      "  enabled = true",
      "}",
      "",
      "# Performance tuning",
      "performance {",
      "  raft_multiplier = 1",
      "}",
      "",
      "# Retry join configuration - customize per deployment",
      "retry_join = []",
      "",
      "# UI configuration",
      "ui_config {",
      "  enabled = true",
      "}",
      "EOF",
      "sudo chown consul:consul /etc/consul.d/consul.hcl",
      "sudo chmod 640 /etc/consul.d/consul.hcl",
      "echo '=== Consul configuration created ==='"
    ]
  }

  # Create Consul systemd service
  provisioner "shell" {
    inline = [
      "echo '=== Creating Consul systemd service ==='",
      "sudo tee /etc/systemd/system/consul.service > /dev/null <<'EOF'",
      "[Unit]",
      "Description=Consul Service Discovery Agent",
      "Documentation=https://www.consul.io/",
      "After=network-online.target",
      "Wants=network-online.target",
      "",
      "[Service]",
      "Type=notify",
      "User=consul",
      "Group=consul",
      "ExecStart=/usr/local/bin/consul agent -config-dir=/etc/consul.d/",
      "ExecReload=/bin/kill -HUP $MAINPID",
      "KillMode=process",
      "KillSignal=SIGTERM",
      "Restart=on-failure",
      "RestartSec=5",
      "LimitNOFILE=65536",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable consul",
      "echo '=== Consul systemd service created and enabled ==='"
    ]
  }

  # Configure Nomad user and directories
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = [
      "echo '=== Configuring Nomad user and directories ==='",
      "# Create nomad system user",
      "sudo useradd --system --home /etc/nomad.d --shell /bin/false nomad",
      "# Create required directories",
      "sudo mkdir -p /etc/nomad.d",
      "sudo mkdir -p /opt/nomad",
      "sudo mkdir -p /var/log/nomad",
      "# Set ownership",
      "sudo chown -R nomad:nomad /etc/nomad.d",
      "sudo chown -R nomad:nomad /opt/nomad",
      "sudo chown -R nomad:nomad /var/log/nomad",
      "# Set permissions",
      "sudo chmod 755 /etc/nomad.d",
      "sudo chmod 755 /opt/nomad",
      "sudo chmod 755 /var/log/nomad",
      "echo '=== Nomad directories configured ==='"
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
      "echo 'Downloading Nomad...'",
      "wget --show-progress https://releases.hashicorp.com/nomad/$${NOMAD_VERSION}/nomad_$${NOMAD_VERSION}_linux_amd64.zip",
      "unzip nomad_$${NOMAD_VERSION}_linux_amd64.zip",
      "sudo mv nomad /usr/local/bin/",
      "sudo chmod +x /usr/local/bin/nomad",
      "rm nomad_$${NOMAD_VERSION}_linux_amd64.zip",
      "nomad version"
    ]
  }

  # Install Vault
  provisioner "shell" {
    environment_vars = [
      "VAULT_VERSION=${var.vault_version}",
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = [
      "echo '=== Installing Vault ${var.vault_version} ==='",
      "cd /tmp",
      "echo 'Downloading Vault...'",
      "wget --show-progress https://releases.hashicorp.com/vault/$${VAULT_VERSION}/vault_$${VAULT_VERSION}_linux_amd64.zip",
      "unzip vault_$${VAULT_VERSION}_linux_amd64.zip",
      "sudo mv vault /usr/local/bin/",
      "sudo chmod +x /usr/local/bin/vault",
      "rm vault_$${VAULT_VERSION}_linux_amd64.zip",
      "echo '=== Verifying Vault installation ==='",
      "vault version"
    ]
  }

  # Configure Vault user and directories
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = [
      "echo '=== Configuring Vault user and directories ==='",
      "# Create vault system user",
      "sudo useradd --system --home /etc/vault.d --shell /bin/false vault",
      "# Create required directories",
      "sudo mkdir -p /etc/vault.d",
      "sudo mkdir -p /opt/vault",
      "sudo mkdir -p /var/log/vault",
      "# Set ownership",
      "sudo chown -R vault:vault /etc/vault.d",
      "sudo chown -R vault:vault /opt/vault",
      "sudo chown -R vault:vault /var/log/vault",
      "# Set permissions",
      "sudo chmod 755 /etc/vault.d",
      "sudo chmod 755 /opt/vault",
      "sudo chmod 755 /var/log/vault",
      "echo '=== Vault directories configured ==='"
    ]
  }

  # Create Nomad systemd service
  provisioner "shell" {
    inline = [
      "echo '=== Creating Nomad systemd service ==='",
      "sudo tee /etc/systemd/system/nomad.service > /dev/null <<'EOF'",
      "[Unit]",
      "Description=Nomad",
      "Documentation=https://www.nomadproject.io/docs/",
      "Wants=network-online.target",
      "After=network-online.target",
      "",
      "[Service]",
      "User=nomad",
      "Group=nomad",
      "ExecReload=/bin/kill -HUP $MAINPID",
      "ExecStart=/usr/local/bin/nomad agent -config=/etc/nomad.d",
      "KillMode=process",
      "KillSignal=SIGINT",
      "LimitNOFILE=65536",
      "LimitNPROC=infinity",
      "Restart=on-failure",
      "RestartSec=2",
      "TasksMax=infinity",
      "OOMScoreAdjust=-1000",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable nomad",
      "echo '=== Nomad systemd service created and enabled ==='"
    ]
  }

  # Create Vault systemd service
  provisioner "shell" {
    inline = [
      "echo '=== Creating Vault systemd service ==='",
      "sudo tee /etc/systemd/system/vault.service > /dev/null <<'EOF'",
      "[Unit]",
      "Description=Vault secret management tool",
      "Documentation=https://www.vaultproject.io/docs/",
      "Requires=network-online.target",
      "After=network-online.target",
      "",
      "[Service]",
      "User=vault",
      "Group=vault",
      "ProtectSystem=full",
      "ProtectHome=read-only",
      "PrivateTmp=yes",
      "PrivateDevices=yes",
      "SecureBits=keep-caps",
      "AmbientCapabilities=CAP_IPC_LOCK",
      "CapabilityBoundingSet=CAP_SYSLOG CAP_IPC_LOCK",
      "NoNewPrivileges=yes",
      "ExecStart=/usr/local/bin/vault server -config=/etc/vault.d",
      "ExecReload=/bin/kill --signal HUP $MAINPID",
      "KillMode=process",
      "KillSignal=SIGINT",
      "Restart=on-failure",
      "RestartSec=5",
      "LimitNOFILE=65536",
      "LimitMEMLOCK=infinity",
      "",
      "[Install]",
      "WantedBy=multi-user.target",
      "EOF",
      "sudo systemctl daemon-reload",
      "sudo systemctl enable vault",
      "echo '=== Vault systemd service created and enabled ==='"
    ]
  }

  # Final verification
  provisioner "shell" {
    inline = [
      "echo '=== Final verification - Full HashiCorp Stack ==='",
      "echo 'Consul:'",
      "consul version",
      "echo ''",
      "echo 'Nomad:'",
      "nomad version",
      "echo ''",
      "echo 'Vault:'",
      "vault version",
      "echo ''",
      "echo 'QEMU Guest Agent:'",
      "sudo systemctl status qemu-guest-agent --no-pager | grep Active",
      "echo ''",
      "echo 'Network:'",
      "ip addr show | grep 'inet ' | grep -v 127.0.0.1",
      "echo ''",
      "echo '=== Build complete - Full HashiCorp stack installed ==='",
    ]
  }

  # Cleanup and hardening
  provisioner "shell" {
    inline = [
      "echo '=== Cleaning up and hardening template ==='",
      "# Remove SSH host keys (regenerated on first boot)",
      "sudo rm -f /etc/ssh/ssh_host_*",
      "# Truncate machine-id (regenerated on first boot)",
      "sudo truncate -s 0 /etc/machine-id",
      "# Clean package manager cache",
      "sudo apt-get autoremove -y",
      "sudo apt-get autoclean -y",
      "sudo apt-get clean -y",
      "# Remove temporary files",
      "sudo rm -rf /tmp/*",
      "sudo rm -rf /var/tmp/*",
      "# Clear shell history",
      "cat /dev/null > ~/.bash_history",
      "sudo rm -f /root/.bash_history",
      "# Zero out free space for better compression (optional but makes clones faster)",
      "echo 'Zeroing free space (this may take a few minutes)...'",
      "sudo dd if=/dev/zero of=/EMPTY bs=1M || true",
      "sudo rm -f /EMPTY",
      "sudo sync",
      "echo '=== Cleanup complete ==='",
    ]
  }
}
