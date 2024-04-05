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