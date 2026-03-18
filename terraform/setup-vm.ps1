# =============================================================================
# setup-vm.ps1
# VM bootstrap script for the Azure Monitoring Playground
#
# This script:
#   1. Enables unrestricted PowerShell script execution policy
#   2. Installs Chocolatey package manager
#   3. Installs Node.js LTS via Chocolatey
#   4. Creates C:\POC working directory
#   5. Installs the node-windows npm package globally
#   6. Registers custom Windows Event Log sources
# =============================================================================

# Note: When run via CustomScriptExtension, this executes as SYSTEM (admin).
# When running manually, launch PowerShell as Administrator.

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Monitoring Playground VM Setup Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# -----------------------------------------------------------------------------
# 1. Set PowerShell Execution Policy
# -----------------------------------------------------------------------------
Write-Host "`n[1/9] Setting PowerShell execution policy to RemoteSigned..." -ForegroundColor Yellow
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction SilentlyContinue
    Write-Host "  Execution policy set to RemoteSigned." -ForegroundColor Green
} catch {
    Write-Host "  Execution policy not changed (GPO override in effect). Current policy: $(Get-ExecutionPolicy). Continuing." -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# 2. Install Chocolatey
# -----------------------------------------------------------------------------
Write-Host "`n[2/9] Installing Chocolatey package manager..." -ForegroundColor Yellow

if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))

    # Refresh the PATH so choco is available immediately
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Host "  Chocolatey installed successfully." -ForegroundColor Green
} else {
    Write-Host "  Chocolatey is already installed." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 3. Install Git and Node.js LTS via Chocolatey
# -----------------------------------------------------------------------------
Write-Host "`n[3/9] Installing Git..." -ForegroundColor Yellow

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    choco install git -y --no-progress
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Host "  Git installed: $(git --version)" -ForegroundColor Green
} else {
    Write-Host "  Git is already installed: $(git --version)" -ForegroundColor Green
}

Write-Host "`n[4/9] Installing Node.js LTS..." -ForegroundColor Yellow

if (!(Get-Command node -ErrorAction SilentlyContinue)) {
    choco install nodejs-lts -y --no-progress
    # Refresh PATH to pick up node and npm
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
    Write-Host "  Node.js installed: $(node --version)" -ForegroundColor Green
} else {
    Write-Host "  Node.js is already installed: $(node --version)" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 4. Create C:\POC directory
# -----------------------------------------------------------------------------
Write-Host "`n[5/9] Creating C:\POC directory..." -ForegroundColor Yellow

if (!(Test-Path "C:\POC")) {
    New-Item -ItemType Directory -Path "C:\POC" -Force | Out-Null
    Write-Host "  C:\POC directory created." -ForegroundColor Green
} else {
    Write-Host "  C:\POC directory already exists." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 5. Clone repo and install Node dependencies
# -----------------------------------------------------------------------------
Write-Host "`n[6/9] Cloning repo to C:\POC..." -ForegroundColor Yellow

$repoDir = "C:\POC\azure-logging-alerting-playground"
if (!(Test-Path "$repoDir\.git")) {
    git clone https://github.com/nickpeterson92/azure-logging-alerting-playground.git $repoDir
    Write-Host "  Repo cloned to $repoDir" -ForegroundColor Green
} else {
    git -C $repoDir pull
    Write-Host "  Repo already exists, pulled latest." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 6. Install npm dependencies for poc-node
# -----------------------------------------------------------------------------
Write-Host "`n[7/9] Installing npm dependencies for poc-node..." -ForegroundColor Yellow

Push-Location "$repoDir\poc-node"
npm install
Pop-Location
Write-Host "  npm dependencies installed." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 7. Install node-windows globally via npm
# -----------------------------------------------------------------------------
Write-Host "`n[8/9] Installing node-windows npm package globally..." -ForegroundColor Yellow

npm install -g node-windows
Write-Host "  node-windows installed globally." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 8. Register Windows Event Log Sources
# -----------------------------------------------------------------------------
Write-Host "`n[9/9] Registering Windows Event Log sources..." -ForegroundColor Yellow

$sources = @("SQLSync-PowerShell", "SQLSync-NodeApp")

foreach ($source in $sources) {
    if (![System.Diagnostics.EventLog]::SourceExists($source)) {
        [System.Diagnostics.EventLog]::CreateEventSource($source, "Application")
        Write-Host "  Registered event source: $source" -ForegroundColor Green
    } else {
        Write-Host "  Event source already exists: $source" -ForegroundColor Green
    }
}

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Setup complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor White
Write-Host "  - Execution policy: RemoteSigned" -ForegroundColor White
Write-Host "  - Chocolatey: installed" -ForegroundColor White
Write-Host "  - Git: $(git --version)" -ForegroundColor White
Write-Host "  - Node.js: $(node --version)" -ForegroundColor White
Write-Host "  - C:\POC: created" -ForegroundColor White
Write-Host "  - Repo: C:\POC\azure-logging-alerting-playground" -ForegroundColor White
Write-Host "  - poc-node: npm dependencies installed" -ForegroundColor White
Write-Host "  - node-windows: installed globally" -ForegroundColor White
Write-Host "  - Event sources: $($sources -join ', ')" -ForegroundColor White
Write-Host ""
