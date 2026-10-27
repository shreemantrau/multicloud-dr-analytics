// Origins live in different clouds with separate state, so their addresses come in as variables.
variable "azure_origin_host" {
  type = string
}

variable "aws_origin_host" {
  type = string
}

// ---------- Front Door: profile and endpoint ----------
// The profile is the Front Door instance; the endpoint is the public hostname clients call.
resource "azurerm_cdn_frontdoor_profile" "main" {
  name                = "fd-p3-dr"
  resource_group_name = azurerm_resource_group.main.name
  sku_name            = "Standard_AzureFrontDoor"
}

resource "azurerm_cdn_frontdoor_endpoint" "main" {
  name                     = "p3-dr"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id
}

// ---------- Origin group: the backends and how to judge their health ----------
resource "azurerm_cdn_frontdoor_origin_group" "main" {
  name                     = "og-p3-dr"
  cdn_frontdoor_profile_id = azurerm_cdn_frontdoor_profile.main.id

  // Small sample window so a failed origin is taken out after a couple of probes, not a dozen.
  load_balancing {
    sample_size                 = 2
    successful_samples_required = 1
  }

  // Front Door probes /health on every origin; an origin that fails is taken out of rotation.
  health_probe {
    path                = "/health"
    protocol            = "Http"
    request_type        = "GET"
    interval_in_seconds = 5
  }
}

// ---------- Origins: priority decides who gets traffic ----------
// Lower priority number = preferred. AWS only receives traffic when Azure is unhealthy.
resource "azurerm_cdn_frontdoor_origin" "azure" {
  name                           = "azure-primary"
  cdn_frontdoor_origin_group_id  = azurerm_cdn_frontdoor_origin_group.main.id
  enabled                        = true
  host_name                      = var.azure_origin_host
  origin_host_header             = var.azure_origin_host
  priority                       = 1
  weight                         = 1000
  certificate_name_check_enabled = true
}

resource "azurerm_cdn_frontdoor_origin" "aws" {
  name                          = "aws-failover"
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  enabled                       = true
  host_name                     = var.aws_origin_host
  origin_host_header            = var.aws_origin_host
  priority                      = 2
  weight                        = 1000
  // The ALB has no TLS certificate, so there is no name to check.
  certificate_name_check_enabled = false
}

// ---------- Route: connects the endpoint to the origin group ----------
resource "azurerm_cdn_frontdoor_route" "main" {
  name                          = "route-p3-dr"
  cdn_frontdoor_endpoint_id     = azurerm_cdn_frontdoor_endpoint.main.id
  cdn_frontdoor_origin_group_id = azurerm_cdn_frontdoor_origin_group.main.id
  cdn_frontdoor_origin_ids = [
    azurerm_cdn_frontdoor_origin.azure.id,
    azurerm_cdn_frontdoor_origin.aws.id,
  ]

  patterns_to_match      = ["/*"]
  supported_protocols    = ["Http", "Https"]
  https_redirect_enabled = false
  // HTTP to the origins, because the AWS ALB only listens on port 80.
  forwarding_protocol    = "HttpOnly"
  link_to_default_domain = true
}

// Prints the public Front Door URL after apply, so we can curl it and run the failover drill.
output "frontdoor_url" {
  value = "http://${azurerm_cdn_frontdoor_endpoint.main.host_name}"
}
