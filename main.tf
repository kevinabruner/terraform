terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "3.0.2-rc07"
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
    Accept = "application/json"
  }
}


provider "proxmox" {  
  pm_api_url = "${var.proxmox_api_url}"    
  pm_api_token_id = "${var.proxmox_api_token_id}"    
  pm_api_token_secret = "${var.proxmox_api_token_secret}"
  pm_tls_insecure = false
  pm_parallel = 3
}


locals {
  vms = jsondecode(data.http.netbox_export.response_body)
  vm_configs = {
    for vm in local.vms : vm.name => merge(vm, {

      # Find the specific interface object where is_primary is true
      primary_iface = [for i in vm.interfaces : i if i.is_primary][0]

      # Find all interfaces that are NOT primary
      secondary_ifaces = [for i in vm.interfaces : i if !i.is_primary]
      
      # Use that found object generate a gateway address (192.168.xx + .1)
      gateway = "${join(".", slice(split(".", [for i in vm.interfaces : i.ip if i.is_primary][0]), 0, 3))}.1"

    }) if vm.name != ""
  }
}

resource "proxmox_cloud_init_disk" "ci_configs" {
  for_each = local.vm_configs

  name     = "${each.value.name}-ci"
  pve_node = each.value.node
  storage  = "cephfs"

  meta_data = <<-EOT
    instance-id: ${sha1(each.value.name)}-v4
    local-hostname: ${each.value.name}
  EOT

  user_data = <<-EOT
  #cloud-config
  write_files:
    - path: /etc/environment
      content: |
        NETBOX_ID=${each.value.vmid}
        VM_NAME=${each.value.name}
      append: true

  users:
    - name: ${var.vm_username}
      sudo: ALL=(ALL) NOPASSWD:ALL
      shell: /bin/bash
      ssh_authorized_keys:
%{ for key in split("\n", trimspace(each.value.ssh_keys)) ~}
        - ${trimspace(key)}
%{ endfor ~}
  EOT

  # Using a cleaner YAML format without unnecessary quotes
  network_config = <<EOT
version: 1
config:
  - type: physical
    name: eth0
    subnets:
      - type: static
        address: ${each.value.primary_iface.ip}
        gateway: ${each.value.gateway}
        dns_nameservers:
          - 1.1.1.1
          - 8.8.8.8
EOT
}

resource "proxmox_vm_qemu" "proxmox_vms" {
  for_each = local.vm_configs

  name               = each.value.name
  vmid               = each.value.vmid
  target_node        = each.value.node
  description        = each.value.desc
  pool               = each.value.pool != "" ? each.value.pool : null
  start_at_node_boot = each.value.start_at_node_boot
  agent              = 1
  memory             = each.value.memory
  clone              = each.value.image   # This comes from your NetBox "image" field
  full_clone         = true
  os_type            = "ubuntu"
  scsihw             = "virtio-scsi-pci"
  boot               = "order=scsi0;ide3"
  vm_state           = each.value.status

  cpu {
    cores   = each.value.cores
    sockets = 1
    type    = "host"
  }

  dynamic "network" {
    for_each = each.value.interfaces
    content {
      id     = network.key
      model  = "virtio"
      bridge = network.value.name 
      tag    = network.value.vlan > 0 ? network.value.vlan : null
    }
  }

  disks {
    scsi {
      scsi0 {
        disk {
          storage   = each.value.storage
          size      = each.value.disk_size
          replicate = true
          format    = "raw"
        }
      }
    }
    ide {      
      ide2 { 
        cdrom { 
          passthrough = false 
        } 
      }      
      ide3 { 
        cdrom {
          iso = proxmox_cloud_init_disk.ci_configs[each.key].id
        }
      }
    }
  }

  serial { 
    id   = 0 
    type = "socket" 
  }


 

lifecycle {
    ignore_changes = [
      qemu_os, 
      hagroup, 
      hastate,            
      agent, 
      usbs, 
      tags, 
      startup_shutdown,
      clone,
      full_clone,  
    ]
  } 
}

