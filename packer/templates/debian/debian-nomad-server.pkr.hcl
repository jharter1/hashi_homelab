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

variable "proxmox_username" {
  type = string
}

variable "proxmox_password" {
  type      = string
  sensitive = true
}

variable "proxmox_node" {
  type = string
}

variable "iso_storage_pool" {
  type = string
}

variable "storage_pool" {
  type = string
}

variable "network_bridge" {
  type = string
}

variable "consul_version" {
  type = string
}

variable "nomad_version" {
  type = string
}

source "proxmox-clone" "debian-nomad-server" {
  # Proxmox Connection
  proxmox_url              = "${var.proxmox_host}/api2/json"
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # Clone from base Debian 12 cloud image template
  clone_vm_id = 9400
  
  # VM Template Settings
  vm_id                = 9402
  vm_name              = "debian-nomad-server"
  template_description = "Debian 12 - Nomad Server with Consul"

  os = "l26"

  onboot = false

  # Hardware
  memory   = 8192
  cores    = 4
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

  # SSH credentials from cloud-init
  ssh_username = "packer"
  ssh_password = "packer"
  ssh_timeout  = "5m"
}

build {
  sources = ["source.proxmox-clone.debian-nomad-server"]

  # Configure cloud-init for Proxmox
  provisioner "shell" {
    inline = [
      "echo '=== Configuring cloud-init for Proxmox ==='",
      "# Configure datasources for Proxmox (NoCloud reads from ide2 CD-ROM)",
      "echo 'datasource_list: [ NoCloud, ConfigDrive ]' | sudo tee /etc/cloud/cloud.cfg.d/99-pve.cfg",
      "# Clean cloud-init state so it runs on next boot",
      "sudo cloud-init clean --logs",
      "echo 'Cloud-init configured for Proxmox'",
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
      "sudo useradd --system --home /etc/consul.d --shell /bin/false consul",
      "sudo mkdir -p /etc/consul.d /opt/consul /var/log/consul",
      "sudo chown -R consul:consul /etc/consul.d /opt/consul /var/log/consul",
      "sudo chmod 755 /etc/consul.d /opt/consul /var/log/consul",
      "echo '=== Consul user and directories configured ==='"
    ]
  }

  # Create Consul base configuration
  provisioner "shell" {
    inline = [
      "echo '=== Creating Consul base configuration ==='",
      "sudo tee /etc/consul.d/consul.hcl > /dev/null <<'EOF'",
      "datacenter = \"dc1\"",
      "data_dir = \"/opt/consul\"",
      "log_file = \"/var/log/consul/consul.log\"",
      "log_level = \"INFO\"",
      "",
      "connect {",
      "  enabled = true",
      "}",
      "",
      "performance {",
      "  raft_multiplier = 1",
      "}",
      "",
      "ui_config {",
      "  enabled = true",
      "}",
      "EOF",
      "sudo chown consul:consul /etc/consul.d/consul.hcl",
      "sudo chmod 640 /etc/consul.d/consul.hcl",
      "echo '=== Consul base configuration created ==='"
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

  # Configure Nomad user and directories
  provisioner "shell" {
    inline = [
      "echo '=== Configuring Nomad user and directories ==='",
      "sudo useradd --system --home /etc/nomad.d --shell /bin/false nomad",
      "sudo mkdir -p /etc/nomad.d /opt/nomad /var/log/nomad",
      "sudo chown -R nomad:nomad /etc/nomad.d /opt/nomad /var/log/nomad",
      "sudo chmod 755 /etc/nomad.d /opt/nomad /var/log/nomad",
      "echo '=== Nomad user and directories configured ==='"
    ]
  }

  # Create Nomad base configuration
  provisioner "shell" {
    inline = [
      "echo '=== Creating Nomad base configuration ==='",
      "sudo tee /etc/nomad.d/nomad.hcl > /dev/null <<'EOF'",
      "datacenter = \"dc1\"",
      "region = \"global\"",
      "data_dir = \"/opt/nomad\"",
      "log_file = \"/var/log/nomad/nomad.log\"",
      "log_level = \"INFO\"",
      "",
      "# Server/client mode will be configured via cloud-init",
      "",
      "consul {",
      "  address = \"127.0.0.1:8500\"",
      "}",
      "EOF",
      "sudo chown nomad:nomad /etc/nomad.d/nomad.hcl",
      "sudo chmod 640 /etc/nomad.d/nomad.hcl",
      "echo '=== Nomad base configuration created ==='"
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

  # Final verification
  provisioner "shell" {
    inline = [
      "echo '=== Final verification - Nomad Server ==='",
      "echo 'Consul:'",
      "consul version",
      "echo ''",
      "echo 'Nomad:'",
      "nomad version",
      "echo ''",
      "echo 'QEMU Guest Agent:'",
      "sudo systemctl status qemu-guest-agent --no-pager | grep Active",
      "echo ''",
      "echo 'Nomad config:'",
      "sudo cat /etc/nomad.d/nomad.hcl",
      "echo ''",
      "echo '=== Build complete - Nomad Server ready ==='",
    ]
  }

  # Cleanup and hardening
  provisioner "shell" {
    inline = [
      "echo '=== Cleaning up and hardening template ==='",
      "# Force SSH reconfiguration to ensure keys regenerate on first boot",
      "sudo DEBIAN_FRONTEND=noninteractive dpkg-reconfigure openssh-server",
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
      "# Zero out free space for better compression",
      "echo 'Zeroing free space (this may take a few minutes)...'",
      "sudo dd if=/dev/zero of=/EMPTY bs=1M || true",
      "sudo rm -f /EMPTY",
      "sudo sync",
      "echo '=== Cleanup complete ==='",
    ]
  }
}
