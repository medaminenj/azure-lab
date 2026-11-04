output "resource_group" {
  value = azurerm_resource_group.lab.name
}

output "acr_login_server" {
  value = azurerm_container_registry.acr.login_server
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.aks.name
}

output "key_vault_name" {
  value = azurerm_key_vault.kv.name
}

output "kv_client_id" {
  description = "Client ID of the identity used by the Key Vault CSI provider"
  value       = azurerm_kubernetes_cluster.aks.key_vault_secrets_provider[0].secret_identity[0].client_id
}

output "tenant_id" {
  value = data.azurerm_client_config.me.tenant_id
}
