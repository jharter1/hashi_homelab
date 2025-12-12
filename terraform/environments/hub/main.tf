terraform {
  required_version = ">= 1.0"
  
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.50"
    }
  }

  backend "local" {
    path = "terraform-hub.tfstate"
  }
}

provider "proxmox" {
  endpoint = var.proxmox_host
  username = var.proxmox_username
  password = var.proxmox_password
  insecure = true

  ssh {
    agent = true
  }
}

# Data source for the Debian server template
data "proxmox_virtual_environment_vms" "debian_server_template" {
  filter {
    name   = "name"
    values = ["debian-12-nomad-server-template"]
  }
}