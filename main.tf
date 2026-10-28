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