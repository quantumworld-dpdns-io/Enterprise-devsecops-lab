output "name" {
  description = "VM name."
  value       = proxmox_virtual_environment_vm.this.name
}

output "ipv4" {
  description = "Configured static address (without prefix)."
  value       = split("/", var.ipv4_cidr)[0]
}

output "role" {
  description = "Role tag."
  value       = var.role
}
