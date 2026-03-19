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
# SQLSync-PowerShell Alerts
# =============================================================================

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "ps_error_events" {
  name                = "alert-sqlsync-powershell-errors"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  description         = "Error events from SQLSync-PowerShell (SQL Server -> Salesforce Account sync)"
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
      | where Source == "SQLSync-PowerShell"
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

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "ps_warning_events" {
  name                = "alert-sqlsync-powershell-warnings"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  description         = "Sustained warnings from SQLSync-PowerShell (repeated deadlocks, timeouts, rate limits suggest systemic issues even if individual retries succeed)"
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
      | where Source == "SQLSync-PowerShell"
      | project TimeGenerated, Source, EventID, RenderedDescription, Computer
    KQL

    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 5

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
# SQLSync-NodeApp Alerts
# =============================================================================

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "node_error_events" {
  name                = "alert-sqlsync-nodeapp-errors"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  description         = "Error events from SQLSync-NodeApp (SQL Server -> Salesforce Contact sync)"
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
      | where Source == "SQLSync-NodeApp"
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

resource "azurerm_monitor_scheduled_query_rules_alert_v2" "node_warning_events" {
  name                = "alert-sqlsync-nodeapp-warnings"
  location            = azurerm_resource_group.main.location
  resource_group_name = azurerm_resource_group.main.name
  description         = "Sustained warnings from SQLSync-NodeApp (repeated rate limits, deadlocks, timeouts suggest systemic issues even if individual retries succeed)"
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
      | where Source == "SQLSync-NodeApp"
      | project TimeGenerated, Source, EventID, RenderedDescription, Computer
    KQL

    time_aggregation_method = "Count"
    operator                = "GreaterThan"
    threshold               = 5

    failing_periods {
      minimum_failing_periods_to_trigger_alert = 1
      number_of_evaluation_periods             = 1
    }
  }

  action {
    action_groups = [azurerm_monitor_action_group.email.id]
  }
}
