resource "azurerm_mssql_server" "main" {
  name                          = "sql-proj3-dr-analytics"
  location                      = azurerm_resource_group.main.location
  resource_group_name           = azurerm_resource_group.main.name
  version                       = "12.0"
  administrator_login           = "sqladmin"
  administrator_login_password  = var.sql_password
  minimum_tls_version           = "1.2" # Rejects clients using TLS 1.0/1.1, which have known weaknesses; only encrypted connections using TLS 1.2 or newer are accepted
  public_network_access_enabled = false
}

resource "azurerm_mssql_database" "main" {
  name                 = "proj3-dr-analytics"
  server_id            = azurerm_mssql_server.main.id
  sku_name             = "Basic"
  max_size_gb          = 2
  storage_account_type = "Local" #Backups default to geo-redundant storage, which costs extra; local is plenty for a lab
}

resource "azurerm_private_endpoint" "sql" {
  name                = "pe-sql-proj3"
  subnet_id           = azurerm_subnet.data.id
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location

  private_service_connection {
    name                           = "psc-sql"
    is_manual_connection           = false
    private_connection_resource_id = azurerm_mssql_server.main.id //private endpoint connectes to what?
    subresource_names              = ["sqlServer"]                # Which door on the SQL server the endpoint opens: "sqlServer" is the SQL connection (port 1433); every database on this server uses it
  }
}

resource "azurerm_private_dns_zone" "sql_dns" {
  name                = "privatelink.database.windows.net"
  resource_group_name = azurerm_resource_group.main.name
}

resource "azurerm_private_dns_a_record" "sql" {
  name                = "sql-proj3-dr-analytics" #sql server name
  resource_group_name = azurerm_resource_group.main.name
  zone_name           = azurerm_private_dns_zone.sql_dns.name
  records             = [azurerm_private_endpoint.sql.private_service_connection[0].private_ip_address]
  ttl                 = 300
}

resource "azurerm_private_dns_zone_virtual_network_link" "sql_dns_link" {
  name                  = "sql-dns-link"
  resource_group_name   = azurerm_resource_group.main.name
  virtual_network_id    = azurerm_virtual_network.main.id
  private_dns_zone_name = azurerm_private_dns_zone.sql_dns.name

}