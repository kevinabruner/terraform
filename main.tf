terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "3.0.2-rc07"
    }
    netbox = {
      source  = "e-breuninger/netbox"
      version = "~> 5.0" # Or current version
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
  pm_api_url = "https://pve.thejfk.ca/api2/json"    
  pm_api_token_id = "terraform@pam!main_terraform"    
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure = false
  pm_parallel = 3
}


locals {
  # This will now work because NetBox is sending valid JSON
  vms = jsondecode(data.http.netbox_export.response_body)
}


resource "proxmox_vm_qemu" "proxmox_vms" {
  for_each = { for vm in local.vms : vm.name => vm if vm.name != "" }

  name        = each.value.name
  vmid        = each.value.vmid
  target_node = each.value.node
  description = each.value.desc
  pool        = each.value.pool != "" ? each.value.pool : null
  
  agent    = 1
  memory   = each.value.memory
  clone       = each.value.image   # This comes from your NetBox "image" field
  full_clone  = true
  os_type     = "ubuntu"
  scsihw   = "virtio-scsi-pci"
  boot     = "order=scsi0;ide3"

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

  # Networking
  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
    tag    = each.value.vlan != 0 ? each.value.vlan : null
  }

  ipconfig0 = each.value.ip0

  # Fast IP Logic
  dynamic "network" {
    for_each = each.value.fast_ip != "" ? [1] : []
    content {
      id     = 1
      model  = "virtio"
      bridge = "vmbr3"
    }
  }
  ipconfig1 = each.value.fast_ip != "" ? "ip=${each.value.fast_ip}" : null

  # Standardized user data
  ciuser     = var.vm_username
  cipassword = var.vm_password
  sshkeys = each.value.ssh_keys

  lifecycle {
    ignore_changes = [
      qemu_os, 
      start_at_node_boot, 
      hagroup, 
      hastate,      
      vm_state, 
      agent, 
      usbs, 
      tags, 
      network, 
      startup_shutdown,
      clone,
      full_clone, 
      ipconfig1
    ]
  }
}

