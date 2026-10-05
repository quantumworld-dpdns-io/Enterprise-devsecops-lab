# AKS with Entra ID-only access, Key Vault KMS encryption of etcd, workload identity,
# Azure CNI Overlay powered by Cilium (eBPF dataplane + network policy) and Container Insights.

terraform {
  required_version = ">= 1.6.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
  }
}

data "azurerm_client_config" "current" {}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.name}"
  location = var.location
  tags     = var.tags
}

# ---------- network ----------
resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  address_space       = [var.vnet_cidr]
  tags                = var.tags
}

resource "azurerm_subnet" "nodes" {
  name                 = "snet-nodes"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [cidrsubnet(var.vnet_cidr, 4, 0)]
}

# Subnet-level NSG: HTTPS to load balancers from the internet, nothing else inbound from it.
# Pod-to-pod policy is enforced by Cilium inside the cluster.
resource "azurerm_network_security_group" "nodes" {
  name                = "nsg-${var.name}-nodes"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags

  security_rule {
    name                       = "allow-https-from-internet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_address_prefix      = "Internet"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "443"
  }

  security_rule {
    name                       = "deny-other-internet-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_address_prefix      = "Internet"
    source_port_range          = "*"
    destination_address_prefix = "*"
    destination_port_range     = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "nodes" {
  subnet_id                 = azurerm_subnet.nodes.id
  network_security_group_id = azurerm_network_security_group.nodes.id
}

# ---------- observability ----------
resource "azurerm_log_analytics_workspace" "this" {
  name                = "log-${var.name}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "PerGB2018"
  retention_in_days   = var.log_retention_days
  daily_quota_gb      = var.log_daily_quota_gb # FinOps guardrail: cap runaway ingestion
  tags                = var.tags
}

# ---------- identities ----------
resource "azurerm_user_assigned_identity" "cluster" {
  name                = "id-${var.name}-cluster"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags
}

# ---------- Key Vault + KMS key ----------
resource "azurerm_key_vault" "this" {
  #checkov:skip=CKV_AZURE_189:AKS KMS in Public network mode needs a reachable vault; the ACL is default-deny with admin CIDRs.
  #checkov:skip=CKV2_AZURE_32:Private endpoint is the production variant (key_vault_network_access = Private).
  name                       = substr(replace("kv-${var.name}-${random_string.kv.result}", "_", "-"), 0, 24)
  resource_group_name        = azurerm_resource_group.this.name
  location                   = azurerm_resource_group.this.location
  tenant_id                  = data.azurerm_client_config.current.tenant_id
  sku_name                   = "premium" # HSM-backed keys
  rbac_authorization_enabled = true      # Azure RBAC, not legacy access policies
  purge_protection_enabled   = true
  soft_delete_retention_days = 90

  # AKS KMS with key_vault_network_access = "Public" needs the vault reachable by the
  # AKS control plane; restrict data-plane access to the admin CIDRs. A fully private
  # setup uses a private endpoint plus key_vault_network_access = "Private".
  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
    ip_rules       = var.admin_cidrs
  }

  tags = var.tags
}

resource "random_string" "kv" {
  length  = 5
  upper   = false
  special = false
}

# The identity running Terraform needs to create keys; the cluster only needs to use them.
resource "azurerm_role_assignment" "deployer_crypto_officer" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Crypto Officer"
  principal_id         = data.azurerm_client_config.current.object_id
}

resource "azurerm_role_assignment" "cluster_crypto_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Crypto User"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

# Expiry is managed by rotation_policy below; a fixed expiration_date would drift on every plan.
# nosemgrep: terraform.azure.security.keyvault.keyvault-ensure-key-expires.keyvault-ensure-key-expires, terraform.azure.security.azure-key-no-expiration-date.azure-key-no-expiration-date
resource "azurerm_key_vault_key" "etcd" {
  #checkov:skip=CKV_AZURE_40:Expiry is managed by rotation_policy (expire_after P365D, auto-rotate 30 days before).
  name         = "aks-etcd-kms"
  key_vault_id = azurerm_key_vault.this.id
  key_type     = "RSA-HSM"
  key_size     = 2048
  key_opts     = ["encrypt", "decrypt", "wrapKey", "unwrapKey"]

  rotation_policy {
    automatic {
      time_before_expiry = "P30D"
    }
    expire_after         = "P365D"
    notify_before_expiry = "P29D"
  }

  depends_on = [azurerm_role_assignment.deployer_crypto_officer]
}

