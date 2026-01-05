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
  sshkeys = <<EOF
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIGBHWpYk7FDrlGcuQF1zYauvWa62Kmwj5Z/C/ksB0eK4 kevin@bessie
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDCfKdycPd96nMVRwU166yImlMSlgjlClJP/JpDx6fUx4xECkpxfiRWyBELTmyFp1loC0ABLL6p86GQEeriABsuOkb9zwOiUTxvJEfwuVPKULvE3kt0nZrQQd0KpGFZ2qbhlTNAUVshU0eYGONevh9AwvjkGLZxakiwIl0XF1X/RzbotYmT7D4hA7yy2/8I97hMTL7a5xSLNMJpfd6rNzq9GwX/o4b06iJjlkyMmgUJevWst4ATb9XAgkJwuuPjXM9dSJi5MwjWYkwH0zCJvutPJ5Z28oy7M1R3+oCbGh+7xNmcOhrCcceV4Z5sq3uYOy/kRR3osCU2pFgirs9TxPwqLHTTiPlcxOvAaACNK9tQDSqI+XwNecBKt4NgvbavI4WgcilqAe3lmUlMskJllEwUi3QrnSGP53LaHu2PRxrPTLfLZI5DKReKzB29FE7ZsMiOCbcTB4SJrBRmxfVB7VSNepqqmLh3RyHb0vRWidKshsz9PXb1Zynpn7nGcbMKxFE= kevin@ansible
ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQCqAJpgMNAvZsnnWEfg4vqU0LpmhNYN1+Pv9D8op3EGrCUHCmLAE9ur732ycHxBr7oKCe/G4xIV/kHivQglkGT0RrFdSNs5JY8gNo/CRICFVLsuBJPftX6b7pBdpIiEcvUugeqMJccxZ34fkiqE+z78v1T4vYSfTJwdRIiT243vJ/DxxLma3XyJgZTPi+2YTKYGKQsIHYicVeR838+mA/4hpTnRc0Oxqn1JPurhQ5wPptlUgpQCY5wGWn2Y17E8SnOmLq303SIvFdYAwZ8rxNJGm+vMuO4sUibcU4gszKI+wUR8lZtdQ2PihbHCxxF0RRtZIVYxZuy2KJsDsu2NRIxNgTU2k+Op+3igGYckYG2eJ814qScUL/KC3HcpBX2S808sT1QwfI4CxL0C3TWYKLsKqJWHLRahbnd6XPMRwi6EXrFxg5qWDD+RgWUND2Gr+2L2dTST8bvDehWbwUA+DeF2pMMT/QT1E7N9Dv71x+nx2MmiFKku9b8uA/AnngUKBn0= kevin@terraform
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFGe6k0+YsaLNbD7WiSq8jVQj0bD2AfR0HKeAlr8Stt/ kevin@fedora
EOF  

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