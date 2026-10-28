terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116.0" # Updated to match your installed version
    }
    netbox = {
      source  = "e-breuninger/netbox"
      version = "~> 5.0"
    }
  }
}

# Cloud-Init User Data (Handles VMs)
resource "proxmox_virtual_environment_file" "user_data" {
  content_type = "snippets"
  datastore_id = var.default_datastore
  node_name    = var.vm_config.node

  source_raw {
    data = templatefile("${path.module}/../../templates/user_data.tftpl", {
      username          = var.vm_username
      password          = var.vm_password
      ssh_keys          = split("\n", trimspace(var.vm_config.ssh_keys))
      name              = var.vm_config.name
      vmid              = var.vm_config.vmid
      env               = var.vm_config.env
      use_mirror        = var.vm_config.use_mirror
      mirror_url        = var.mirror_url
      os                = var.vm_config.os
      role              = var.vm_config.role
      node_ip_with_cidr = var.vm_config.primary_iface.ip
      subnet            = cidrsubnet(var.vm_config.primary_iface.ip, 0, 0)
      vm_type           = var.vm_config.vm_type

      extra_packages = lookup(var.role_configs, var.vm_config.role, var.role_configs["Default"]).packages
      extra_files    = lookup(var.role_configs, var.vm_config.role, var.role_configs["Default"]).files
      extra_commands = lookup(var.role_configs, var.vm_config.role, var.role_configs["Default"]).commands
      users          = lookup(var.role_configs, var.vm_config.role, var.role_configs["Default"]).users
      mounts         = lookup(var.role_configs, var.vm_config.role, var.role_configs["Default"]).mounts
      
      # ... (keep your other template variables here)
      has_keepalived = false
      is_vrrp_master = false
      local_ip       = split("/", var.vm_config.primary_iface.ip)[0]
      peer_ip        = "127.0.0.1"
      peer_ips_csv   = ""
      cluster_members = {}
    })
    file_name = "${var.vm_config.name}-user-data.yaml"
  }
}

# VM Resource
resource "proxmox_virtual_environment_vm" "vm" {
  count       = try(var.vm_config.vm_type, "vm") == "vm" ? 1 : 0
  name        = var.vm_config.name
  vm_id       = var.vm_config.vmid
  node_name   = var.vm_config.node
  description = var.vm_config.desc
  pool_id     = var.vm_config.pool != "" ? var.vm_config.pool : null
  on_boot     = var.vm_config.start_at_node_boot
  started     = var.vm_config.status == "running"

  agent { enabled = true }
  cpu { 
    cores = var.vm_config.cores
    sockets = 1
    type = "host" 
}
  memory { dedicated = var.vm_config.memory }
  scsi_hardware = "virtio-scsi-pci"
  serial_device {}

  clone {
    vm_id     = var.vm_config.template_vmid
    node_name = var.vm_config.node
    full      = true
  }

  disk {
    datastore_id = var.vm_config.storage
    size         = max(tonumber(var.vm_config.disk_size), 8)
    interface    = "scsi0"
    file_format  = "raw"
  }

  dynamic "network_device" {
    for_each = var.vm_config.interfaces
    content {
      bridge  = network_device.value.bridge
      vlan_id = network_device.value.vlan > 0 ? network_device.value.vlan : null
    }
  }

  initialization {
    datastore_id         = var.default_datastore
    user_data_file_id    = proxmox_virtual_environment_file.user_data.id
  }

  lifecycle { ignore_changes = [tags, startup, usb, clone, initialization] }
}

# LXC Container Resource
resource "proxmox_virtual_environment_container" "ct" {
  count         = try(var.vm_config.vm_type, "") == "ct" ? 1 : 0
  node_name     = var.vm_config.node
  vm_id         = var.vm_config.vmid
  description   = var.vm_config.desc
  pool_id       = var.vm_config.pool != "" ? var.vm_config.pool : null
  start_on_boot = var.vm_config.start_at_node_boot
  started       = var.vm_config.status == "running"
  unprivileged  = true

  operating_system {
    template_file_id = "${var.vm_config.storage}:vztmpl/${var.vm_config.image}.tar.zst"
    type             = "debian"
  }

  cpu { cores = var.vm_config.cores }
  memory { dedicated = var.vm_config.memory }

  disk {
    datastore_id = var.vm_config.storage
    size         = var.vm_config.disk_size
  }

  # ADD THIS DYNAMIC MOUNT POINT BLOCK BACK
  dynamic "mount_point" {
    for_each = lookup(var.ceph_mounts, var.vm_config.name, {}) != {} ? [var.ceph_mounts[var.vm_config.name]] : []
    content {
      volume    = mount_point.value.volume
      path      = mount_point.value.path
      shared    = true
      replicate = true
    }
  }

  initialization {
    hostname = var.vm_config.name
    ip_config {
      ipv4 {
        address = var.vm_config.primary_iface.ip
        gateway = var.vm_config.gateway
      }
    }
    dns {
      servers = [var.default_dns]
      domain  = var.default_domain
    }
  }

  dynamic "network_interface" {
    for_each = var.vm_config.interfaces
    content {
      name    = network_interface.key == 0 ? "ens18" : "veth${network_interface.key}"      
      bridge  = network_interface.value.bridge
      vlan_id = network_interface.value.vlan > 0 ? network_interface.value.vlan : null
    }
  }

  lifecycle { ignore_changes = [tags, startup, initialization] }
}