# =============================================================================
# setup-vm.ps1
# VM bootstrap script for the Azure Monitoring Playground
# =============================================================================

# Note: When run via CustomScriptExtension, this executes as SYSTEM (admin).
# When running manually, launch PowerShell as Administrator.

$ErrorActionPreference = "Stop"

Write-Host "========================================" -ForegroundColor Cyan
Write-Host " Monitoring Playground VM Setup Script" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan

# Helper: refresh PATH from registry (picks up changes from choco installs)
function Refresh-Path {
    $env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
}

# -----------------------------------------------------------------------------
# 1. Set PowerShell Execution Policy
# -----------------------------------------------------------------------------
Write-Host "`n[1/10] Setting PowerShell execution policy to RemoteSigned..." -ForegroundColor Yellow
try {
    Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope LocalMachine -Force -ErrorAction SilentlyContinue
    Write-Host "  Execution policy set to RemoteSigned." -ForegroundColor Green
} catch {
    Write-Host "  Execution policy not changed (GPO override in effect). Current policy: $(Get-ExecutionPolicy). Continuing." -ForegroundColor Yellow
}

# -----------------------------------------------------------------------------
# 2. Install Chocolatey
# -----------------------------------------------------------------------------
Write-Host "`n[2/10] Installing Chocolatey package manager..." -ForegroundColor Yellow

