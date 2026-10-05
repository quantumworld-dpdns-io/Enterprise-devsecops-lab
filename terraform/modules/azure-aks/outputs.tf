output "cluster_name" {
  description = "AKS cluster name."
  value       = azurerm_kubernetes_cluster.this.name
}

output "resource_group" {
  description = "Resource group."
  value       = azurerm_resource_group.this.name
}

output "oidc_issuer_url" {
  description = "Cluster OIDC issuer for workload identity federation."
  value       = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "app_client_id" {
  description = "Client ID to put on the demo-app service account annotation azure.workload.identity/client-id."
  value       = azurerm_user_assigned_identity.app.client_id
}

output "key_vault_uri" {
  description = "Key Vault URI."
  value       = azurerm_key_vault.this.vault_uri
}

output "kubeconfig_command" {
  description = "Fetch an Entra ID kubeconfig (then kubelogin convert-kubeconfig -l azurecli)."
  value       = "az aks get-credentials -g ${azurerm_resource_group.this.name} -n ${azurerm_kubernetes_cluster.this.name}"
}
