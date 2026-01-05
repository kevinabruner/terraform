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
  url = "http://netbox.thejfk.ca/api/virtualization/virtual-machines/?export=Main+terraform+templates"

  request_headers = {
    Authorization = "Token 18a09ac581f3b2679df0f538698e2893aac493a7"
    Accept = "application/json"
  }
}


provider "proxmox" {  
  pm_api_url = "https://pve.thejfk.ca/api2/json"    
  pm_api_token_id = "terraform@pam!main_terraform"    
  pm_api_token_secret = "b01b0155-c025-4b3a-b173-cb6b1bf9eb17"    
  pm_tls_insecure = false
}


locals {
  # This will now work because NetBox is sending valid JSON
  vms = jsondecode(data.http.netbox_export.response_body)
}

resource "proxmox_vm_qemu" "proxmox_vms" {
  for_each = { for vm in local.vms : vm.name => vm }

  name        = each.value.name
  vmid        = each.value.vmid
  target_node = each.value.target_node
  memory      = each.value.memory
  cores       = each.value.cores

  # Hardcode your constants here instead of in the NetBox template
  os_type    = "cloud-init"
  scsihw     = "virtio-scsi-pci"
  boot       = "order=scsi0;ide3"
  ciuser     = "kevin"
  cipassword = "sensitive_password" # Or use a variable
  sshkeys    = "ssh-ed25519 AAA..."

  disks {
    scsi {
      scsi0 {
        disk {
          storage = each.value.storage
          size    = "8G" # We can refine this later
        }
      }
    }
  }

  network {
    id     = 0
    model  = "virtio"
    bridge = "vmbr0"
  }

  lifecycle {
    prevent_destroy = true
    ignore_changes  = all
  }
}