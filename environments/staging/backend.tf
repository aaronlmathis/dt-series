terraform {
  backend "azurerm" {
    resource_group_name  = "dt-series-tfstate-rg"
    storage_account_name = "dtseriestfstatestaging"
    container_name       = "tfstate"
    key                  = "staging.terraform.tfstate"
  }
}
