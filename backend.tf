# ---------------------------------------------------------------------------
# Terraform + provider configuration, and the REMOTE STATE backend.
#
# The backend stores terraform.tfstate in an Azure Blob container instead of
# on your laptop. That is what makes CI/CD possible later (a GitLab runner
# has no disk between runs).
#
# Fill in the 3 values after you create the storage account in Step 2.
# See README.md -> "Bootstrap the state storage".
# ---------------------------------------------------------------------------

terraform {
  required_version = ">= 1.7"

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

  backend "azurerm" {
    subscription_id      = "7238caee-be16-4181-8f48-b3b1b805b922"
    resource_group_name  = "rg-tfstate"
    storage_account_name = "stazlabmaneji01" # <-- must match Step 2
    container_name       = "tfstate"
    key                  = "azure-lab.tfstate"
  }
}

provider "azurerm" {
  # azurerm 4.x no longer guesses the subscription: it must be explicit.
  # A subscription ID is not a secret, so it is safe in the repository.
  subscription_id = "7238caee-be16-4181-8f48-b3b1b805b922"
  features {}
}
