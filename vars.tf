##If there is no value here, they will need to be exported manually or placed in /etc/environment

variable "proxmox_api_token_secret" { 
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