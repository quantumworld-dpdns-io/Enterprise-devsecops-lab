# GitHub Actions -> Azure without client secrets: a user-assigned managed identity
# trusts GitHub's OIDC tokens through federated identity credentials.
#   plan identity : Reader on the subscription, any PR / branch of the repo
#   apply identity: Contributor on one resource group, protected environment only

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
  }
}

variable "repository" {
  description = "owner/repo."
  type        = string
}

variable "apply_environment" {
  description = "GitHub environment with required reviewers."
  type        = string
  default     = "production"
}

variable "location" {
  type    = string
  default = "westeurope"
}

variable "apply_scope_resource_group_id" {
  description = "Resource group the apply identity may change."
  type        = string
}

variable "state_storage_account_id" {
  description = "Storage account holding Terraform state (blob data access for both identities)."
  type        = string
}

data "azurerm_subscription" "current" {}

resource "azurerm_resource_group" "ci" {
  name     = "rg-github-ci-identities"
  location = var.location
}

resource "azurerm_user_assigned_identity" "plan" {
  name                = "id-github-terraform-plan"
  resource_group_name = azurerm_resource_group.ci.name
  location            = azurerm_resource_group.ci.location
}

resource "azurerm_user_assigned_identity" "apply" {
  name                = "id-github-terraform-apply"
  resource_group_name = azurerm_resource_group.ci.name
  location            = azurerm_resource_group.ci.location
}

resource "azurerm_federated_identity_credential" "plan_pr" {
  name                = "github-pull-request"
  resource_group_name = azurerm_resource_group.ci.name
  parent_id           = azurerm_user_assigned_identity.plan.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.repository}:pull_request"
}

resource "azurerm_federated_identity_credential" "plan_main" {
  name                = "github-main"
  resource_group_name = azurerm_resource_group.ci.name
  parent_id           = azurerm_user_assigned_identity.plan.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.repository}:ref:refs/heads/main"
}

resource "azurerm_federated_identity_credential" "apply" {
  name                = "github-environment-${var.apply_environment}"
  resource_group_name = azurerm_resource_group.ci.name
  parent_id           = azurerm_user_assigned_identity.apply.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.repository}:environment:${var.apply_environment}"
}

resource "azurerm_role_assignment" "plan_reader" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
}

resource "azurerm_role_assignment" "apply_contributor" {
  scope                = var.apply_scope_resource_group_id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.apply.principal_id
}

resource "azurerm_role_assignment" "state_access" {
  for_each             = { plan = azurerm_user_assigned_identity.plan.principal_id, apply = azurerm_user_assigned_identity.apply.principal_id }
  scope                = var.state_storage_account_id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = each.value
}

output "plan_client_id" {
  value = azurerm_user_assigned_identity.plan.client_id
}

output "apply_client_id" {
  value = azurerm_user_assigned_identity.apply.client_id
}
