# Development Environment Configuration
# Deploys a complete HashiCorp cluster for development

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.88"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 4.5"
    }
    null = {
      source = "hashicorp/null"
    }
  }

  # Local backend (default) - state stored in terraform.tfstate
  # To use Terraform Cloud, uncomment the cloud block below and run: terraform login
  # cloud {
  #   organization = "pve_homelab_cloud"
  # 
  #   workspaces {
  #     name = "hashi-homelab"
  #   }
  # }
}

# ProxMox provider configuration (bpg)
provider "proxmox" {
  endpoint = var.proxmox_host
  username = var.proxmox_username
  password = var.proxmox_password
  insecure = var.proxmox_tls_insecure

  ssh {
    agent = true
  }
}

# Deploy Nomad server cluster
module "nomad_servers" {
  source = "../../modules/nomad-server"

  server_count = var.nomad_server_count
  name_prefix  = "${var.environment}-nomad-server"

  proxmox_nodes = var.proxmox_nodes
  template_name = var.nomad_server_template_name
  template_ids  = var.nomad_server_template_ids

  cores     = var.nomad_server_cores
  memory    = var.nomad_server_memory
  disk_size = var.nomad_server_disk_size

  storage_pool   = var.storage_pool
  vm_storage_pool = var.vm_storage_pool
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag

  network_cidr    = var.network_cidr
  ip_start_offset = var.nomad_server_ip_start
  gateway         = var.network_gateway
  dns_servers     = var.dns_servers

  ssh_keys        = var.ssh_public_keys
  ssh_private_key = var.ssh_private_key != "" ? file(var.ssh_private_key) : ""

  proxmox_ssh_user = var.proxmox_ssh_user
  proxmox_host_ip  = var.proxmox_host_ip

  datacenter = var.datacenter
  region     = var.region

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  vault_version  = var.vault_version

  environment     = var.environment
  auto_bootstrap  = var.auto_bootstrap
  additional_tags = var.additional_tags
}

# Deploy Nomad client nodes
module "nomad_clients" {
  source = "../../modules/nomad-client"

  # Note: Removed depends_on to allow parallel creation with servers
  # Clients only need server IP addresses (variables), not running servers

  client_count = var.nomad_client_count
  name_prefix  = "${var.environment}-nomad-client"

  proxmox_nodes = var.proxmox_nodes
  template_name = var.nomad_client_template_name
  template_ids  = var.nomad_client_template_ids
  

  cores     = var.nomad_client_cores
  memory    = var.nomad_client_memory
  disk_size = var.nomad_client_disk_size

  storage_pool   = var.storage_pool
  vm_storage_pool = var.vm_storage_pool
  network_bridge = var.network_bridge
  vlan_tag       = var.vlan_tag

  network_cidr    = var.network_cidr
  ip_start_offset = var.nomad_client_ip_start
  gateway         = var.network_gateway
  dns_servers     = var.dns_servers

  ssh_keys        = var.ssh_public_keys
  ssh_private_key = var.ssh_private_key != "" ? file(var.ssh_private_key) : ""

  proxmox_ssh_user = var.proxmox_ssh_user
  proxmox_host_ip  = var.proxmox_host_ip

  server_addresses = module.nomad_servers.server_ips

  datacenter = var.datacenter
  region     = var.region
  node_class = var.nomad_client_node_class

  consul_version = var.consul_version
  nomad_version  = var.nomad_version
  docker_version = var.docker_version

  environment         = var.environment
  auto_start_services = var.auto_start_services
  additional_tags     = var.additional_tags
}