# The cluster identity must manage the node subnet (load balancers, NICs).
resource "azurerm_role_assignment" "cluster_network" {
  scope                = azurerm_subnet.nodes.id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.cluster.principal_id
}

# ---------- cluster ----------
resource "azurerm_kubernetes_cluster" "this" {
  #checkov:skip=CKV_AZURE_115:Private API is var.private_cluster (true for prod); dev uses authorized IP ranges and Entra-only auth.
  #checkov:skip=CKV_AZURE_170:SKU tier is var.sku_tier; Standard (SLA) for prod, Free for dev.
  #checkov:skip=CKV_AZURE_117:Host encryption covers temp and cache disks; a customer-managed disk encryption set is a prod add-on.
  #checkov:skip=CKV_AZURE_6:Authorized IP ranges come from the required admin_cidrs input.
  name                    = "aks-${var.name}"
  resource_group_name     = azurerm_resource_group.this.name
  location                = azurerm_resource_group.this.location
  dns_prefix              = var.name
  private_cluster_enabled = var.private_cluster
  kubernetes_version      = var.kubernetes_version
  sku_tier                = var.sku_tier

  automatic_upgrade_channel = "patch"
  node_os_upgrade_channel   = "NodeImage"

  # Entra ID is the only way in: no local admin kubeconfig to leak.
  local_account_disabled            = true
  role_based_access_control_enabled = true
  azure_active_directory_role_based_access_control {
    tenant_id              = data.azurerm_client_config.current.tenant_id
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  azure_policy_enabled      = true
  image_cleaner_enabled     = true

  api_server_access_profile {
    authorized_ip_ranges = var.admin_cidrs
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.cluster.id]
  }

  key_management_service {
    key_vault_key_id         = azurerm_key_vault_key.etcd.id
    key_vault_network_access = "Public"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    pod_cidr            = var.pod_cidr
    service_cidr        = var.service_cidr
    dns_service_ip      = cidrhost(var.service_cidr, 10)
    load_balancer_sku   = "standard"
    outbound_type       = "loadBalancer"
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_vm_size
    vnet_subnet_id               = azurerm_subnet.nodes.id
    zones                        = var.zones
    auto_scaling_enabled         = true
    min_count                    = 2
    max_count                    = 3
    only_critical_addons_enabled = true # system pool runs system pods only
    max_pods                     = 110
    os_disk_type                 = "Ephemeral" # OS disk on local cache: faster, no managed-disk cost
    os_sku                       = "AzureLinux"
    host_encryption_enabled      = var.host_encryption_enabled
    temporary_name_for_rotation  = "systemtmp"

    upgrade_settings {
      max_surge = "33%"
    }
  }

  oms_agent {
    log_analytics_workspace_id      = azurerm_log_analytics_workspace.this.id
    msi_auth_for_monitoring_enabled = true
  }

  tags = var.tags

  depends_on = [
    azurerm_role_assignment.cluster_crypto_user,
    azurerm_role_assignment.cluster_network,
  ]
}

resource "azurerm_kubernetes_cluster_node_pool" "apps" {
  name                    = "apps"
  kubernetes_cluster_id   = azurerm_kubernetes_cluster.this.id
  vm_size                 = var.apps_vm_size
  vnet_subnet_id          = azurerm_subnet.nodes.id
  zones                   = var.zones
  auto_scaling_enabled    = true
  min_count               = 1
  max_count               = 5
  max_pods                = 110
  os_disk_type            = "Ephemeral"
  priority                = var.apps_spot ? "Spot" : "Regular"
  eviction_policy         = var.apps_spot ? "Delete" : null
  spot_max_price          = var.apps_spot ? -1 : null
  os_sku                  = "AzureLinux"
  host_encryption_enabled = var.host_encryption_enabled
  node_labels             = { "lab.example/pool" = "apps" }
  tags                    = var.tags

  upgrade_settings {
    max_surge = "33%"
  }
}

# ---------- workload identity for the demo app ----------
resource "azurerm_user_assigned_identity" "app" {
  name                = "id-${var.name}-${var.app_service_account}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = var.tags
}

resource "azurerm_federated_identity_credential" "app" {
  name                = "k8s-${var.app_namespace}-${var.app_service_account}"
  resource_group_name = azurerm_resource_group.this.name
  parent_id           = azurerm_user_assigned_identity.app.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject             = "system:serviceaccount:${var.app_namespace}:${var.app_service_account}"
}

# The app may read secrets from the vault, nothing else.
resource "azurerm_role_assignment" "app_secrets_user" {
  scope                = azurerm_key_vault.this.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.app.principal_id
}