if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    Invoke-Expression ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
    Refresh-Path
    Write-Host "  Chocolatey installed successfully." -ForegroundColor Green
} else {
    Write-Host "  Chocolatey is already installed." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 3. Install Git
# -----------------------------------------------------------------------------
Write-Host "`n[3/10] Installing Git..." -ForegroundColor Yellow

if (!(Get-Command git -ErrorAction SilentlyContinue)) {
    choco install git -y --no-progress
    Refresh-Path
    Write-Host "  Git installed: $(git --version)" -ForegroundColor Green
} else {
    Write-Host "  Git is already installed: $(git --version)" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 4. Install Node.js LTS
# -----------------------------------------------------------------------------
Write-Host "`n[4/10] Installing Node.js LTS..." -ForegroundColor Yellow

if (!(Get-Command node -ErrorAction SilentlyContinue)) {
    choco install nodejs-lts -y --no-progress
    Refresh-Path
    Write-Host "  Node.js installed: $(node --version)" -ForegroundColor Green
} else {
    Write-Host "  Node.js is already installed: $(node --version)" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 5. Create C:\POC directory
# -----------------------------------------------------------------------------
Write-Host "`n[5/10] Creating C:\POC directory..." -ForegroundColor Yellow

if (!(Test-Path "C:\POC")) {
    New-Item -ItemType Directory -Path "C:\POC" -Force | Out-Null
    Write-Host "  C:\POC directory created." -ForegroundColor Green
} else {
    Write-Host "  C:\POC directory already exists." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 6. Clone repo
# -----------------------------------------------------------------------------
Write-Host "`n[6/10] Cloning repo to C:\POC..." -ForegroundColor Yellow

$repoDir = "C:\POC\azure-logging-alerting-playground"
if (!(Test-Path "$repoDir\.git")) {
    git clone https://github.com/nickpeterson92/azure-logging-alerting-playground.git $repoDir
    Write-Host "  Repo cloned to $repoDir" -ForegroundColor Green
} else {
    git -C $repoDir pull
    Write-Host "  Repo already exists, pulled latest." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 7. Install npm dependencies for poc-node
# -----------------------------------------------------------------------------
Write-Host "`n[7/10] Installing npm dependencies for poc-node..." -ForegroundColor Yellow

Push-Location "$repoDir\poc-node"
npm install
Pop-Location
Write-Host "  npm dependencies installed." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 8. Install node-windows globally
# -----------------------------------------------------------------------------
Write-Host "`n[8/10] Installing node-windows npm package globally..." -ForegroundColor Yellow

npm install -g node-windows
Write-Host "  node-windows installed globally." -ForegroundColor Green

# -----------------------------------------------------------------------------
# 9. Register Windows Event Log Sources
#    - SQLSync-PowerShell: via .NET (used by Write-EventLog in PowerShell)
#    - SQLSync-NodeApp: via eventcreate (used by node-windows EventLogger)
#    These two methods use incompatible registry entries, so each source
#    must be registered with the method that matches its writer.
# -----------------------------------------------------------------------------
Write-Host "`n[9/10] Registering Windows Event Log sources..." -ForegroundColor Yellow

# PowerShell source - register via .NET
if (![System.Diagnostics.EventLog]::SourceExists('SQLSync-PowerShell')) {
    [System.Diagnostics.EventLog]::CreateEventSource('SQLSync-PowerShell', 'Application')
    Write-Host "  Registered event source: SQLSync-PowerShell (via .NET)" -ForegroundColor Green
} else {
    Write-Host "  Event source already exists: SQLSync-PowerShell" -ForegroundColor Green
}

# Node source - register via eventcreate (node-windows uses eventcreate.exe)
$nodeSourceExists = Get-EventLog -LogName Application -Source 'SQLSync-NodeApp' -Newest 1 -ErrorAction SilentlyContinue
if (!$nodeSourceExists) {
    # If it was previously registered via .NET, remove it first
    try {
        if ([System.Diagnostics.EventLog]::SourceExists('SQLSync-NodeApp')) {
            [System.Diagnostics.EventLog]::DeleteEventSource('SQLSync-NodeApp')
            Write-Host "  Removed stale .NET registration for SQLSync-NodeApp" -ForegroundColor Yellow
        }
    } catch { }
    eventcreate /T INFORMATION /ID 1 /L APPLICATION /SO "SQLSync-NodeApp" /D "Event source initialized by setup-vm.ps1"
    Write-Host "  Registered event source: SQLSync-NodeApp (via eventcreate)" -ForegroundColor Green
} else {
    Write-Host "  Event source already exists: SQLSync-NodeApp" -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# 10. Set PATH permanently for all users (so new shells just work)
# -----------------------------------------------------------------------------
Write-Host "`n[10/10] Ensuring PATH is set for all user sessions..." -ForegroundColor Yellow

# Write a profile script that all PowerShell sessions will load
$profileDir = "C:\Windows\System32\WindowsPowerShell\v1.0"
$profileScript = Join-Path $profileDir "profile.ps1"
$pathBlock = @'
# Auto-refresh PATH to pick up Chocolatey-installed tools (git, node, npm)
$env:Path = [System.Environment]::GetEnvironmentVariable("Path", "Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path", "User")
'@

if (!(Test-Path $profileScript) -or !(Select-String -Path $profileScript -Pattern "Auto-refresh PATH" -Quiet)) {
    Add-Content -Path $profileScript -Value "`n$pathBlock" -Force
    Write-Host "  PowerShell profile updated at $profileScript" -ForegroundColor Green
} else {
    Write-Host "  PowerShell profile already configured." -ForegroundColor Green
}

# -----------------------------------------------------------------------------
# Done
# -----------------------------------------------------------------------------
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host " Setup complete!" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "Summary:" -ForegroundColor White
Write-Host "  - Chocolatey: installed" -ForegroundColor White
Write-Host "  - Git: $(git --version)" -ForegroundColor White
Write-Host "  - Node.js: $(node --version)" -ForegroundColor White
Write-Host "  - C:\POC: created" -ForegroundColor White
Write-Host "  - Repo: $repoDir" -ForegroundColor White
Write-Host "  - poc-node: npm dependencies installed" -ForegroundColor White
Write-Host "  - node-windows: installed globally" -ForegroundColor White
Write-Host "  - SQLSync-PowerShell: registered via .NET" -ForegroundColor White
Write-Host "  - SQLSync-NodeApp: registered via eventcreate" -ForegroundColor White
Write-Host "  - PATH: persisted for all user sessions" -ForegroundColor White
Write-Host ""
Write-Host "Run the simulators:" -ForegroundColor Cyan
Write-Host "  cd $repoDir\poc-powershell; .\Start-IntegrationSync.ps1" -ForegroundColor White
Write-Host "  cd $repoDir\poc-node; npm start" -ForegroundColor White
Write-Host ""
