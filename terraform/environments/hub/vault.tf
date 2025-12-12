locals {
  # Round-robin distribution across ProxMox nodes
  vault_nodes = [for i in range(var.vault_cluster_size) :
    var.proxmox_nodes[i % length(var.proxmox_nodes)]
  ]

  # Template IDs per node (round-robin)
  vault_templates = [for i in range(var.vault_cluster_size) :
    var.vault_template_ids[i % length(var.vault_template_ids)]
  ]
}

module "vault_servers" {
  source = "../../modules/proxmox-vm"
  count  = var.vault_cluster_size

  vm_name         = "hub-vault-${count.index + 1}"
  template_name   = local.vault_templates[count.index]
  proxmox_node    = local.vault_nodes[count.index]
  vm_storage_pool = var.vault_vm_config.storage_pool
  role            = "vault"
  
  cores     = var.vault_vm_config.cores
  memory    = var.vault_vm_config.memory
  disk_size = "${var.vault_vm_config.disk_size}G"
  
  ip_address = "10.0.0.${var.vault_vm_config.ip_start + count.index}/24"
  gateway    = "10.0.0.1"
  ssh_keys   = var.ssh_public_key
}