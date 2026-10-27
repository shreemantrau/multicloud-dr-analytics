resource "azurerm_container_registry" "main" {
  name                = "acrproj3"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "Basic"
}

resource "azurerm_role_assignment" "acr_pull_app" {
  principal_id         = azurerm_linux_web_app.app.identity[0].principal_id
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
}

resource "azurerm_role_assignment" "acr_pull_web" {
  principal_id         = azurerm_linux_web_app.web.identity[0].principal_id
  scope                = azurerm_container_registry.main.id
  role_definition_name = "AcrPull"
}