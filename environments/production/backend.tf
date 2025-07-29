terraform {
  backend "azurerm" {
    resource_group_name  = "dt-series-tfstate-rg"
    storage_account_name = "dtseriestfstateprod"
    container_name       = "tfstate"
    key                  = "production.terraform.tfstate"
  }
}
