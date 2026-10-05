variable "name" {
  description = "Cluster name; also the prefix for every resource."
  type        = string
}

variable "kubernetes_version" {
  description = "EKS control plane version."
  type        = string
  default     = "1.33"
}

variable "vpc_cidr" {
  description = "VPC CIDR. Three /20 private and three /24 public subnets are carved from it."
  type        = string
  default     = "10.30.0.0/16"
}

variable "azs" {
  description = "Exactly three availability zones."
  type        = list(string)

  validation {
    condition     = length(var.azs) == 3
    error_message = "Provide exactly three availability zones."
  }
}

variable "single_nat_gateway" {
  description = "One NAT gateway for all AZs (cheaper, not zone-redundant). false = one per AZ."
  type        = bool
  default     = true
}

variable "public_access_cidrs" {
  description = "CIDRs allowed to reach the public API endpoint. Empty disables the public endpoint."
  type        = list(string)
  default     = []
}

variable "admin_role_arns" {
  description = "IAM role ARNs granted cluster-admin through EKS access entries."
  type        = list(string)
  default     = []
}

variable "readonly_role_arns" {
  description = "IAM role ARNs granted read-only cluster access."
  type        = list(string)
  default     = []
}

variable "node_instance_types" {
  description = "Instance types for the managed node group (several types improve Spot/On-Demand availability)."
  type        = list(string)
  default     = ["m7i.large", "m6i.large"]
}

variable "node_capacity_type" {
  description = "ON_DEMAND or SPOT."
  type        = string
  default     = "ON_DEMAND"

  validation {
    condition     = contains(["ON_DEMAND", "SPOT"], var.node_capacity_type)
    error_message = "node_capacity_type must be ON_DEMAND or SPOT."
  }
}

variable "node_min" {
  description = "Minimum nodes."
  type        = number
  default     = 2
}

variable "node_desired" {
  description = "Desired nodes."
  type        = number
  default     = 3
}

variable "node_max" {
  description = "Maximum nodes."
  type        = number
  default     = 6
}

variable "log_retention_days" {
  description = "CloudWatch retention for control-plane and flow logs (365 = one year of audit evidence)."
  type        = number
  default     = 365
}

variable "app_namespace" {
  description = "Namespace of the demo workload that gets an IAM role via EKS Pod Identity."
  type        = string
  default     = "demo"
}

variable "app_service_account" {
  description = "Service account of the demo workload."
  type        = string
  default     = "demo-app"
}

variable "tags" {
  description = "Extra tags on every resource (cost allocation: owner, cost-center, env)."
  type        = map(string)
  default     = {}
}
