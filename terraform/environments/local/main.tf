# Local environment: a 3-node k3s cluster on the developer workstation or a CI runner.
# State stays local on purpose; see docs/deployment.md for the remote-state pattern.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    docker = {
      source  = "kreuzwerker/docker"
      version = "~> 3.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

# Uses DOCKER_HOST when set, otherwise the platform default socket / named pipe.
provider "docker" {}

module "cluster" {
  source = "../../modules/k3s-docker-cluster"

  cluster_name = var.cluster_name
  agent_count  = var.agent_count
  cni          = var.cni
  network_cidr = var.network_cidr
  api_port     = var.api_port
  http_port    = var.http_port
  https_port   = var.https_port
}

variable "cni" {
  type    = string
  default = "flannel"
}

variable "network_cidr" {
  type    = string
  default = "10.10.10.0/24"
}

variable "api_port" {
  type    = number
  default = 6443
}

variable "http_port" {
  type    = number
  default = 8080
}

variable "https_port" {
  type    = number
  default = 8443
}

variable "cluster_name" {
  type    = string
  default = "lab"
}

variable "agent_count" {
  type    = number
  default = 2
}

output "server_container" {
  value = module.cluster.server_container
}

output "node_containers" {
  value = module.cluster.node_containers
}

output "api_endpoint" {
  value = module.cluster.api_endpoint
}

output "ingress_https" {
  value = module.cluster.ingress_https
}
