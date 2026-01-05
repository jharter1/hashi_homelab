# ProxMox VM Module
# Reusable module for provisioning VMs from Packer templates

terraform {
  required_version = ">= 1.5.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.88"
    }
  }
}

# Convert disk size string (e.g., "50G") to a whole number of Gigabytes (GB)
locals {
  disk_num  = tonumber(regex("^([0-9]+)", var.disk_size)[0])
  disk_unit = upper(regex("[^0-9]+$", var.disk_size)) # Extracts "G" or "M"

  # Calculate size in GB. If the input is in M, divide the number by 1024.
  disk_size_gb = (
    local.disk_unit == "G" ? local.disk_num :
    local.disk_unit == "M" ? floor(local.disk_num / 1024) :
    floor(local.disk_num / 1073741824) # Default to bytes if no suffix, unlikely but safe
  )
}

resource "proxmox_virtual_environment_vm" "vm" {
  name        = var.vm_name
  node_name   = var.proxmox_node
  description = "Managed by Terraform"
  tags        = concat([var.environment, var.role], var.additional_tags)

  on_boot = var.onboot
  started = true # Ensure VM starts after creation

  clone {
    vm_id = can(tonumber(var.template_name)) ? tonumber(var.template_name) : 9000
    full  = true  # Full clone required when cloning from NAS-SharedStorage
  }

  disk {
    interface    = "scsi0"
    datastore_id = var.vm_storage_pool != "" ? var.vm_storage_pool : var.storage_pool
    size         = local.disk_size_gb
  }

  # Note: Disk sizing is handled by Proxmox during clone from template
  # Adding a disk block here causes issues with existing VMs

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
      password = "ubuntu" # Change this after first login
      keys     = var.ssh_keys != "" ? [var.ssh_keys] : []
    }
  }

  # Optimized timeouts based on observed VM creation times (25-60s)
  # Previous defaults of 300s were far too conservative
  # Update: Increased timeouts to handle network latency and full clones
  timeout_clone       = 600 # 10 min for clone (was 90s)
  timeout_create      = 300 # 5 min for VM creation (was 180s)
  timeout_start_vm    = 300 # 5 min to start VM and wait for agent (was 60s)
  timeout_shutdown_vm = 300 # 5 min for graceful shutdown (was 120s)

  lifecycle {
    ignore_changes = [
      network_device,
      initialization[0].datastore_id, # Ignore cloud-init storage changes (per-node differences)
      network_device[0].mac_address,  # MAC addresses assigned by Proxmox
    ]
  }
}

# Wait for SSH to be available
resource "null_resource" "wait_for_ssh" {
  depends_on = [proxmox_virtual_environment_vm.vm]

  triggers = {
    vm_id = proxmox_virtual_environment_vm.vm.id
  }

  provisioner "local-exec" {
    command = "timeout 300 bash -c 'until nc -z -w 5 ${split("/", var.ip_address)[0]} 22; do sleep 5; done'"
  }
}

# Apply configuration files via SSH after VM is ready
resource "null_resource" "cloud_init_config" {
  count = var.consul_config != "" && var.nomad_config != "" ? 1 : 0

  depends_on = [null_resource.wait_for_ssh]

  triggers = {
    vm_id         = proxmox_virtual_environment_vm.vm.id
    consul_config = var.consul_config
    nomad_config  = var.nomad_config
    script_hash   = sha256(templatefile("${path.module}/templates/configure-vm.sh.tftpl", { role = var.role }))
  }

  connection {
    type        = "ssh"
    user        = "ubuntu"
    host        = split("/", var.ip_address)[0]
    private_key = var.ssh_private_key
    timeout     = "2m"
  }

  # Upload configuration script
  provisioner "file" {
    content = templatefile("${path.module}/templates/configure-vm.sh.tftpl", {
      role = var.role
    })
    destination = "/tmp/configure-vm.sh"
  }

  # Upload Consul config
  provisioner "file" {
    content     = var.consul_config
    destination = "/tmp/consul.hcl"
  }

  # Upload Nomad config
  provisioner "file" {
    content     = var.nomad_config
    destination = "/tmp/nomad.hcl"
  }

  # Execute configuration script
  provisioner "remote-exec" {
    inline = [
      "chmod +x /tmp/configure-vm.sh",
      "/tmp/configure-vm.sh"
    ]
  }
}
