output "URI" {
  value = var.runtime_version=="18-lts"?"https://${azurerm_linux_web_app.webnode[0].default_hostname}" :"https://${azurerm_linux_web_app.webpython[0].default_hostname}"
}

output "IDENTITY_PRINCIPAL_ID" {
  value     = var.runtime_version=="18-lts"?(length(azurerm_linux_web_app.webnode[0].identity) == 0 ? "" : azurerm_linux_web_app.webnode[0].identity.0.principal_id):length(azurerm_linux_web_app.webpython[0].identity) == 0 ? "" : azurerm_linux_web_app.webpython[0].identity.0.principal_id
  sensitive = true
}