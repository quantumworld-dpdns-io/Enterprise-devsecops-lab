variable "proxmox_node" {
  description = "Proxmox node name."
  type        = string
  default     = "pve-lab-1"
}

variable "proxmox_insecure" {
  description = "Skip TLS verification of the Proxmox API (self-signed lab certificate)."
  type        = bool
  default     = true
}

variable "template_id" {
  description = "Cloud-init Ubuntu 24.04 template VM ID."
  type        = number
  default     = 9000
}

variable "bridge" {
  description = "VLAN-aware bridge."
  type        = string
  default     = "vmbr0"
}

variable "mgmt_vlan" {
  description = "VLAN for management and k3s nodes."
  type        = number
  default     = 10
}

variable "security_vlan" {
  description = "VLAN for the security tooling VM."
  type        = number
  default     = 100
}

variable "dns_servers" {
  description = "Resolvers handed to cloud-init."
  type        = list(string)
  default     = ["10.10.10.1"]
}

variable "ssh_public_keys" {
  description = "SSH public keys for the admin user. Set in terraform.tfvars (git-ignored)."
  type        = list(string)
}
