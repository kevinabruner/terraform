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
    Authorization = "18a09ac581f3b2679df0f538698e2893aac493a7"
    Accept        = "text/plain"
  }
}
provider "proxmox" {  
  pm_api_url = "https://pve.thejfk.ca/api2/json"    
  pm_api_token_id = "terraform@pam!main_terraform"    
  pm_api_token_secret = "b01b0155-c025-4b3a-b173-cb6b1bf9eb17"    
  pm_tls_insecure = false
}


locals {
  # Decode the JSON export from the HTTP data source
  vms = jsondecode(data.http.netbox_export.response_body).results
}

resource "proxmox_vm_qemu" "proxmox_vms" {
  # This creates one resource for every VM found in the NetBox export
  for_each = { for vm in local.vms : vm.name => vm }

  name        = each.value.name
  vmid        = each.value.custom_fields.vmid # Adjust this based on your NetBox field name
  target_node = "nuc1" 

  # Add the 'Shields' we validated earlier
  lifecycle {
    prevent_destroy = true
    ignore_changes = [
      clone,
      full_clone,
      disk,
      network,
      target_node,
      qemu_os
    ]
  }
}