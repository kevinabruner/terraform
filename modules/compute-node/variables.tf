# modules/compute-node/variables.tf

variable "vm_config" {
  type = map(any)
}

variable "ceph_mounts" {
  type = map(any)
}

variable "role_configs" {
  type = map(any)
}

variable "vm_username" {
  type = string
}

variable "vm_password" {
  type      = string
  sensitive = true
}

variable "mirror_url" {
  type = string
}

variable "default_dns" {
  type = string
}

variable "default_domain" {
  type = string
}

variable "default_datastore" {
  type = string
}