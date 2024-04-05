terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "2.9.14"
    }
  }
}

provider "proxmox" {  
  pm_api_url = "https://pve.thejfk.ca/api2/json"    
  pm_api_token_id = "terraform@pam!main_terraform"    
  pm_api_token_secret = "b01b0155-c025-4b3a-b173-cb6b1bf9eb17"    
  pm_tls_insecure = false
}

resource "proxmox_lxc" "vm_name" {
    count = 1
    features {
        nesting = true
    }
    hostname = var.vm_name
    network {
        name = "net0"
        bridge = "vmbr0"
        ip = var.vm_ip
        ip6 = "dhcp"
    }
    rootfs {
        storage = "ceph"
        size    = "8G"
    }
    ostemplate = "truenas-nfs:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    password = var.password
    pool = var.vm_pool
    target_node = var.vm_node
    unprivileged = true
    cores = var.cores
    memory = var.memory    
    vmid = var.vmid
}