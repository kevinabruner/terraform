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
  vm_configs = {
    for vm in local.vms : vm.name => merge(vm, {
      primary_iface = [for i in vm.interfaces : i if i.is_primary][0]
      gateway       = "${join(".", slice(split(".", [for i in vm.interfaces : i.ip if i.is_primary][0]), 0, 3))}.1"
    }) if vm.name != ""
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

  user_data = <<-EOT
    #cloud-config
    users:
      - name: ${var.vm_username}
        passwd: '${var.vm_password}'
        lock_passwd: false
        sudo: ALL=(ALL) NOPASSWD:ALL
        groups: [adm, conf, dip, lxd, plugdev, sudo]
        shell: /bin/bash
        ssh_authorized_keys:
    %{ for key in split("\n", trimspace(each.value.ssh_keys)) ~}
          - ${trimspace(key)}
    %{ endfor ~}

    package_update: false
    packages:
      - qemu-guest-agent
      %{~ if each.value.role == "Drupal" ~}
      - apache2
      %{~ endif ~}

    #cloud-config
    write_files:
    %{~ if each.value.role == "Drupal" ~}
      - path: /etc/apache2/conf-available/Drupal-env.conf
        content: |
          SetEnv mysql_db_host "db-${each.value.env}.jfkhome"
        owner: root:root
        permissions: '0644'
    %{~ endif ~}
      - path: /etc/environment
        content: |
          NETBOX_ID=${each.value.vmid}
          VM_NAME=${each.value.name}
          mysql_db_host=db-${each.value.env}.jfkhome
        append: true

    runcmd:
      - systemctl enable qemu-guest-agent
      - systemctl start qemu-guest-agent
    %{~ if each.value.role == "Drupal" ~}
      - a2enconf Drupal-env
    %{~ endif ~}

    power_state:
      delay: "now"
      mode: reboot
      message: "Rebooting to initialize Guest Agent"
      condition: true
      EOT

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
    searchdomains:
    - jfkhome
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