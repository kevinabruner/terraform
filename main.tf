terraform {
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.60"
    }
    netbox = {
      source  = "e-breuninger/netbox"
      version = "~> 5.0"
    }
  }
}

data "http" "netbox_export" {
  url = "https://netbox.thejfk.ca/api/virtualization/virtual-machines/?export=Main+terraform+templates"
  request_headers = {
    Authorization = "Token ${var.netbox_api_token_secret}"
    Accept        = "application/json"
  }
}

provider "proxmox" {
  endpoint  = var.proxmox_api_url
  #api_token = "${var.proxmox_api_token_id}=${var.proxmox_api_token_secret}"
  username = "root@pam"
  password = var.vm_password
  insecure  = false

  ssh {
    agent       = true
    username    = "root"
    private_key = file("~/.ssh/id_rsa")
  }
}

locals {
  vms = jsondecode(data.http.netbox_export.response_body)

  role_configs = {
    for f in fileset("${path.module}/roles", "*.yaml") :
    yamldecode(file("${path.module}/roles/${f}")).name => yamldecode(file("${path.module}/roles/${f}"))
  }

  vm_configs = {
    for vm in local.vms : vm.name => merge(vm, {
      primary_iface = [for i in vm.interfaces : i if i.is_primary][0]
      gateway       = "${join(".", slice(split(".", [for i in vm.interfaces : i.ip if i.is_primary][0]), 0, 3))}.1"
    }) if vm.name != ""
  }
}

# ------------------------------------------------------------------------------
# CLOUD-INIT SNIPPETS (VMs ONLY)
# Uploaded to "truenas-nfs" storage (must support the "snippets" content type)
# ------------------------------------------------------------------------------

resource "proxmox_virtual_environment_file" "user_data" {
  for_each     = { for k, v in local.vm_configs : k => v if try(v.vm_type, "vm") == "vm" }
  content_type = "snippets"
  datastore_id = "truenas-nfs"
  node_name    = each.value.node

  source_raw {
    data = templatefile("${path.module}/templates/user_data.tftpl", {
      username          = var.vm_username
      password          = var.vm_password
      ssh_keys          = split("\n", trimspace(each.value.ssh_keys))
      name              = each.value.name
      vmid              = each.value.vmid
      env               = each.value.env
      use_mirror        = each.value.use_mirror
      mirror_url        = var.mirror_url
      os                = each.value.os
      role              = each.value.role
      node_ip_with_cidr = each.value.primary_iface.ip
      subnet            = cidrsubnet(each.value.primary_iface.ip, 0, 0)
      vm_type           = each.value.vm_type

      etcd_content = templatefile("${path.module}/templates/_etcd.tftpl", {
        name     = each.value.name
        local_ip = split("/", each.value.primary_iface.ip)[0]
        cluster_members = {
          for k, v in local.vm_configs : k => v
          if v.role == each.value.role && v.env == each.value.env
        }
      })

      patroni_content = templatefile("${path.module}/templates/_patroni.yml.tftpl", {
        name     = each.value.name
        local_ip = split("/", each.value.primary_iface.ip)[0]
        subnet   = cidrsubnet(each.value.primary_iface.ip, 0, 0)
        cluster_members = {
          for k, v in local.vm_configs : k => v
          if v.role == each.value.role && v.env == each.value.env
        }
        password = "87Josie*"
      })

      extra_packages = lookup(local.role_configs, each.value.role, local.role_configs["Default"]).packages
      extra_files    = lookup(local.role_configs, each.value.role, local.role_configs["Default"]).files
      extra_commands = lookup(local.role_configs, each.value.role, local.role_configs["Default"]).commands
      users          = lookup(local.role_configs, each.value.role, local.role_configs["Default"]).users
      mounts         = lookup(local.role_configs, each.value.role, local.role_configs["Default"]).mounts

      has_keepalived = contains(var.keepalived_members, each.value.role)
      is_vrrp_master = endswith(each.value.name, "1")
      local_ip       = split("/", each.value.primary_iface.ip)[0]

      peer_ip = try(split("/", [
        for name, v in local.vm_configs : v.primary_iface.ip
        if v.role == each.value.role && v.env == each.value.env && v.name != each.value.name
      ][0])[0], "127.0.0.1")

      peer_ips_csv = join(",", [
        for name, v in local.vm_configs : split("/", v.primary_iface.ip)[0]
        if v.role == each.value.role && v.env == each.value.env && v.name != each.value.name
      ])

      cluster_members = {
        for k, v in local.vm_configs : k => v
        if v.role == each.value.role && v.env == each.value.env
      }
    })
    file_name = "${each.value.name}-user-data.yaml"
  }
}

