# Nomad Server Cluster Module
# Deploys a multi-node Nomad server cluster

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.88"
    }
  }
}

locals {
  server_ips = [for i in range(var.server_count) :
    "${cidrhost(var.network_cidr, var.ip_start_offset + i)}/24"
  ]

  server_names = [for i in range(var.server_count) :
    "${var.name_prefix}-${i + 1}"
  ]

  # Round-robin across ProxMox nodes
  proxmox_nodes = length(var.proxmox_nodes) > 0 ? var.proxmox_nodes : [var.proxmox_node]
  server_nodes = [for i in range(var.server_count) :
    local.proxmox_nodes[i % length(local.proxmox_nodes)]
  ]

  # Template IDs per node (use same template if only one provided)
  template_ids = length(var.template_ids) > 0 ? var.template_ids : [var.template_name]
  server_templates = [for i in range(var.server_count) :
    local.template_ids[i % length(local.template_ids)]
  ]

  # Generate retry_join addresses for Consul
  consul_retry_join = [for ip in local.server_ips :
    split("/", ip)[0]
  ]
}

# Deploy Nomad server VMs
module "nomad_servers" {
  source = "../proxmox-vm"

  count = var.server_count

  vm_name       = local.server_names[count.index]
  proxmox_node  = local.server_nodes[count.index]
  template_name = local.server_templates[count.index]

  cores     = var.cores
  memory    = var.memory
  disk_size = var.disk_size

  storage_pool   = var.storage_pool
  vm_storage_pool = var.vm_storage_pool
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag

  ip_address  = local.server_ips[count.index]
  gateway     = var.gateway
  dns_servers = var.dns_servers

  ssh_keys        = var.ssh_keys
  ssh_private_key = var.ssh_private_key

  consul_config = templatefile("${path.module}/templates/consul-server.hcl", {
    datacenter        = var.datacenter
    server_count      = var.server_count
    consul_retry_join = jsonencode(local.consul_retry_join)
  })

  nomad_config = templatefile("${path.module}/templates/nomad-server.hcl", {
    datacenter        = var.datacenter
    region            = var.region
    server_count      = var.server_count
    consul_retry_join = jsonencode(local.consul_retry_join)
  })

  cloud_init_user_data = "" # Not used anymore

  proxmox_ssh_user = var.proxmox_ssh_user
  proxmox_host_ip  = var.proxmox_host_ip

  environment = var.environment
  role        = "nomad-server"
  additional_tags = concat(
    ["consul-server", "vault-server"],
    var.additional_tags
  )
}

# Wait for servers to be ready
resource "null_resource" "wait_for_servers" {
  count = var.server_count

  depends_on = [module.nomad_servers]

  provisioner "local-exec" {
    command = <<-EOT
      echo "Waiting for server ${count.index + 1} at ${split("/", local.server_ips[count.index])[0]} to be ready..."
      timeout 300 bash -c 'until nc -z ${split("/", local.server_ips[count.index])[0]} 22; do sleep 2; done'
      echo "Server ${count.index + 1} is ready!"
    EOT
  }
}

# Bootstrap Consul cluster (only on first server)
resource "null_resource" "bootstrap_consul" {
  count = var.auto_bootstrap ? 1 : 0

  depends_on = [null_resource.wait_for_servers]

  provisioner "remote-exec" {
    inline = [
      "sudo systemctl enable consul",
      "sudo systemctl start consul",
      "sleep 10",
      "consul members"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = split("/", local.server_ips[0])[0]
      private_key = var.ssh_private_key
    }
  }
}

# Bootstrap Nomad cluster (only on first server)
resource "null_resource" "bootstrap_nomad" {
  count = var.auto_bootstrap ? 1 : 0

  depends_on = [null_resource.bootstrap_consul]

  provisioner "remote-exec" {
    inline = [
      "sudo systemctl enable nomad",
      "sudo systemctl start nomad",
      "sleep 10",
      "nomad server members"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = split("/", local.server_ips[0])[0]
      private_key = var.ssh_private_key
    }
  }
}
