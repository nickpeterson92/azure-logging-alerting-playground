output "vm_public_ip_address" {
  description = "Public IP address of the monitoring VM"
  value       = azurerm_public_ip.main.ip_address
}

output "application_insights_instrumentation_key" {
  description = "Instrumentation key for Application Insights"
  value       = azurerm_application_insights.main.instrumentation_key
  sensitive   = true
}

output "application_insights_connection_string" {
  description = "Connection string for Application Insights"
  value       = azurerm_application_insights.main.connection_string
  sensitive   = true
}

output "log_analytics_workspace_id" {
  description = "ID of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.id
}

output "log_analytics_workspace_workspace_id" {
  description = "Workspace ID (GUID) of the Log Analytics Workspace"
  value       = azurerm_log_analytics_workspace.main.workspace_id
}

output "resource_group_name" {
  description = "Name of the resource group"
  value       = azurerm_resource_group.main.name
}

output "vm_name" {
  description = "Name of the Windows VM"
  value       = azurerm_windows_virtual_machine.main.name
}
