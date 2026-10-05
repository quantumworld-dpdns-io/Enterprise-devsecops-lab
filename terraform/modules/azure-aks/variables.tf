variable "name" {
  description = "Short name used in every resource name (lowercase, digits, dashes)."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{2,14}$", var.name))
    error_message = "name must be 3-15 chars, lowercase letters, digits and dashes."
  }
}

variable "location" {
  description = "Azure region."
  type        = string
  default     = "westeurope"
}

variable "kubernetes_version" {
  description = "AKS Kubernetes version (null = current default)."
  type        = string
  default     = null
}

variable "private_cluster" {
  description = "Private API server (no public endpoint). Recommended for production."
  type        = bool
  default     = false
}

variable "sku_tier" {
  description = "Free (dev) or Standard (uptime SLA)."
  type        = string
  default     = "Free"
}

variable "vnet_cidr" {
  description = "VNet address space."
  type        = string
  default     = "10.40.0.0/16"
}

variable "pod_cidr" {
  description = "Overlay pod CIDR (not routed in the VNet)."
  type        = string
  default     = "10.244.0.0/16"
}

variable "service_cidr" {
  description = "Kubernetes service CIDR."
  type        = string
  default     = "10.41.0.0/16"
}

variable "zones" {
  description = "Availability zones for node pools."
  type        = list(string)
  default     = ["1", "2", "3"]
}

variable "system_vm_size" {
  description = "VM size of the system pool."
  type        = string
  default     = "Standard_D4ds_v5" # "d" sizes have the local disk that ephemeral OS needs
}

variable "apps_vm_size" {
  description = "VM size of the application pool."
  type        = string
  default     = "Standard_D4ds_v5"
}

variable "apps_spot" {
  description = "Run the application pool on Spot capacity (dev cost saving)."
  type        = bool
  default     = false
}

variable "host_encryption_enabled" {
  description = "Encrypt temp disks and caches at the host (needs the EncryptionAtHost feature registered)."
  type        = bool
  default     = true
}

variable "admin_group_object_ids" {
  description = "Entra ID groups with cluster-admin."
  type        = list(string)
  default     = []
}

variable "admin_cidrs" {
  description = "CIDRs allowed to reach the API server and the Key Vault data plane."
  type        = list(string)
}

variable "log_retention_days" {
  description = "Log Analytics retention."
  type        = number
  default     = 30
}

variable "log_daily_quota_gb" {
  description = "Daily ingestion cap for Log Analytics (-1 = unlimited)."
  type        = number
  default     = 5
}

variable "app_namespace" {
  description = "Namespace of the workload bound to a managed identity."
  type        = string
  default     = "demo"
}

variable "app_service_account" {
  description = "Service account of that workload."
  type        = string
  default     = "demo-app"
}

variable "tags" {
  description = "Tags on every resource (owner, cost-center, environment)."
  type        = map(string)
  default     = {}
}
