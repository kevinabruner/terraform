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
  
  # Merge in VM Data with computed network data
  vm_configs = {
    for vm in local.vms : vm.name => merge(vm, {
      # Extract Primary Interface
      primary_iface = [for i in vm.interfaces : i if i.is_primary][0]
      # Construct Gateway from Primary IP
      gateway = "${join(".", slice(split(".", [for i in vm.interfaces : i.ip if i.is_primary][0]), 0, 3))}.1"
    }) if vm.name != ""
  }

  # Role-based configurations
  role_configs = {
    "Drupal" = {
      has_keepalived = false
      packages = ["apache2"]
      commands = [
        "a2enconf Drupal-env || true", 
        "systemctl restart apache2 || true",
        "sed -i 's/,noauto//g' /etc/fstab || true",
        "mount -a || true"
      ]
      files    = [
        {
          path    = "/etc/apache2/conf-available/Drupal-env.conf"
          content = "SetEnv environment \"$${env}\"" 
        }
      ]
    }
    "Reverse proxy" = {
      has_keepalived = true
      packages       = ["unattended-upgrades"]
      commands       = ["systemctl restart keepalived"]
      files          = []
    }
    "Database proxy" = {
      has_keepalived = true
      packages       = ["unattended-upgrades"]
      commands       = ["systemctl restart keepalived"]
      files          = []
    }
    "psql server" = {
      has_keepalived = false
      packages       = ["unattended-upgrades"]
      commands       = []
      files          = []
    }
    "DNS resolver" = {
      has_keepalived = true
      packages       = ["unattended-upgrades"]
      commands       = ["systemctl restart keepalived"]
      files          = []
    }
    "Default" = { 
      has_keepalived = false
      packages = ["unattended-upgrades"]
      commands = []
      files    = [] 
    }
  }
}


