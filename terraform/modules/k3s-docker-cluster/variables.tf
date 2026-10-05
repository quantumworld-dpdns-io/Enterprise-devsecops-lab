variable "cluster_name" {
  description = "Prefix for every container, volume and network."
  type        = string
  default     = "k3s"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,20}$", var.cluster_name))
    error_message = "cluster_name must be lowercase alphanumeric with dashes, 2-21 chars."
  }
}

variable "k3s_image" {
  description = "k3s image. Pin the exact version so rebuilds are reproducible."
  type        = string
  default     = "rancher/k3s:v1.31.4-k3s1"
}

variable "agent_count" {
  description = "Number of worker nodes."
  type        = number
  default     = 2

  validation {
    condition     = var.agent_count >= 1 && var.agent_count <= 5
    error_message = "agent_count must be between 1 and 5."
  }
}

variable "network_cidr" {
  description = "Node network. Server gets .10, agents .11 onwards."
  type        = string
  default     = "10.10.10.0/24"
}

variable "pod_cidr" {
  description = "Cluster pod CIDR."
  type        = string
  default     = "10.20.0.0/16"
}

variable "service_cidr" {
  description = "Cluster service CIDR."
  type        = string
  default     = "10.21.0.0/16"
}

variable "api_port" {
  description = "Host loopback port for the Kubernetes API."
  type        = number
  default     = 6443
}

variable "http_port" {
  description = "Host loopback port mapped to the ingress controller on :80."
  type        = number
  default     = 8080
}

variable "https_port" {
  description = "Host loopback port mapped to the ingress controller on :443."
  type        = number
  default     = 8443
}

variable "cni" {
  description = "flannel (k3s default) or cilium (flannel and the embedded network-policy controller are disabled; install Cilium with scripts/cilium.sh)."
  type        = string
  default     = "flannel"

  validation {
    condition     = contains(["flannel", "cilium"], var.cni)
    error_message = "cni must be flannel or cilium."
  }
}

variable "extra_server_args" {
  description = "Additional k3s server flags."
  type        = list(string)
  default     = []
}
