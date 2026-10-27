resource "azurerm_resource_group" "main" {
  name     = "rg-project3-dr-analytics"
  location = "westus2"
}

resource "azurerm_virtual_network" "main" {
  name                = "vnet-p3-dr"
  resource_group_name = azurerm_resource_group.main.name
  location            = azurerm_resource_group.main.location
  address_space       = ["10.0.0.0/16"]
}
#---------------Subnets------------------
resource "azurerm_subnet" "web" {
  name                 = "snet_web"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.1.0/24"]
}

resource "azurerm_subnet" "app" {
  name                 = "snet_app"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.2.0/24"]
  delegation {
    name = "app-service-delegation"
    service_delegation {
      name = "Microsoft.Web/serverFarms"
    }
  }
}

resource "azurerm_subnet" "data" {
  name                 = "snet_data"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.3.0/24"]
}

resource "azurerm_subnet" "keyvault" {
  name                 = "snet_keyvault"
  resource_group_name  = azurerm_resource_group.main.name
  virtual_network_name = azurerm_virtual_network.main.name
  address_prefixes     = ["10.0.4.0/24"]
}

#------------NSG---------------------

resource "azurerm_network_security_group" "web" {
  name                = "nsg-web"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}


resource "azurerm_network_security_group" "app" {
  name                = "nsg-app"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}


resource "azurerm_network_security_group" "data" {
  name                = "nsg-data"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}


resource "azurerm_network_security_group" "keyvault" {
  name                = "nsg-keyvault"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
}


#-----------NSG Assocation-------------

resource "azurerm_subnet_network_security_group_association" "web" {
  network_security_group_id = azurerm_network_security_group.web.id
  subnet_id                 = azurerm_subnet.web.id
}

resource "azurerm_subnet_network_security_group_association" "app" {
  network_security_group_id = azurerm_network_security_group.app.id
  subnet_id                 = azurerm_subnet.app.id
}

resource "azurerm_subnet_network_security_group_association" "data" {
  network_security_group_id = azurerm_network_security_group.data.id
  subnet_id                 = azurerm_subnet.data.id
}

resource "azurerm_subnet_network_security_group_association" "keyvault" {
  network_security_group_id = azurerm_network_security_group.keyvault.id
  subnet_id                 = azurerm_subnet.keyvault.id
}

#--------------------------NSG RULES--------------------

resource "azurerm_network_security_rule" "web_inbound" {
  name                        = "allow-https-inbound"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "Internet"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.web.name
}

resource "azurerm_network_security_rule" "app_inbound" {
  name                        = "allow-web-to-app"
  priority                    = 100
  direction                   = "Inbound"
  access                      = "Allow"
  protocol                    = "Tcp"
  source_port_range           = "*"
  destination_port_range      = "5000" //flash communicates at 5000
  source_address_prefix       = "10.0.1.0/24"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.app.name
}

resource "azurerm_network_security_rule" "data_inbound" {
  name                        = "allow-app-to-data"
  priority                    = 100
  direction                   = "Inbound"
  protocol                    = "Tcp"
  access                      = "Allow"
  source_port_range           = "*"
  destination_port_range      = "1433"
  source_address_prefix       = "10.0.2.0/24"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.data.name
}

resource "azurerm_network_security_rule" "keyvault_inbound" {
  name                        = "allow-app-to-keyvault"
  priority                    = 100
  direction                   = "Inbound"
  protocol                    = "Tcp"
  access                      = "Allow"
  source_port_range           = "*"
  destination_port_range      = "443"
  source_address_prefix       = "10.0.2.0/24"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.keyvault.name
}

#full-proofing access to subnets so no other subnets can access data and keyvaults and app excpet for the ones that are intended

resource "azurerm_network_security_rule" "app_deny_all" {
  name                        = "deny-all-inbound"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.app.name
}

resource "azurerm_network_security_rule" "data_deny_all" {
  name                        = "deny-all-inbound"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.data.name
}

resource "azurerm_network_security_rule" "keyvault_deny_all" {
  name                        = "deny-all-inbound"
  priority                    = 4000
  direction                   = "Inbound"
  access                      = "Deny"
  protocol                    = "*"
  source_port_range           = "*"
  destination_port_range      = "*"
  source_address_prefix       = "*"
  destination_address_prefix  = "*"
  resource_group_name         = azurerm_resource_group.main.name
  network_security_group_name = azurerm_network_security_group.keyvault.name
}