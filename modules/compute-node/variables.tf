##----------------BIG NOTE:---------------###
#  If there is no "default" value here,     #
#  they will need to be exported manually   #
#  or placed in /etc/environment            #
##--------------END BIG NOTE:-------------###

# variable "proxmox_api_token_secret" { 
#     type = string
#     sensitive = true 
# }

variable "proxmox_api_url" {
    type = string
    default = "https://pve.thejfk.ca/api2/json"
}

variable "proxmox_api_url_rockwood" {
    type = string
    default = "https://pve-b.thejfk.ca/api2/json"
}

# variable "proxmox_api_token_id" {
#     type = string
#     default = "root@pam!main_terraform"
# }

variable "netbox_api_token_secret" { 
    type = string
    sensitive = true 
}

variable "mirror_url" { 
    type = string 
    default = "http://mirror.jfkhome"
}

variable "keepalived_members" { 
    type        = list(string)
    default     = [
        "Database proxy",
        "Reverse proxy"
    ]
}

variable "proxmox_password" { 
    type = string 
    sensitive = true 
}

variable "vm_password" { 
    type = string 
    sensitive = true 
}

variable "vm_username" { 
    type = string 
    default = "kevin"
}
variable "vm_config" { type = map(any) }
variable "ceph_mounts" { type = map(any) }
variable "role_configs" { type = map(any) }
variable "vm_username" { type = string }
variable "vm_password" { type = string }
variable "mirror_url" { type = string }
variable "default_dns" { type = string }
variable "default_domain" { type = string }
variable "default_datastore" { type = string }