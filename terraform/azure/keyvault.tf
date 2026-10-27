data "azurerm_client_config" "data" {

}

resource "azurerm_key_vault" "main" {
  location                      = azurerm_resource_group.main.location
  name                          = "kv-proj3-dr-analytics"
  resource_group_name           = azurerm_resource_group.main.name
  sku_name                      = "standard"
  tenant_id                     = data.azurerm_client_config.data.tenant_id
  public_network_access_enabled = false
  soft_delete_retention_days    = 7     # minimum allowed (default is 90)
  purge_protection_enabled      = false # lab setting; production would be trues
  rbac_authorization_enabled    = true  # default is flase and fails on the read at run time throwing 403
}

resource "azurerm_private_endpoint" "keyvault" {
  name                = "pe-keyvault-proj3"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  subnet_id           = azurerm_subnet.keyvault.id
  private_service_connection {
    is_manual_connection           = false
    name                           = "psc_keyvault"
    private_connection_resource_id = azurerm_key_vault.main.id
    subresource_names              = ["vault"]
  }
}

resource "azurerm_private_dns_zone" "keyvault_dns" {
  name                = "privatelink.vaultcore.azure.net"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_a_record" "keyvault" {
  //name = "kv-proj3-dr-analytics"
  name                = azurerm_key_vault.main.name
  resource_group_name = azurerm_resource_group.main.name
  ttl                 = 300
  zone_name           = azurerm_private_dns_zone.keyvault_dns.name
  records             = [azurerm_private_endpoint.keyvault.private_service_connection[0].private_ip_address]
}

resource "azurerm_private_dns_zone_virtual_network_link" "keyvault" {
  name                  = "keyvault-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  private_dns_zone_name = azurerm_private_dns_zone.keyvault_dns.name
  virtual_network_id    = azurerm_virtual_network.main.id
}

resource "azurerm_role_assignment" "rbac-app" {
  principal_id = azurerm_linux_web_app.app.identity[0].principal_id
  scope        = azurerm_key_vault.main.id
  // role_definition_name = "Key Vault Secrets User" # Can read write and delete secrets 
  role_definition_name = "Key Vault Secrets User" # read secrets only (least privilege)
}

resource "azurerm_role_assignment" "me_kv_officer" {
  principal_id         = data.azurerm_client_config.data.object_id # your own identity
  scope                = azurerm_key_vault.main.id
  role_definition_name = "Key Vault Secrets Officer" # create and manage secrets
}