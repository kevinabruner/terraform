variable "ssh_key" {
  default = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABAQDcwZAOfqf6E6p8IkrurF2vR3NccPbMlXFPaFe2+Eh/8QnQCJVTL6PKduXjXynuLziC9cubXIDzQA+4OpFYUV2u0fAkXLOXRIwgEmOrnsGAqJTqIsMC3XwGRhR9M84c4XPAX5sYpOsvZX/qwFE95GAdExCUkS3H39rpmSCnZG9AY4nPsVRlIIDP+/6YSy9KWp2YVYe5bDaMKRtwKSq3EOUhl3Mm8Ykzd35Z0Cysgm2hR2poN+EB7GD67fyi+6ohpdJHVhinHi7cQI4DUp+37nVZG4ofYFL9yRdULlHcFa9MocESvFVlVW0FCvwFKXDty6askpg9yf4FnM0OSbhgqXzD austin@EARTH"
}
variable "proxmox_host" {
    default = "pve"
}
variable "vm_name" {
    default = "testingagain"
}
variable "vm_ip" {
    default = "192.168.11.188"
}
variable "password" {
    default = "obo74Cle"
}
variable "vm_pool" {
    default = "personal"
}
variable "vm_node" {
    default = "pve"
}
variable "cores" {
    default = "1"
}
variable "memory" {
    default = "1024"
}
variable "vmid" {
    default = "149"
}