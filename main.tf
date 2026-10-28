# Default Provider (Cambridge / Site A)
provider "proxmox" {
  endpoint = var.proxmox_api_url_cambridge
  username = "root@pam"
  password = var.proxmox_password 
  insecure = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file("~/.ssh/id_rsa")
    node {
      name    = "pve"
      address = "192.168.11.15"
    }
  }
}

# Aliased Provider (Rockwood / Site B)
provider "proxmox" {
  alias    = "rockwood"
  endpoint = var.proxmox_api_url_rockwood # Make sure this variable is declared in your root variables.tf
  username = "root@pam"
  password = var.proxmox_password 
  insecure = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file("~/.ssh/id_rsa")
    node {
      name    = "site-b"    # Or hardcode your Node name for Site B
      address = "10.10.10.15" # Or hardcode your Site B Proxmox IP/Tailscale IP
    }
  }
}

terraform {
  required_version = ">= 1.5.0"
  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.116.0"
    }
    netbox = {
      source  = "e-breuninger/netbox"
      version = "~> 5.0"
    }
  }
}

# ------------------------------------------------------------------------------
# DEPLOY CAMBRIDGE (SITE A) WORKLOADS
# ------------------------------------------------------------------------------
module "cambridge_nodes" {
  source   = "./modules/compute-node"
  for_each = local.cambridge_workloads # Combines VMs and CTs into one map or call separately

  vm_config         = each.value
  ceph_mounts       = local.ceph_mounts
  role_configs      = local.role_configs
  vm_username       = var.vm_username
  vm_password       = var.vm_password
  mirror_url        = var.mirror_url
  default_dns       = "192.168.11.99"
  default_domain    = "jfkhome"
  default_datastore = "truenas-nfs"
}

# ------------------------------------------------------------------------------
# DEPLOY ROCKWOOD (SITE B) WORKLOADS
# ------------------------------------------------------------------------------
module "rockwood_nodes" {
  source   = "./modules/compute-node"
  for_each = local.rockwood_workloads

  # THIS IS WHERE THE MAGIC HAPPENS: Passes the Rockwood provider alias into the module
  providers = {
    proxmox = proxmox.rockwood
  }

  vm_config         = each.value
  ceph_mounts       = local.ceph_mounts
  role_configs      = local.role_configs
  vm_username       = var.vm_username
  vm_password       = var.vm_password
  mirror_url        = var.mirror_url
  default_dns       = "192.168.100.1"
  default_domain    = "rockwood.local"
  default_datastore = each.value.storage # Site B local storage
}