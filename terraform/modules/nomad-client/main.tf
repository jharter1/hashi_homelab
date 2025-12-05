# Nomad Client Module
# Deploys Nomad client nodes

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
  client_ips = [for i in range(var.client_count) :
    "${cidrhost(var.network_cidr, var.ip_start_offset + i)}/24"
  ]

  client_names = [for i in range(var.client_count) :
    "${var.name_prefix}-${i + 1}"
  ]

  # Round-robin across ProxMox nodes
  proxmox_nodes = length(var.proxmox_nodes) > 0 ? var.proxmox_nodes : [var.proxmox_node]
  client_nodes = [for i in range(var.client_count) :
    local.proxmox_nodes[i % length(local.proxmox_nodes)]
  ]

  # Template IDs per node (use same template if only one provided)
  template_ids = length(var.template_ids) > 0 ? var.template_ids : [var.template_name]
  client_templates = [for i in range(var.client_count) :
    local.template_ids[i % length(local.template_ids)]
  ]
}

# Deploy Nomad client VMs
module "nomad_clients" {
  source = "../proxmox-vm"

  count = var.client_count

  vm_name       = local.client_names[count.index]
  proxmox_node  = local.client_nodes[count.index]
  template_name = local.client_templates[count.index]

  cores     = var.cores
  memory    = var.memory
  disk_size = var.disk_size

  storage_pool   = var.storage_pool
  vm_storage_pool = var.vm_storage_pool
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag

  ip_address  = local.client_ips[count.index]
  gateway     = var.gateway
  dns_servers = var.dns_servers

  ssh_keys        = var.ssh_keys
  ssh_private_key = var.ssh_private_key

  consul_config = templatefile("${path.module}/templates/consul-client.hcl", {
    datacenter       = var.datacenter
    server_addresses = jsonencode(var.server_addresses)
    bind_addr        = split("/", local.client_ips[count.index])[0]
  })

  nomad_config = templatefile("${path.module}/templates/nomad-client.hcl", {
    datacenter       = var.datacenter
    region           = var.region
    node_class       = var.node_class
    server_addresses = jsonencode(var.server_addresses)
  })

  cloud_init_user_data = "" # Not used anymore

  proxmox_ssh_user = var.proxmox_ssh_user
  proxmox_host_ip  = var.proxmox_host_ip

  environment = var.environment
  role        = "nomad-client"
  additional_tags = concat(
    ["consul-client", "docker"],
    var.additional_tags
  )
}

# Wait for clients to be ready
resource "null_resource" "wait_for_clients" {
  count = var.client_count

  depends_on = [module.nomad_clients]

  provisioner "local-exec" {
    command = <<-EOT
      timeout 120 bash -c 'until nc -z ${split("/", local.client_ips[count.index])[0]} 22; do sleep 2; done'
    EOT
  }
}

# Start services on clients
resource "null_resource" "start_services" {
  count = var.auto_start_services ? var.client_count : 0

  depends_on = [null_resource.wait_for_clients]

  provisioner "remote-exec" {
    inline = [
      "sudo systemctl enable docker",
      "sudo systemctl start docker",
      "sudo systemctl enable consul",
      "sudo systemctl start consul",
      "sleep 5",
      "sudo systemctl enable nomad",
      "sudo systemctl start nomad",
      "sleep 10",
      "nomad node status"
    ]

    connection {
      type        = "ssh"
      user        = "ubuntu"
      host        = split("/", local.client_ips[count.index])[0]
      private_key = var.ssh_private_key
    }
  }
}
