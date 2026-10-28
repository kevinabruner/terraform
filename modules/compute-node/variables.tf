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