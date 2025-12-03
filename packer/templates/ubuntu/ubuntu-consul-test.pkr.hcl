# Ubuntu TEST template with HashiCorp Consul
# Test template for Consul configuration with proper user, directories, and systemd service
# VM ID: 9010 (to avoid conflicts with existing templates)

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

source "proxmox-iso" "ubuntu-consul-test" {
  # Proxmox Connection
  proxmox_url              = "${var.proxmox_host}/api2/json"
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # VM Configuration
  vm_id                = 9010
  vm_name              = "ubuntu-consul-test"
  template_description = "Ubuntu 22.04 TEST - QEMU Agent + Consul ${var.consul_version} with proper configuration"
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
  sources = ["source.proxmox-iso.ubuntu-consul-test"]

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
      "echo 'Extracting Consul...'",
      "unzip consul_$${CONSUL_VERSION}_linux_amd64.zip",
      "sudo mv consul /usr/local/bin/",
      "sudo chmod +x /usr/local/bin/consul",
      "rm consul_$${CONSUL_VERSION}_linux_amd64.zip",
      "echo '=== Verifying Consul installation ==='",
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

  # Verify everything works
  provisioner "shell" {
    inline = [
      "echo '=== Final verification ==='",
      "echo 'Consul version:'",
      "consul version",
      "echo ''",
      "echo 'Consul user:'",
      "id consul",
      "echo ''",
      "echo 'Consul directories:'",
      "ls -la /etc/consul.d/",
      "ls -la /opt/consul/",
      "ls -la /var/log/consul/",
      "echo ''",
      "echo 'Consul systemd service:'",
      "systemctl status consul --no-pager || true",
      "echo ''",
      "echo 'QEMU Guest Agent:'",
      "sudo systemctl status qemu-guest-agent --no-pager | grep Active",
      "echo ''",
      "echo 'Network:'",
      "ip addr show | grep 'inet ' | grep -v 127.0.0.1",
      "echo ''",
      "echo '=== Build complete ==='"
    ]
  }
}
