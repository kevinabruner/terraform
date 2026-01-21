terraform {
  required_providers {
    proxmox = {
      source  = "telmate/proxmox"
      version = "3.0.2-rc07"
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

provider "proxmox" {
  pm_api_url          = var.proxmox_api_url
  pm_api_token_id     = var.proxmox_api_token_id
  pm_api_token_secret = var.proxmox_api_token_secret
  pm_tls_insecure     = false
  pm_parallel         = 3
}


locals {
  vms = jsondecode(data.http.netbox_export.response_body)
  drupal_script_raw = trimspace(file("${path.module}/scripts/drupal_prod_db_flush.sh"))
  vm_configs = {
    for vm in local.vms : vm.name => merge(vm, {
      primary_iface = [for i in vm.interfaces : i if i.is_primary][0]
      gateway       = "${join(".", slice(split(".", [for i in vm.interfaces : i.ip if i.is_primary][0]), 0, 3))}.1"
    }) if vm.name != ""
  }
  role_configs = {
    "Drupal" = {
      packages        = ["apache2", "php", "libapache2-mod-php"]
      commands        = ["a2enconf Drupal-env || true", "systemctl restart apache2 || true"]
      files           = [{ path = "/etc/apache2/conf-available/Drupal-env.conf", content = "SetEnv environment \"$${env}\"" }]
      custom_script = local.drupal_script_template # Put the script here
    }
    "Default" = {
      packages        = []
      commands        = []
      files           = []
      custom_script = "" # Must exist, even if empty
    }
    "Database" = {
      packages        = ["mariadb-server"]
      commands        = []
      files           = []
      custom_script = "" # Must exist
    }
  }
}

resource "proxmox_cloud_init_disk" "ci_configs" {
  for_each = local.vm_configs
  name     = "${each.value.vmid}-cidata"
  pve_node = each.value.node
  storage  = "cephfs"

  meta_data = <<-EOT
    instance-id: ${each.value.name}
    local-hostname: ${each.value.name}
  EOT

  user_data = templatefile("${path.module}/templates/main.tftpl", {
    # 1. Basic Identity
    username = var.vm_username
    password = var.vm_password
    ssh_keys = split("\n", trimspace(each.value.ssh_keys))
    name     = each.value.name
    vmid     = each.value.vmid
    env      = each.value.env

    # 2. Extract Role Data from Locals
    extra_packages = lookup(local.role_configs, each.value.role, local.role_configs["Default"]).packages
    extra_files    = lookup(local.role_configs, each.value.role, local.role_configs["Default"]).files
    
    # 3. Dynamic Logic for Commands (The "Switch" replacement)
    extra_commands = concat(
      lookup(local.role_configs, each.value.role, local.role_configs["Default"]).commands,
      
      # Logic for the Drupal-specific script
      (each.value.role == "Drupal" && each.value.env == "prod" && endswith(each.value.name, "1")) ? [
        "|\n${indent(4, replace(local.drupal_script_raw, "REPLACE_ME_ENV", each.value.env))}"
      ] : []
    )
  })

      

  network_config = <<-EOT
version: 2
ethernets:
%{ for index, iface in each.value.interfaces ~}
  ens${18 + index}:
    addresses:
      - ${iface.ip}
%{ if iface.is_primary ~}
    gateway4: ${each.value.gateway}
    nameservers:
      addresses: [192.168.11.99]
      search: [jfkhome]
    routes:
      - to: default
        via: ${each.value.gateway}
%{ endif ~}
%{ endfor ~}
EOT


}

resource "proxmox_vm_qemu" "proxmox_vms" {
  for_each           = local.vm_configs
  name               = each.value.name
  vmid               = each.value.vmid
  target_node        = each.value.node
  description        = each.value.desc
  pool               = each.value.pool != "" ? each.value.pool : null
  start_at_node_boot = each.value.start_at_node_boot
  agent              = 1
  memory             = each.value.memory
  clone              = each.value.image
  full_clone         = true
  clone_wait             = 30
  os_type            = "cloud-init"
  scsihw             = "virtio-scsi-pci"
  boot               = "order=scsi0;ide3"
  vm_state           = each.value.status
  define_connection_info = false

  serial {
    id   = 0
    type = "socket"
  }

  timeouts {
    create = "5m"
    delete = "5m"
  }

  cpu {
    cores   = each.value.cores
    sockets = 1
    type    = "host"
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
        cdrom {
          iso = proxmox_cloud_init_disk.ci_configs[each.key].id
        }
      }
    }
  }


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
resource "local_file" "debug_rendered_yaml" {
  for_each = local.vm_configs
  content  = proxmox_cloud_init_disk.ci_configs[each.key].user_data
  filename = "${path.module}/debug/${each.key}_cloud_init.yaml"
}