resource "proxmox_virtual_environment_file" "network_config" {
  for_each     = { for k, v in local.vm_configs : k => v if try(v.vm_type, "vm") == "vm" }
  content_type = "snippets"
  datastore_id = "truenas-nfs"
  node_name    = each.value.node

  source_raw {
    data = <<-EOT
version: 2
ethernets:
%{ for index, iface in each.value.interfaces ~}
  ens${18 + index}:
    optional: true
    addresses:
      - ${iface.ip}
%{ if iface.is_primary ~}
    nameservers:
      addresses: [192.168.11.99]
      search: [jfkhome]
    routes:
      - to: 0.0.0.0/0
        via: ${each.value.gateway}
%{ endif ~}
%{ endfor ~}
EOT
    file_name = "${each.value.name}-network-config.yaml"
  }
}

# ------------------------------------------------------------------------------
# VIRTUAL MACHINE RESOURCE (vm_type = "vm")
# ------------------------------------------------------------------------------

resource "proxmox_virtual_environment_vm" "proxmox_vms" {
  for_each    = { for k, v in local.vm_configs : k => v if try(v.vm_type, "vm") == "vm" }
  name        = each.value.name
  vm_id       = each.value.vmid
  node_name   = each.value.node
  description = each.value.desc
  pool_id     = each.value.pool != "" ? each.value.pool : null
  on_boot     = each.value.start_at_node_boot
  started     = each.value.status == "running"

  agent {
    enabled = true
  }

  cpu {
    cores   = each.value.cores
    sockets = 1
    type    = "host"
  }

  memory {
    dedicated = each.value.memory
  }

  scsi_hardware = "virtio-scsi-pci"

  serial_device {}

clone {
    vm_id     = each.value.template_vmid
    node_name = "pve"
    full      = true
  }

  disk {
    datastore_id = each.value.storage
    size         = each.value.disk_size
    interface    = "scsi0"
    file_format  = "raw"
  }

  dynamic "network_device" {
    for_each = each.value.interfaces
    content {
      bridge  = network_device.value.bridge
      vlan_id = network_device.value.vlan > 0 ? network_device.value.vlan : null
    }
  }

  initialization {
    datastore_id         = "truenas-nfs"
    user_data_file_id    = proxmox_virtual_environment_file.user_data[each.key].id
    network_data_file_id = proxmox_virtual_environment_file.network_config[each.key].id
  }

  timeout_create = 900
  timeout_clone  = 900

  lifecycle {
    ignore_changes = [
      tags,
      startup,
      usb,
      clone,
      initialization,
    ]
  }
}

# ------------------------------------------------------------------------------
# LXC CONTAINER RESOURCE (vm_type = "ct")
# ------------------------------------------------------------------------------

resource "proxmox_virtual_environment_container" "proxmox_cts" {
  for_each      = { for k, v in local.vm_configs : k => v if try(v.vm_type, "") == "ct" }
  node_name     = each.value.node
  vm_id         = each.value.vmid
  description   = each.value.desc
  pool_id       = each.value.pool != "" ? each.value.pool : null
  start_on_boot = each.value.start_at_node_boot
  started       = each.value.status == "running"
  unprivileged  = true

  # Deploy directly from custom OS tarball on shared NFS
  operating_system {
    template_file_id = "truenas-nfs:vztmpl/${each.value.image}.tar.zst"
    type             = "debian"
  }

  cpu {
    cores = each.value.cores
  }

  memory {
    dedicated = each.value.memory
  }

  disk {
    datastore_id = each.value.storage   # Target local storage (e.g., local-lvm)
    size         = each.value.disk_size # Creates rootfs at full target size directly
  }

  initialization {
    hostname = each.value.name

    ip_config {
      ipv4 {
        address = each.value.primary_iface.ip
        gateway = each.value.gateway
      }
    }

    dns {
      servers = ["192.168.11.99"]
      domain  = "jfkhome"
    }
  }

  dynamic "network_interface" {
    for_each = each.value.interfaces
    content {
      name    = network_interface.key == 0 ? "ens18" : "veth${network_interface.key}"      
      bridge  = network_interface.value.bridge
      vlan_id = network_interface.value.vlan > 0 ? network_interface.value.vlan : null
    }
  }

  features {
    nesting = true
  }

  lifecycle {
    ignore_changes = [
      tags,
      startup,
      initialization,
    ]
  }
}