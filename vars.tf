##----------------BIG NOTE:---------------###
#  If there is no "default" value here,     #
#  they will need to be exported manually   #
#  or placed in /etc/environment            #
##--------------END BIG NOTE:-------------###

variable "proxmox_api_token_secret" { 
    type = string
    sensitive = true 
}

variable "proxmox_api_url" {
    type = string
    default = "https://pve.thejfk.ca/api2/json"
}

variable "proxmox_api_token_id" {
    type = string
    default = "terraform@pam!main_terraform"
}

variable "netbox_api_token_secret" { 
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