terraform {
  required_providers {
    proxmox = {
      source = "telmate/proxmox"
      version = "2.9.14"
    }
  }
}

provider "proxmox" {
  # url is the hostname (FQDN if you have one) for the proxmox host you'd like to connect to to issue the commands. my proxmox host is 'prox-1u'. Add /api2/json at the end for the API
  pm_api_url = "https://pve.thejfk.ca/api2/json"
  
  # api token id is in the form of: <username>@pam!<tokenId>
  pm_api_token_id = "terraform@pam!main_terraform"
  
  # this is the full secret wrapped in quotes. don't worry, I've already deleted this from my proxmox cluster by the time you read this post
  pm_api_token_secret = "b01b0155-c025-4b3a-b173-cb6b1bf9eb17"
  
  # leave tls_insecure set to true unless you have your proxmox SSL certificate situation fully sorted out (if you do, you will know)
  pm_tls_insecure = false
}

resource "proxmox_lxc" "lxc-test" {
    features {
        nesting = true
    }
    hostname = "terraform-new-container"
    network {
        name = "eth0"
        bridge = "vmbr0"
        ip = "dhcp"
        ip6 = "dhcp"
    }
    rootfs {
        storage = "ceph"
        size    = "8G"
    }
    ostemplate = "truenas-nfs:vztmpl/ubuntu-22.04-standard_22.04-1_amd64.tar.zst"
    password = "rootroot"
    pool = "HA-3"
    target_node = "pve"
    unprivileged = true
}