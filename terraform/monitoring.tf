# =============================================================================
# Log Analytics Workspace
# =============================================================================

resource "azurerm_log_analytics_workspace" "main" {
  name                = "law-monitoring-playground"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  sku                 = "PerGB2018"
  retention_in_days   = 30
  tags                = var.tags
}

# =============================================================================
# Application Insights (connected to Log Analytics Workspace)
# =============================================================================

resource "azurerm_application_insights" "main" {
  name                = "appi-monitoring-playground"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  workspace_id        = azurerm_log_analytics_workspace.main.id
  application_type    = "web"
  tags                = var.tags
}

# =============================================================================
# Azure Monitor Agent (AMA) - VM Extension
# =============================================================================

resource "azurerm_virtual_machine_extension" "ama" {
  name                       = "AzureMonitorWindowsAgent"
  virtual_machine_id         = azurerm_windows_virtual_machine.main.id
  publisher                  = "Microsoft.Azure.Monitor"
  type                       = "AzureMonitorWindowsAgent"
  type_handler_version       = "1.22"
  automatic_upgrade_enabled  = true
  auto_upgrade_minor_version = true
  tags                       = var.tags
}

# =============================================================================
# Custom Script Extension - VM Bootstrap (setup-vm.ps1)
# =============================================================================

resource "azurerm_virtual_machine_extension" "setup" {
  name                 = "SetupVMBootstrap"
  virtual_machine_id   = azurerm_windows_virtual_machine.main.id
  publisher            = "Microsoft.Compute"
  type                 = "CustomScriptExtension"
  type_handler_version = "1.10"
  tags                 = var.tags

  protected_settings = jsonencode({
    commandToExecute = "powershell -ExecutionPolicy Bypass -EncodedCommand ${textencodebase64(file("${path.module}/setup-vm.ps1"), "UTF-16LE")}"
  })

  depends_on = [
    azurerm_virtual_machine_extension.ama
  ]

  lifecycle {
    ignore_changes = [protected_settings]
  }
}

# =============================================================================
# Data Collection Rule (DCR) - Windows Event Logs
# =============================================================================

resource "azurerm_monitor_data_collection_rule" "windows_events" {
  name                = "dcr-windows-events"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  tags                = var.tags

  destinations {
    log_analytics {
      workspace_resource_id = azurerm_log_analytics_workspace.main.id
      name                  = "log-analytics-destination"
    }
  }

  data_flow {
    streams      = ["Microsoft-Event"]
    destinations = ["log-analytics-destination"]
  }

  data_sources {
    windows_event_log {
      streams = ["Microsoft-Event"]
      name    = "windows-event-logs"

      x_path_queries = [
        "Application!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=5)]]",
        "System!*[System[(Level=1 or Level=2 or Level=3 or Level=4 or Level=5)]]",
      ]
    }
  }
}

# =============================================================================
# DCR Association - Link the VM to the Data Collection Rule
# =============================================================================

resource "azurerm_monitor_data_collection_rule_association" "windows_events" {
  name                    = "dcra-vm-windows-events"
  target_resource_id      = azurerm_windows_virtual_machine.main.id
  data_collection_rule_id = azurerm_monitor_data_collection_rule.windows_events.id
  description             = "Association between the VM and the Windows Event Log DCR"

  depends_on = [
    azurerm_virtual_machine_extension.ama
  ]
}
