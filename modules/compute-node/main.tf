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
  count        = try(var.vm_config.vm_type, "vm") == "vm" ? 1 : 0
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
      
      has_keepalived = contains(var.keepalived_members, var.vm_config.role)
      is_vrrp_master = endswith(var.vm_config.name, "1")
      local_ip       = split("/", var.vm_config.primary_iface.ip)[0]

      peer_ip = try(split("/", [
        for name, v in var.all_vms : v.primary_iface.ip
        if v.role == var.vm_config.role && v.env == var.vm_config.env && v.name != var.vm_config.name
      ][0])[0], "127.0.0.1")

      peer_ips_csv = join(",", [
        for name, v in var.all_vms : split("/", v.primary_iface.ip)[0]
        if v.role == var.vm_config.role && v.env == var.vm_config.env && v.name != var.vm_config.name
      ])

      cluster_members = {
        for k, v in var.all_vms : k => v
        if v.role == var.vm_config.role && v.env == var.vm_config.env
      }
    })
    file_name = "${var.vm_config.name}-user-data.yaml"
  }
}

# Cloud-Init Network Config (Handles VMs)
resource "proxmox_virtual_environment_file" "network_config" {
  count        = try(var.vm_config.vm_type, "vm") == "vm" ? 1 : 0
  content_type = "snippets"
  datastore_id = var.default_datastore
  node_name    = var.vm_config.node

  source_raw {
    data = <<-EOT
version: 2
ethernets:
%{ for index, iface in var.vm_config.interfaces ~}
  ens${18 + index}:
    optional: true
    addresses:
      - ${iface.ip}
%{ if iface.is_primary ~}
    nameservers:
      addresses: ${jsonencode(var.default_dns)}
      search: [${var.default_domain}]
    routes:
      - to: 0.0.0.0/0
        via: ${var.vm_config.gateway}
%{ endif ~}
%{ endfor ~}
EOT
    file_name = "${var.vm_config.name}-network-config.yaml"
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
    user_data_file_id    = proxmox_virtual_environment_file.user_data[0].id
  }

  lifecycle { ignore_changes = [tags, startup, usb, clone, initialization] }
}

# LXC Container Resource
resource "proxmox_virtual_environment_container" "ct" {
  count         = try(var.vm_config.vm_type, "vm") == "ct" ? 1 : 0
  node_name     = var.vm_config.node
  vm_id         = var.vm_config.vmid
  description   = var.vm_config.desc
  pool_id       = try(var.vm_config.pool, "") != "" ? var.vm_config.pool : null
  start_on_boot = var.vm_config.start_at_node_boot
  started       = var.vm_config.status == "running"
  unprivileged  = true
  
  operating_system {
    template_file_id = "truenas-nfs:vztmpl/${var.vm_config.image}.tar.zst"
    type             = "debian"
  }

  cpu { cores = var.vm_config.cores }
  memory { dedicated = var.vm_config.memory }

  disk {
    datastore_id = var.vm_config.storage
    size         = var.vm_config.disk_size
  }

  dynamic "mount_point" {
    for_each = {
      for key, cfg in var.ceph_mounts : key => cfg
      if strcontains(var.vm_config.name, key)
    }
    content {
      volume = mount_point.value.volume
      path   = mount_point.value.path
      shared = true
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
      servers = var.default_dns
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

  features {
    nesting = contains(try(var.vm_config.lxc_features, []), "nesting")
    keyctl  = contains(try(var.vm_config.lxc_features, []), "keyctl")
    fuse    = contains(try(var.vm_config.lxc_features, []), "fuse")
  }

  lifecycle { ignore_changes = [tags, startup, initialization] }
}

post-processor "shell-local" {
    inline = [
      "ssh root@pve 'qm move_disk ${var.proxmox_vmid} scsi0 truenas-nfs --delete'",
      # Loop over all active nodes so nuc3, site-b, and any others get the template config
      "ssh root@pve 'for node in $(pvesh get /nodes --output-format json | jq -r \".[].node\"); do cp /etc/pve/nodes/pve/qemu-server/${var.proxmox_vmid}.conf /etc/pve/nodes/$node/qemu-server/ 2>/dev/null || true; done'"
    ]
  }