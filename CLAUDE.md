# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

POC for Azure Monitor, Log Analytics, and Application Insights alerting. Two simulators generate realistic failures on a Windows VM, monitored via Azure's logging and alerting stack.

- **PowerShell Simulator**: DB-to-DB sync (`dbo.Accounts` on `sqlprod-east-01` → `dbo.Accounts` on `sqlprod-west-01`). Mock SQL errors with real error numbers on both source query and target write sides.
- **Node.js Simulator**: SQL-to-Salesforce sync (`dbo.Contacts` → SF `Contact`). Mock SQL client + real HTTP calls to a mock Salesforce API returning real status codes.

Both simulators retry transient errors (deadlock 1205, timeout -2, snapshot isolation 3960, HTTP 429/503) up to 3 times, then escalate from warning to error. Event IDs (eventcreate limits to 1-1000): 100=start, 101=success, 201=source error, 202=target error, 301=retryable warning. AMA/DCR collects events into Log Analytics, where KQL alert rules trigger email notifications (errors: threshold >0, warnings: threshold >5).

## Task Tracking

Use `bd` (beads) for ALL task tracking. Do NOT use TodoWrite, TaskCreate, or markdown files.

```bash
bd ready                              # Find unblocked work
bd create "Title" --type=task         # Create issue
bd update <id> --status=in_progress   # Claim work
bd close <id>                         # Complete work
```

## Commands

### Terraform
```bash
cd terraform
terraform init
terraform plan -out=tfplan
terraform apply tfplan
terraform output application_insights_connection_string
```

### Mock Salesforce API (poc-mock-api/)
```bash
cd poc-mock-api
npm install
npm start                          # default 30% failure rate on port 3001
npm start -- --failure-rate=0.5    # custom failure rate
```

### Node.js Simulator (poc-node/)
```bash
cd poc-node
npm install
npm start -- --cycles 5 --delay 2000 --sql-failure-rate 0.15 --sf-base-url http://localhost:3001
npm run install-service  # register as Windows Service (admin required)
```

### PowerShell Simulator (poc-powershell/)
```powershell
# Admin required for event log writes
.\Install-EventSource.ps1                    # register event source (idempotent)
.\Start-IntegrationSync.ps1 -RunCount 5 -DelaySeconds 5 -FailureRate 0.3 -MaxRetries 3
```

## Architecture

```
Windows VM (Standard_B2s)
├── PowerShell Simulator ──► Windows Event Log (SQLSync-PowerShell)
├── Node.js Simulator ────► Windows Event Log (SQLSync-NodeApp)
│                      └──► Application Insights (custom events/metrics/exceptions)
└── AMA + DCR ────────────► Log Analytics Workspace
                                    │
                            KQL Alert Rules (5min eval, threshold > 0)
                                    │
                            Email Action Group
```

- **AMA/DCR** collects Application & System event logs at all severity levels
- **App Insights** linked to Log Analytics workspace; Node.js SDK sends custom telemetry
- **4 alert rules** in `terraform/alerting.tf`: PS errors, PS warnings, Node errors, Node warnings

## Key Files

| Purpose | Path |
|---------|------|
| VM + networking | `terraform/main.tf` |
| Log Analytics, App Insights, AMA, DCR | `terraform/monitoring.tf` |
| Alert rules + action group | `terraform/alerting.tf` |
| Variables (subscription, VM size, email) | `terraform/variables.tf` |
| VM bootstrap (installs tools, clones repo) | `terraform/setup-vm.ps1` |
| Node.js entry point | `poc-node/src/index.js` |
| Sync cycle simulation logic (with retry) | `poc-node/src/integration-sim.js` |
| Mock SQL client (real error numbers) | `poc-node/src/sql-client.js` |
| Salesforce HTTP client (real status codes) | `poc-node/src/sf-client.js` |
| App Insights telemetry wrapper | `poc-node/src/appinsights.js` |
| Windows Event Log writer | `poc-node/src/event-logger.js` |
| Mock Salesforce API server | `poc-mock-api/src/server.js` |
| PowerShell DB-to-DB sync simulator | `poc-powershell/Start-IntegrationSync.ps1` |

## Terraform Details

- **Providers**: azurerm ~> 4.0, azapi ~> 2.0
- **azapi used for NIC creation** to satisfy Azure Policy requiring NSG on NIC
- VM uses system-assigned managed identity
- `terraform.tfvars` contains secrets (subscription_id, admin_password, alert_email) — never commit

## Conventions

- **Linter**: Use Biome, not ESLint
- **Event sources**: `SQLSync-PowerShell` (registered via .NET API) and `SQLSync-NodeApp` (registered via eventcreate) — different registry mechanisms
- **Simulators are stateless**: each cycle generates synthetic data, no real SQL connection
- **Retry pattern**: transient errors (deadlock, timeout, 429, 503, snapshot isolation) retry up to 3x then escalate warning → error
- **Mock Salesforce API**: must be running on port 3001 before starting Node simulator
- **Timestamps**: ISO 8601 UTC throughout
- **Node.js App Insights**: no-op mode when `APPLICATIONINSIGHTS_CONNECTION_STRING` env var is unset
