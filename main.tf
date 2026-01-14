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
  url = "${var.netbox_export_url}"

  request_headers = {
    Authorization = "Token ${var.netbox_api_token_secret}"
    Accept = "application/json"
  }
}


provider "proxmox" {  
  pm_api_url = "https://pve.thejfk.ca/api2/json"    
  pm_api_token_id = "terraform@pam!main_terraform"    
  pm_api_token_secret = var.proxmox_api_token_secret
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
        cloudinit { 
          storage = each.value.storage 
        } 
      }
    }
  }

  serial { 
    id   = 0 
    type = "socket" 
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

  # Always uses the Netbox primary ipv4 interface
  ipconfig0 = "ip=${each.value.primary_iface.ip},gw=${each.value.gateway}"

  # Grabs the IP of the first few non-primary interfaces, if any (this can't be a loop, I'm sorry)
  ipconfig1 = length(each.value.secondary_ifaces) > 0 ? "ip=${each.value.secondary_ifaces[0].ip}" : null
  ipconfig2 = length(each.value.secondary_ifaces) > 1 ? "ip=${each.value.secondary_ifaces[1].ip}" : null
  ipconfig3 = length(each.value.secondary_ifaces) > 2 ? "ip=${each.value.secondary_ifaces[2].ip}" : null


  # Standardized user data
  ciuser     = var.vm_username
  cipassword = var.vm_password
  sshkeys = each.value.ssh_keys

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

