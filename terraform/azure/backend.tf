terraform {
  backend "azurerm" {
    resource_group_name  = "rg-project3-dr-analytics"
    storage_account_name = "stp3tfstate27637"
    container_name       = "tfstate"          # container that holds the state file
    key                  = "project3.tfstate" # state file name inside the container
    use_azuread_auth     = true               # use your az login instead of a storage key 
  }
}