resource "proxmox_cloud_init_disk" "ci_configs" {
  for_each = local.vm_configs
  name     = "${each.value.vmid}-cidata"
  pve_node = each.value.node
  storage  = "local"

  meta_data = <<-EOT
    instance-id: ${each.value.name}
    local-hostname: ${each.value.name}
  EOT

  user_data = templatefile("${path.module}/templates/user_data.tftpl", {
    # 1. Basic Identity
    username = var.vm_username
    password = var.vm_password
    ssh_keys = split("\n", trimspace(each.value.ssh_keys))
    name     = each.value.name
    vmid     = each.value.vmid
    env      = each.value.env
    use_mirror   = each.value.use_mirror
    mirror_url   = var.mirror_url
    os           = each.value.os
    role         = each.value.role
    node_ip_with_cidr = each.value.primary_iface.ip
    subnet            = cidrsubnet(each.value.primary_iface.ip, 0, 0)    

    # 3. RENDER ETCD SUBTEMPLATE
    etcd_content = templatefile("${path.module}/templates/_etcd.tftpl", {
      name       = each.value.name
      local_ip         = split("/", each.value.primary_iface.ip)[0]
      cluster_members = {
        for k, v in local.vm_configs : k => v
        if v.role == each.value.role && v.env == each.value.env
      }
    })

    # 4. RENDER PATRONI SUBTEMPLATE 
    patroni_content = templatefile("${path.module}/templates/_patroni.yml.tftpl", {
      name = each.value.name
      local_ip   = split("/", each.value.primary_iface.ip)[0]
      subnet            = cidrsubnet(each.value.primary_iface.ip, 0, 0) 
      cluster_members = {
        for k, v in local.vm_configs : k => v
        if v.role == each.value.role && v.env == each.value.env
      }   
      password = "87Josie*"
    })

    # 2. Extract Role Data from Locals
    extra_packages = lookup(local.role_configs, each.value.role, local.role_configs["Default"]).packages
    extra_files    = lookup(local.role_configs, each.value.role, local.role_configs["Default"]).files
    extra_commands = lookup(local.role_configs, each.value.role, local.role_configs["Default"]).commands
    
    # 3. Boolean for all *-prod1 instances
    is_drupal_master = (each.value.role == "Drupal" && each.value.env == "prod" && endswith(each.value.name, "1"))
    
    # Keepalived Logic
    has_keepalived = lookup(local.role_configs, each.value.role, local.role_configs["Default"]).has_keepalived
    is_vrrp_master = endswith(each.value.name, "1")
    local_ip       = split("/", each.value.primary_iface.ip)[0] # Strip CIDR mask
    
    # Peer IP Search: Find the OTHER node with same role and env
    peer_ip = try(split("/", [
      for name, v in local.vm_configs : v.primary_iface.ip 
      if v.role == each.value.role && v.env == each.value.env && v.name != each.value.name
    ][0])[0], "127.0.0.1")

    # find all peers and return as a string (for db servers)
    peer_ips_csv = join(",", [
      for name, v in local.vm_configs : split("/", v.primary_iface.ip)[0]
      if v.role == each.value.role && v.env == each.value.env && v.name != each.value.name
    ])

    # --- THE ETCD CLUSTER LOGIC ---
    # This filters all VMs to find peers in the same role and environment
    cluster_members = {
      for k, v in local.vm_configs : k => v
      if v.role == each.value.role && v.env == each.value.env
    }
  })

  
  #Dynamically generate network config based on interfaces in Netbox
  network_config = <<-EOT
version: 2
ethernets:
%{ for index, iface in each.value.interfaces ~}
  ens${18 + index}:
    optional: true
    addresses:
      - ${iface.ip}
%{ if iface.is_primary ~}
    nameservers:
      addresses: [192.168.11.99]
      search: [jfkhome]
    routes:
      - to: 0.0.0.0/0
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
  clone_wait         = 15

  os_type            = "ubuntu"
  scsihw             = "virtio-scsi-pci"
  boot               = "order=scsi0;net0;ide3;ide2"
  vm_state           = each.value.status
  define_connection_info = false

  serial {
    id   = 0
    type = "socket"
  }

  timeouts {
    create = "15m"
    delete = "15m"
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
      bridge = network.value.bridge
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
      boot,
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
resource "null_resource" "etcd_lifecycle" {
  for_each = {
    for k, v in local.vm_configs : k => v 
    if v.role == "psql server"
  }

  triggers = {
    # This captures the VM's name; if you want to force a run, 
    # you can add a 'revision' variable here or use the VM's state.
    node_name = each.value.name
    node_ip   = split("/", each.value.primary_iface.ip)[0]
    ssh_user  = var.vm_username
    peer_ips  = join(" ", [
      for k, v in local.vm_configs : split("/", v.primary_iface.ip)[0]
      if v.role == "psql server" && v.env == each.value.env && v.name != each.value.name
    ])
  }

  # --- CREATE PHASE (Join) ---
  # We still SSH into the NEW node to tell it to join.
  connection {
    type        = "ssh"
    host        = self.triggers.node_ip
    user        = self.triggers.ssh_user
    private_key = file("~/.ssh/id_rsa")
    timeout     = "5m"
  }

  provisioner "remote-exec" {
    inline = [
      <<-EOT
      # Wait for etcd to be installed/ready if this is a fresh boot
      until command -v etcdctl >/dev/null 2>&1; do echo "Waiting for etcdctl..."; sleep 5; done
      
      HEALTHY_PEER=""
      for peer in ${self.triggers.peer_ips}; do
        if curl -s --connect-timeout 2 http://$peer:2379/health | grep -q '{"health":"true"}'; then
          HEALTHY_PEER=$peer
          break
        fi
      done

      if [ -n "$HEALTHY_PEER" ]; then
        echo "Joining cluster via $HEALTHY_PEER"
        etcdctl --endpoints=http://$HEALTHY_PEER:2379 member add ${self.triggers.node_name} --peer-urls=http://${self.triggers.node_ip}:2380 || true
      fi
      EOT
    ]
  }

  # --- DESTROY PHASE (Remove) ---
  # IMPORTANT: We run this LOCALLY because the node being destroyed might be gone.
  provisioner "local-exec" {
    when    = destroy
    command = <<-EOT
      for peer in ${self.triggers.peer_ips}; do
        # Try to find a survivor to execute the removal
        if curl -s --connect-timeout 2 http://$peer:2379/health | grep -q '{"health":"true"}'; then
          echo "Removing ${self.triggers.node_name} from cluster via peer $peer"
          MEMBER_ID=$(ssh -o StrictHostKeyChecking=no ${self.triggers.ssh_user}@$peer "etcdctl member list | grep '${self.triggers.node_name}' | cut -d',' -f1")
          if [ -n "$MEMBER_ID" ]; then
            ssh -o StrictHostKeyChecking=no ${self.triggers.ssh_user}@$peer "etcdctl member remove $MEMBER_ID"
            exit 0
          fi
        fi
      done
      echo "No survivors found or member already removed."
    EOT
  }
}
resource "local_file" "debug_rendered_yaml" {
  for_each = local.vm_configs
  content  = proxmox_cloud_init_disk.ci_configs[each.key].user_data
  filename = "${path.module}/debug/${each.key}_cloud_init.yaml"
}
# resource "local_file" "debug_network_config" {
#   for_each = local.vm_configs
#   content  = <<-EOT
# version: 2
# ethernets:
# %{ for index, iface in each.value.interfaces ~}
#   ens${18 + index}:
#     addresses:
#       - ${iface.ip}
# %{ if iface.is_primary ~}
#     gateway4: ${each.value.gateway}
#     nameservers:
#       addresses: [192.168.11.99]
#       search: [jfkhome]
#     routes:
#       - to: default
#         via: ${each.value.gateway}
# %{ endif ~}
# %{ endfor ~}
# EOT
#   filename = "${path.module}/debug/debug_${each.key}.yaml"
# }