terraform {
  backend "azurerm" {
    resource_group_name  = "dt-series-tfstate-rg"
    storage_account_name = "dtseriestfstatedev"
    container_name       = "tfstate"
    key                  = "dev.terraform.tfstate"
  }
}
