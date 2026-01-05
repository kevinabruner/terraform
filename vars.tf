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