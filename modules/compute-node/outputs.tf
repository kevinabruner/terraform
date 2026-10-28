output "container_id" {
  value = length(proxmox_virtual_environment_container.ct) > 0 ? proxmox_virtual_environment_container.ct[0].id : null
}