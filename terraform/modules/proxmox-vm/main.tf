# ProxMox VM Module
# Reusable module for provisioning VMs from Packer templates

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.50"
    }
  }
}

resource "proxmox_virtual_environment_vm" "vm" {
  name        = var.vm_name
  node_name   = var.proxmox_node
  description = "Managed by Terraform"
  tags        = concat([var.environment, var.role], var.additional_tags)
  
  on_boot = var.onboot
  started = true  # Ensure VM starts after creation
  
  clone {
    vm_id = can(tonumber(var.template_name)) ? tonumber(var.template_name) : 9000
    full  = true
  }
  
  cpu {
    cores   = var.cores
    sockets = var.sockets
  }
  
  memory {
    dedicated = var.memory
  }
  
  agent {
    enabled = true
  }
  
  network_device {
    bridge  = var.network_bridge
    vlan_id = var.vlan_tag != 0 ? var.vlan_tag : null
  }
  
  initialization {
    datastore_id = var.storage_pool
    
    ip_config {
      ipv4 {
        address = var.ip_address
        gateway = var.gateway
      }
    }
    
    dns {
      servers = var.dns_servers
    }
    
    user_account {
      username = "ubuntu"
      password = "ubuntu"  # Change this after first login
      keys     = var.ssh_keys != "" ? [var.ssh_keys] : []
    }
  }
  
  lifecycle {
    ignore_changes = [
      network_device,
    ]
  }
}

# Apply configuration files via SSH after VM is ready
resource "null_resource" "cloud_init_config" {
  count = var.consul_config != "" && var.nomad_config != "" ? 1 : 0

  depends_on = [proxmox_virtual_environment_vm.vm]

  triggers = {
    vm_id = proxmox_virtual_environment_vm.vm.id
    consul_config = var.consul_config
    nomad_config = var.nomad_config
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = split("/", var.ip_address)[0]
    private_key = var.ssh_private_key
    timeout     = "5m"
  }

  provisioner "file" {
    content     = var.consul_config
    destination = "/tmp/consul-config.hcl"
  }

  provisioner "file" {
    content     = var.nomad_config
    destination = "/tmp/nomad-config.hcl"
  }

  provisioner "remote-exec" {
    inline = [
      "cloud-init status --wait || true",
      "echo 'Installing configuration files...'",
      "sudo mv /tmp/consul-config.hcl /etc/consul.d/$(echo '${var.consul_config}' | grep -q 'server = true' && echo 'server.hcl' || echo 'client.hcl')",
      "sudo chown consul:consul /etc/consul.d/*.hcl",
      "sudo chmod 640 /etc/consul.d/*.hcl",
      "sudo mv /tmp/nomad-config.hcl /etc/nomad.d/$(echo '${var.nomad_config}' | grep -q 'server {' && echo 'server.hcl' || echo 'client.hcl')",
      "sudo chown nomad:nomad /etc/nomad.d/*.hcl",
      "sudo chmod 640 /etc/nomad.d/*.hcl",
      "echo 'Starting services in background...'",
      "(sudo systemctl restart consul && sleep 2 && sudo systemctl restart nomad &)",
      "echo 'Configuration complete'"
    ]
  }
}
