# Azure dev environment: AKS + Key Vault KMS + workload identity + Cilium dataplane.
# Not deployed by default; CI validates and scans it, and plans when Azure OIDC is configured.

terraform {
  required_version = ">= 1.6.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }

  backend "azurerm" {
    key              = "azure-dev.terraform.tfstate"
    use_oidc         = true
    use_azuread_auth = true # Entra ID data-plane auth, no storage account keys
    # resource_group_name, storage_account_name, container_name via -backend-config
  }
}

provider "azurerm" {
  features {
    key_vault {
      purge_soft_delete_on_destroy = false # purge protection is on; never try to purge
    }
  }
  use_oidc = true
  # subscription_id / tenant_id / client_id come from ARM_* environment variables
}

variable "admin_cidrs" {
  description = "Office/VPN egress CIDRs allowed to the API server and Key Vault."
  type        = list(string)
  default     = ["203.0.113.0/24"] # TEST-NET-3 documentation range; replace
}

variable "admin_group_object_ids" {
  type    = list(string)
  default = []
}

module "aks" {
  source = "../../modules/azure-aks"

  name                   = "labdev"
  location               = "westeurope"
  sku_tier               = "Free"
  apps_spot              = true
  admin_cidrs            = var.admin_cidrs
  admin_group_object_ids = var.admin_group_object_ids
  tags = {
    project     = "enterprise-devsecops-lab"
    environment = "dev"
    owner       = "platform-team"
    cost-center = "lab"
    managed-by  = "terraform"
  }
}

output "kubeconfig_command" {
  value = module.aks.kubeconfig_command
}

output "app_client_id" {
  value = module.aks.app_client_id
}
