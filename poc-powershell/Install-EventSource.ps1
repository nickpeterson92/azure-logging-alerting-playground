#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Registers the "SQLSync-PowerShell" event source under the Windows Application event log.

.DESCRIPTION
    This script creates the event log source "SQLSync-PowerShell" in the Application log.
    It is idempotent - if the source already exists, it reports that and exits cleanly.
    Must be run as Administrator because creating event sources requires elevated privileges.

.EXAMPLE
    .\Install-EventSource.ps1
#>

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

$SourceName = 'SQLSync-PowerShell'
$LogName    = 'Application'

Write-Host "=============================================" -ForegroundColor Cyan
Write-Host " Event Source Installer - $SourceName"        -ForegroundColor Cyan
Write-Host "=============================================" -ForegroundColor Cyan
Write-Host ""

try {
    $sourceExists = [System.Diagnostics.EventLog]::SourceExists($SourceName)

    if ($sourceExists) {
        $existingLog = [System.Diagnostics.EventLog]::LogNameFromSourceName($SourceName, '.')
        Write-Host "[OK] Event source '$SourceName' already exists under log '$existingLog'." -ForegroundColor Green
        Write-Host "     No action required." -ForegroundColor Gray
    }
    else {
        Write-Host "[INFO] Event source '$SourceName' does not exist. Creating..." -ForegroundColor Yellow

        [System.Diagnostics.EventLog]::CreateEventSource($SourceName, $LogName)

        Write-Host "[OK] Event source '$SourceName' created under log '$LogName'." -ForegroundColor Green
        Write-Host ""
        Write-Host "[IMPORTANT] You may need to restart the machine or the Event Log service" -ForegroundColor Yellow
        Write-Host "            before the source becomes fully available." -ForegroundColor Yellow
    }
}
catch [System.Security.SecurityException] {
    Write-Error "Access denied. This script must be run as Administrator. Right-click PowerShell and select 'Run as Administrator', then retry."
    exit 1
}
catch {
    Write-Error "Failed to register event source: $_"
    exit 1
}

Write-Host ""
Write-Host "Done." -ForegroundColor Cyan
