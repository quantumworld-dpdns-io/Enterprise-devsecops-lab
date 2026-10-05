# AWS dev environment: EKS with KMS-encrypted Secrets, IAM access entries and Pod Identity.
# Not deployed by default. CI runs fmt/validate/lint/scan on every change and `plan` only
# when AWS OIDC is configured (vars.AWS_PLAN_ROLE_ARN); see docs/cloud.md.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
  }

  # Native S3 locking (no DynamoDB table needed with Terraform >= 1.10).
  backend "s3" {
    key          = "aws-dev/terraform.tfstate"
    encrypt      = true
    use_lockfile = true
    # bucket and region come from -backend-config=backend.hcl (kept out of the repo)
  }
}

provider "aws" {
  region = var.region

  default_tags {
    tags = {
      project     = "enterprise-devsecops-lab"
      environment = "dev"
      owner       = var.owner
      cost-center = var.cost_center
      managed-by  = "terraform"
    }
  }
}

variable "region" {
  type    = string
  default = "eu-central-1"
}

variable "owner" {
  type    = string
  default = "platform-team"
}

variable "cost_center" {
  type    = string
  default = "lab"
}

variable "admin_role_arns" {
  type    = list(string)
  default = []
}

variable "public_access_cidrs" {
  description = "Office/VPN egress CIDRs for the API endpoint; empty = private endpoint only."
  type        = list(string)
  default     = []
}

module "eks" {
  source = "../../modules/aws-eks"

  name                = "lab-dev"
  azs                 = ["${var.region}a", "${var.region}b", "${var.region}c"]
  single_nat_gateway  = true # dev: one NAT; prod sets false for zone redundancy
  node_capacity_type  = "SPOT"
  node_instance_types = ["m7i.large", "m6i.large", "m5.large"]
  admin_role_arns     = var.admin_role_arns
  public_access_cidrs = var.public_access_cidrs
}

output "kubeconfig_command" {
  value = module.eks.kubeconfig_command
}

output "app_role_arn" {
  value = module.eks.app_role_arn
}
