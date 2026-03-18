# =============================================================================
# Action Group - Email Notification
# =============================================================================

resource "azurerm_monitor_action_group" "email" {
  name                = "ag-email-alerts"
  resource_group_name = azurerm_resource_group.main.name
  short_name          = "EmailAlert"
  tags                = var.tags

  email_receiver {
    name          = "primary-email"
    email_address = var.alert_email
  }
}

# =============================================================================
# Log Search Alert - Error Level Events from SQLSync Sources
# =============================================================================

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "error_events" {
  name                = "alert-sqlsync-error-events"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  description         = "Fires when Error-level Windows Event Log entries from SQLSync-PowerShell or SQLSync-NodeApp are detected."
  tags                = var.tags

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 1
  enabled              = true

  criteria {
    query = <<-KQL
      Event
      | where EventLevelName == "Error"
      | where Source in ("SQLSync-PowerShell", "SQLSync-NodeApp")
      | project TimeGenerated, Source, EventID, RenderedDescription, Computer
    KQL

    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.email.id]
  }
}

# =============================================================================
# Log Search Alert - Warning Level Events from SQLSync Sources
# =============================================================================

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "warning_events" {
  name                = "alert-sqlsync-warning-events"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  description         = "Fires when Warning-level Windows Event Log entries from SQLSync-PowerShell or SQLSync-NodeApp are detected."
  tags                = var.tags

  evaluation_frequency = "PT5M"
  window_duration      = "PT5M"
  scopes               = [azurerm_log_analytics_workspace.main.id]
  severity             = 2
  enabled              = true

  criteria {
    query = <<-KQL
      Event
      | where EventLevelName == "Warning"
      | where Source in ("SQLSync-PowerShell", "SQLSync-NodeApp")
      | project TimeGenerated, Source, EventID, RenderedDescription, Computer
    KQL

    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 0

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.email.id]
  }
}
