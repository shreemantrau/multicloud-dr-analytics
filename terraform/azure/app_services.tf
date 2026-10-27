resource "azurerm_service_plan" "main" {
  name                = "asp_proj3"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  sku_name            = "B1"
  os_type             = "Linux"
}

resource "azurerm_linux_web_app" "web" {
  name                = "app-project3-web"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  service_plan_id     = azurerm_service_plan.main.id
  https_only          = false # Previously set to TRUE ... Redirects HTTP to HTTPS so traffic is always encrypted. Default is FALSE
  # Front Door reaches this origin over HTTP (the AWS ALB has no certificate), so the redirect to HTTPS would break its health probe. Default is FALSE

  identity {
    type = "SystemAssigned"
  }
  site_config {
    container_registry_use_managed_identity = true # Tells the app to pull images with its own identity (AcrPull) instead of a stored username and password
    application_stack {
      docker_registry_url = "https://${azurerm_container_registry.main.login_server}"
      docker_image_name   = "web-tier:v1"
    }
  }

  app_settings = {
    WEBSITES_PORT = "5000"                                                  # Port Flask listens on inside the container
    APP_URL       = "https://${azurerm_linux_web_app.app.default_hostname}" # Where web.py calls the app tier; built from the app's real hostname, so no typo risk
  }

}

resource "azurerm_linux_web_app" "app" {
  name                      = "app-project3-app"
  location                  = azurerm_resource_group.main.location
  resource_group_name       = azurerm_resource_group.main.name
  service_plan_id           = azurerm_service_plan.main.id
  https_only                = true                  # Redirects HTTP to HTTPS so traffic is always encrypted. Default is FALSE
  virtual_network_subnet_id = azurerm_subnet.app.id # acts like a pointer to access VNET. Traffic will flow through App Subnet and reach SQL AND KeyVault 
  identity {
    type = "SystemAssigned" # lets the app authenticate to ACR without stored credentials
  }
  site_config {
    vnet_route_all_enabled                  = true # Sends ALL outbound traffic through the VNet, not just private IP ranges, so lookups for privatelink names (SQL, Key Vault) use the private DNS zones and resolve to the private IPs
    container_registry_use_managed_identity = true # Tells the app to pull images with its own identity (AcrPull) instead of a stored username and password
    application_stack {
      docker_image_name   = "app-tier:v1" # Image and tag to run, pulled from the registry below
      docker_registry_url = "https://${azurerm_container_registry.main.login_server}"
    }
  }

  app_settings = {
    WEBSITES_PORT  = "5000"                                                # Tells App Service which port Flask listens on inside the container
    KEY_VAULT_NAME = azurerm_key_vault.main.name                           # Read by app.py to build the vault URL
    SQL_SERVER     = azurerm_mssql_server.main.fully_qualified_domain_name # sql-proj3-dr-analytics.database.windows.net
    SQL_DB         = azurerm_mssql_database.main.name
    SQL_USER       = "sqladmin"
  }
}
