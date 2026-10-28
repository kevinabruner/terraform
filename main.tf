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

data "http" "netbox_export" {
  url = "https://netbox.thejfk.ca/api/virtualization/virtual-machines/?export=Main+terraform+templates"
  request_headers = {
    Authorization = "Token ${var.netbox_api_token_secret}"
    Accept        = "application/json"
  }
}

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
  endpoint = var.proxmox_api_url_rockwood
  username = "root@pam"
  password = var.proxmox_password 
  insecure = true

  ssh {
    agent       = false
    username    = "root"
    private_key = file("~/.ssh/id_rsa")
    node {
      name    = var.rockwood_node_name
      address = var.rockwood_node_address
    }
  }
}

locals {
  ceph_mounts = {
    garage = { volume = "/mnt/pve/cephfs/garage", path = "/var/lib/garage/data" }
    psql   = { volume = "/mnt/pve/cephfs/psql-dumps/db-dumps", path = "/home/kevin/admin" }
    db-prod = { volume = "/mnt/pve/cephfs/galera-dumps/db-dumps", path = "/home/kevin/db-dumps" }
    db-dev  = { volume = "/mnt/pve/cephfs/galera-dumps/db-dumps", path = "/home/kevin/db-dumps" }
    nerdperk = { volume = "/mnt/pve/cephfs/nerdperk/files", path = "/var/www/html/sites/default/files/" }
    recursioncomic = { volume = "/mnt/pve/cephfs/recursioncomic/files", path = "/var/www/html/sites/default/files/" }
    koscinski = { volume = "/mnt/pve/cephfs/koscinski/files", path = "/var/www/html/sites/default/files/" }
  }

  vms = jsondecode(data.http.netbox_export.response_body)

  role_configs = {
    for f in fileset("${path.module}/roles", "*.yaml") :
    yamldecode(file("${path.module}/roles/${f}")).name => yamldecode(file("${path.module}/roles/${f}"))
  }

  vm_configs = {
    for vm in local.vms : vm.name => merge(vm, {
      site    = try(vm.site.name, vm.site, "Cambridge")
      vm_type = try(vm.custom_fields.vm_type.value, vm.vm_type, "vm")
      image   = try(vm.custom_fields.template.value, vm.template, vm.image, "")
      pool    = try(vm.custom_fields.proxmox_pool.value, vm.pool, "")
      storage = try(vm.custom_fields.storage_location.value, vm.storage, "local-zfs")
      os      = try(vm.custom_fields.os.value, vm.os, "debian")
      primary_iface = [for i in vm.interfaces : i if i.is_primary][0]
      gateway       = "${join(".", slice(split(".", [for i in vm.interfaces : i.ip if i.is_primary][0]), 0, 3))}.1"
    }) if vm.name != ""
  }

  cambridge_vms = { for k, v in local.vm_configs : k => v if v.site == "Cambridge" && try(v.vm_type, "vm") == "vm" }
  rockwood_vms  = { for k, v in local.vm_configs : k => v if v.site == "Rockwood" && try(v.vm_type, "vm") == "vm" }

  cambridge_cts = { for k, v in local.vm_configs : k => v if v.site == "Cambridge" && try(v.vm_type, "") == "ct" }
  rockwood_cts  = { for k, v in local.vm_configs : k => v if v.site == "Rockwood" && try(v.vm_type, "") == "ct" }

  cambridge_workloads = merge(local.cambridge_vms, local.cambridge_cts)
  rockwood_workloads  = merge(local.rockwood_vms, local.rockwood_cts)
}

# ------------------------------------------------------------------------------
# DEPLOY CAMBRIDGE (SITE A) WORKLOADS (Using your modular setup)
# ------------------------------------------------------------------------------
module "cambridge_nodes" {
  source   = "./modules/compute-node"
  for_each = local.cambridge_workloads

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
  default_datastore = each.value.storage
}

resource "null_resource" "node_bootstrap" {
  for_each = { for k, v in local.cambridge_cts : k => v if strcontains(k, "psql") }

  triggers = {    
    container_id = module.cambridge_nodes[each.key].container_id
  }

  provisioner "local-exec" {
    command = "/home/kevin/psql/join_node.sh ${each.key}"
  }
}