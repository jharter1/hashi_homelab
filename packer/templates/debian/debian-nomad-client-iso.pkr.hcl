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

source "proxmox-iso" "debian-nomad-client" {
  # Proxmox Connection
  proxmox_url              = "${var.proxmox_host}/api2/json"
  username                 = var.proxmox_username
  password                 = var.proxmox_password
  node                     = var.proxmox_node
  insecure_skip_tls_verify = true

  # VM Template Settings
  vm_id                = 9501
  vm_name              = "debian-nomad-client"
  template_description = "Debian 12 - Nomad Client with Docker"

  # ISO - Debian 12 netinstall
  boot_iso {
    iso_url          = "https://cdimage.debian.org/debian-cd/current/amd64/iso-cd/debian-12.8.0-amd64-netinst.iso"
    iso_checksum     = "sha256:0613c564529ba23cd384a0b52b39aa4ac87e68eb3d29c07eb3ba2c09af91adfc"
    iso_storage_pool = var.iso_storage_pool
    unmount          = true
  }

  # Boot command for automated installation
  boot_command = [
    "<esc><wait>",
    "auto url=http://{{ .HTTPIP }}:{{ .HTTPPort }}/preseed.cfg<enter>"
  ]

  # HTTP directory for preseed
  http_directory = "packer/templates/debian/http"
  http_port_min  = 8000
  http_port_max  = 8100

  os = "l26"

  onboot = false

  # Hardware - Clients need more resources for running workloads
  memory   = 8192
  cores    = 4
  sockets  = 1
  cpu_type = "x86-64-v2-AES"

  # Storage - 50GB disk for containers and workloads
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

  # SSH credentials
  ssh_username = "packer"
  ssh_password = "packer"
  ssh_timeout  = "20m"
}

build {
  sources = ["source.proxmox-iso.debian-nomad-client"]

  # Wait for system to be ready
  provisioner "shell" {
    inline = ["echo 'Waiting for system to be ready...' && sleep 10"]
  }

  # Install Docker
  provisioner "shell" {
    environment_vars = [
      "DEBIAN_FRONTEND=noninteractive"
    ]
    inline = [
      "echo '=== Installing Docker ==='",
      "sudo apt-get update",
      "sudo apt-get install -y ca-certificates curl gnupg lsb-release unzip wget",
      "sudo install -m 0755 -d /etc/apt/keyrings",
      "curl -fsSL https://download.docker.com/linux/debian/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg",
      "sudo chmod a+r /etc/apt/keyrings/docker.gpg",
      "echo \"deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/debian $(lsb_release -cs) stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null",
      "sudo apt-get update",
      "sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin",
      "sudo docker --version"
    ]
  }

  # Install Consul
  provisioner "shell" {
    environment_vars = [
      "CONSUL_VERSION=${var.consul_version}"
    ]
    inline = [
      "echo '=== Installing Consul ${var.consul_version} ==='",
      "cd /tmp",
      "wget https://releases.hashicorp.com/consul/$${CONSUL_VERSION}/consul_$${CONSUL_VERSION}_linux_amd64.zip",
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
      "NOMAD_VERSION=${var.nomad_version}"
    ]
    inline = [
      "echo '=== Installing Nomad ${var.nomad_version} ==='",
      "cd /tmp",
      "wget https://releases.hashicorp.com/nomad/$${NOMAD_VERSION}/nomad_$${NOMAD_VERSION}_linux_amd64.zip",
      "unzip nomad_$${NOMAD_VERSION}_linux_amd64.zip",
      "sudo mv nomad /usr/local/bin/",
      "sudo chmod +x /usr/local/bin/nomad",
      "rm nomad_$${NOMAD_VERSION}_linux_amd64.zip",
      "nomad version"
    ]
  }

  # Configure directories and users
  provisioner "shell" {
    inline = [
      "echo '=== Configuring Consul and Nomad ==='",
      "sudo useradd --system --home /etc/consul.d --shell /bin/false consul || true",
      "sudo useradd --system --home /etc/nomad.d --shell /bin/false nomad || true",
      "sudo mkdir -p /etc/consul.d /opt/consul /var/log/consul",
      "sudo mkdir -p /etc/nomad.d /opt/nomad /var/log/nomad",
      "sudo chown -R consul:consul /etc/consul.d /opt/consul /var/log/consul",
      "sudo chown -R nomad:nomad /etc/nomad.d /opt/nomad /var/log/nomad",
      "sudo chmod 755 /etc/consul.d /opt/consul /var/log/consul",
      "sudo chmod 755 /etc/nomad.d /opt/nomad /var/log/nomad"
    ]
  }

  # Clean up
  provisioner "shell" {
    inline = [
      "echo '=== Cleaning up ==='",
      "sudo apt-get clean",
      "sudo rm -rf /tmp/*",
      "sudo cloud-init clean --logs"
    ]
  }
}
