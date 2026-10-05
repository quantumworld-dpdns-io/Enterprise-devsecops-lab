variable "name" {
  description = "VM and host name."
  type        = string
}

variable "role" {
  description = "Role tag, used by inventory and dashboards (k3s-server, k3s-agent, runner, security)."
  type        = string
}

variable "extra_tags" {
  description = "Additional Proxmox tags."
  type        = list(string)
  default     = []
}

variable "node_name" {
  description = "Proxmox node that hosts the VM."
  type        = string
}

variable "vm_id" {
  description = "Proxmox VM ID."
  type        = number
}

variable "template_id" {
  description = "VM ID of the cloud-init template to clone."
  type        = number
}

variable "cores" {
  description = "vCPU count."
  type        = number
  default     = 2
}

variable "memory_mb" {
  description = "Dedicated memory in MiB."
  type        = number
  default     = 4096
}

variable "disk_gb" {
  description = "Root disk size in GiB."
  type        = number
  default     = 32
}

variable "datastore_id" {
  description = "Datastore for the disk and cloud-init drive."
  type        = string
  default     = "local-lvm"
}

variable "bridge" {
  description = "Linux bridge for the NIC."
  type        = string
  default     = "vmbr0"
}

variable "vlan_id" {
  description = "VLAN tag, or null for untagged."
  type        = number
  default     = null
}

variable "ipv4_cidr" {
  description = "Static address in CIDR form, e.g. 10.10.10.10/24."
  type        = string

  validation {
    condition     = can(cidrhost(var.ipv4_cidr, 0))
    error_message = "ipv4_cidr must be an address in CIDR notation."
  }
}

variable "gateway" {
  description = "Default gateway."
  type        = string
}

variable "dns_servers" {
  description = "DNS resolvers."
  type        = list(string)
}

variable "dns_domain" {
  description = "Search domain."
  type        = string
  default     = "lab.example"
}

variable "admin_user" {
  description = "Cloud-init admin user (SSH key only, no password)."
  type        = string
  default     = "labadmin"
}

variable "ssh_public_keys" {
  description = "Authorized SSH public keys for the admin user."
  type        = list(string)
}
