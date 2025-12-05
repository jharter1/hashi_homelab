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

source "proxmox-iso" "ubuntu-nomad-client" {
  # Proxmox Connection
  proxmox_url              = "${var.proxmox_host}/api2/json"
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # VM Template Settings
  vm_id                = 9301
  vm_name              = "ubuntu-nomad-client"
  template_description = "Ubuntu 22.04 - Nomad Client with Docker"

  # ISO - Ubuntu 22.04
  boot_iso {
    iso_url          = "https://releases.ubuntu.com/jammy/ubuntu-22.04.5-live-server-amd64.iso"
    iso_checksum     = "sha256:9bc6028870aef3f74f4e16b900008179e78b130e6b0b9a140635434a46aa98b0"
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  # HTTP directory for cloud-init
  http_directory = "packer/templates/ubuntu/http-qemu-agent"
  http_port_min  = 8000
  http_port_max  = 8100

  os = "l26"

  onboot = false

  # Hardware - Clients need more resources for running workloads
  memory   = 8192
  cores    = 4
  sockets  = 1
  cpu_type = "x86-64-v2-AES"

  # Storage - More disk space for containers
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
  ssh_timeout  = "30m"

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
}

build {
  sources = ["source.proxmox-iso.ubuntu-nomad-client"]

  # Wait for cloud-init to complete
  provisioner "shell" {
    inline = [
      "echo 'Waiting for cloud-init to complete...'",
      "cloud-init status --wait",
      "echo 'Cloud-init complete'",
    ]
  }

  # Configure cloud-init for Proxmox
  provisioner "shell" {
    inline = [
      "echo '=== Configuring cloud-init for Proxmox ==='",
      "# Remove installer datasource config",
      "sudo rm -f /etc/cloud/cloud.cfg.d/99-installer.cfg",
      "sudo rm -f /etc/cloud/cloud.cfg.d/subiquity-disable-cloudinit-networking.cfg",
      "# Configure datasources for Proxmox (NoCloud reads from ide2 CD-ROM)",
      "echo 'datasource_list: [ NoCloud, ConfigDrive ]' | sudo tee /etc/cloud/cloud.cfg.d/99-pve.cfg",
      "# Clean cloud-init state so it runs on next boot",
      "sudo cloud-init clean --logs",
      "echo 'Cloud-init configured for Proxmox'",
    ]
  }

  # Install Docker
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = [
      "echo '=== Installing Docker ==='",
      "# Install prerequisites",
      "sudo apt-get update",
      "sudo apt-get install -y ca-certificates curl gnupg lsb-release unzip wget",
      "# Add Docker's official GPG key",
      "sudo install -m 0755 -d /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "sudo chmod a+r /etc/apt/keyrings/docker.gpg",
      "# Set up the repository",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "# Install Docker Engine",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
      "# Verify Docker installation",
      "sudo docker --version",
      "sudo systemctl status docker --no-pager | grep Active",
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
      "# Add nomad user to docker group for container management",
      "sudo usermod -aG docker nomad",
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
      "# Client mode will be configured via cloud-init",
      "",
      "plugin \"docker\" {",
      "  config {",
      "    allow_privileged = false",
      "    volumes {",
      "      enabled = true",
      "    }",
      "  }",
      "}",
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
      "Requires=docker.service",
      "After=docker.service",
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
      "echo '=== Final verification - Nomad Client ==='",
      "echo 'Docker:'",
      "sudo docker --version",
      "echo ''",
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
      "echo '=== Build complete - Nomad Client ready ==='",
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
