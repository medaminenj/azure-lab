# ===========================================================================
#  azure-lab
#  Terraform -> Resource Group + ACR + AKS + Key Vault + Log Analytics + Alert
#  Deploy a tiny web app with Helm, read a secret from Key Vault, then destroy.
# ===========================================================================

data "azurerm_client_config" "me" {}

resource "random_string" "s" {
  length  = 5
  lower   = true
  upper   = false
  numeric = true
  special = false
}

locals {
  tags = {
    project = "azure-lab"
    owner   = var.owner
  }
}

# ---------------------------------------------------------------------------
# Resource group: the folder that holds every resource of this lab.
# Deleting it deletes everything inside it.
# ---------------------------------------------------------------------------
resource "azurerm_resource_group" "lab" {
  name     = "rg-azure-lab"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------------------
# Log Analytics workspace: the database where the cluster ships its logs and
# metrics. Azure Monitor / Container Insights reads from here.
# (Equivalent of the Elasticsearch index in your ELK stack.)
# ---------------------------------------------------------------------------
resource "azurerm_log_analytics_workspace" "law" {
  name                = "law-azure-lab"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# Azure Container Registry: private Docker registry for your images.
# (Equivalent of Docker Hub, but inside your subscription.)
# ---------------------------------------------------------------------------
resource "azurerm_container_registry" "acr" {
  name                = "acrlab${random_string.s.result}"
  resource_group_name = azurerm_resource_group.lab.name
  location            = azurerm_resource_group.lab.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

# ---------------------------------------------------------------------------
# AKS: managed Kubernetes. Azure runs the control plane for free; you only pay
# for the worker nodes. Identity = the cluster's own managed identity, so no
# credentials are stored anywhere.
# ---------------------------------------------------------------------------
resource "azurerm_kubernetes_cluster" "aks" {
  name                = "aks-azure-lab"
  location            = azurerm_resource_group.lab.location
  resource_group_name = azurerm_resource_group.lab.name
  dns_prefix          = "azlab"

  default_node_pool {
    name       = "system"
    node_count = 1
    vm_size    = var.node_vm_size
  }

  identity {
    type = "SystemAssigned"
  }

  # Ship container logs + metrics to Log Analytics (Container Insights).
  oms_agent {
    log_analytics_workspace_id = azurerm_log_analytics_workspace.law.id
  }

  # Installs the Secrets Store CSI driver + Azure Key Vault provider add-on.
  # This is what lets a pod mount a Key Vault secret as a file.
  key_vault_secrets_provider {
    secret_rotation_enabled = true
  }

  tags = local.tags
}

# Allow the cluster's kubelet identity to pull images from ACR
# (so the Deployment can use acrlabXXXXX.azurecr.io/web:v1 without a pull secret).
resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                = azurerm_container_registry.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_kubernetes_cluster.aks.kubelet_identity[0].object_id
}

# ---------------------------------------------------------------------------
# Key Vault: managed secret store. RBAC mode = permissions are granted with
# Azure roles, not with legacy access policies.
# ---------------------------------------------------------------------------
resource "azurerm_key_vault" "kv" {
  name                       = "kv-azlab-${random_string.s.result}"
  location                   = azurerm_resource_group.lab.location
  resource_group_name        = azurerm_resource_group.lab.name
  tenant_id                  = data.azurerm_client_config.me.tenant_id
  sku_name                   = "standard"
  rbac_authorization_enabled = true
  tags                       = local.tags
}

# Let YOU write secrets in this vault (Terraform runs as you).
resource "azurerm_role_assignment" "me_secrets_officer" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets Officer"
  principal_id         = data.azurerm_client_config.me.object_id
}

# Let the AKS add-on identity READ secrets from this vault
# (this is the identity referenced by userAssignedIdentityID in spc.yaml).
resource "azurerm_role_assignment" "aks_kv_read" {
  scope                = azurerm_key_vault.kv.id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.aks.key_vault_secrets_provider[0].secret_identity[0].object_id
}

resource "azurerm_key_vault_secret" "message" {
  name         = "app-message"
  value        = "hello from Azure Key Vault"
  key_vault_id = azurerm_key_vault.kv.id

  # RBAC propagation can take a minute; don't create the secret before the role exists.
  depends_on = [azurerm_role_assignment.me_secrets_officer]
}

# ---------------------------------------------------------------------------
# Alerting: an action group (who to notify) + a metric alert (what to watch).
# ---------------------------------------------------------------------------
resource "azurerm_monitor_action_group" "mail" {
  name                = "ag-azure-lab"
  resource_group_name = azurerm_resource_group.lab.name
  short_name          = "azlab"
  tags                = local.tags

  email_receiver {
    name          = "owner"
    email_address = var.owner_email
  }
}

resource "azurerm_monitor_metric_alert" "node_cpu" {
  name                = "alert-aks-node-cpu"
  resource_group_name = azurerm_resource_group.lab.name
  scopes              = [azurerm_kubernetes_cluster.aks.id]
  description         = "Node CPU above ${var.alert_cpu_threshold}% for 5 minutes"
  severity            = 3
  frequency           = "PT1M"
  window_size         = "PT5M"
  tags                = local.tags

  criteria {
    metric_namespace = "Insights.container/nodes"
    metric_name      = "cpuUsagePercentage"
    aggregation      = "Average"
    operator         = "GreaterThan"
    threshold        = var.alert_cpu_threshold

    # Container Insights needs a few minutes to start emitting this metric.
    # Without this flag, Azure rejects the alert while the metric is still absent.
    skip_metric_validation = true
  }

  action {
    action_group_id = azurerm_monitor_action_group.mail.id
  }
}
