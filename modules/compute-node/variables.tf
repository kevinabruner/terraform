# modules/compute-node/variables.tf

variable "vm_config" {
  type = any
}

variable "ceph_mounts" {
  type = any
}

variable "role_configs" {
  type = any
}

variable "vm_username" {
  type = any
}

variable "vm_password" {
  type      = any
  sensitive = true
}

variable "mirror_url" {
  type = any
}

variable "default_dns" {
  type = any
}

variable "default_domain" {
  type = any
}

variable "default_datastore" {
  type = any
}