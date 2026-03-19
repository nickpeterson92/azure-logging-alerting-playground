<#
.SYNOPSIS
    Simulates a database-to-database sync pipeline with realistic SQL Server error codes.

.DESCRIPTION
    Runs a continuous sync loop simulating a pipeline that queries a source SQL Server
    (dbo.Accounts on sqlprod-east-01) and writes deltas to a target SQL Server
    (dbo.Accounts on sqlprod-west-01). Both sides can fail with real SQL Server error
    numbers. Transient failures (deadlock 1205, timeout -2, snapshot isolation 3960)
    are retried up to MaxRetries times before escalating from warning to error.

    Event IDs:
      1000 = Sync cycle started / info
      1001 = Sync cycle completed successfully
      2001 = Source SQL error
      2002 = Target SQL error
      3001 = Retryable warning (deadlock, timeout, snapshot isolation)

.PARAMETER RunCount
    Number of sync cycles to execute. Default: 20

.PARAMETER DelaySeconds
    Seconds to wait between each sync cycle. Default: 5

.PARAMETER FailureRate
    Probability (0.0 - 1.0) that any given step will fail. Default: 0.3

.PARAMETER MaxRetries
    Maximum retry attempts for transient failures. Default: 3

.EXAMPLE
    .\Start-IntegrationSync.ps1 -RunCount 10 -DelaySeconds 3 -FailureRate 0.5
#>

[CmdletBinding()]
param(
    [ValidateRange(1, 10000)]
    [int]$RunCount = 20,

    [ValidateRange(1, 300)]
    [int]$DelaySeconds = 5,

    [ValidateRange(0.0, 1.0)]
    [double]$FailureRate = 0.3,

    [ValidateRange(1, 10)]
    [int]$MaxRetries = 3
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$SourceName     = 'SQLSync-PowerShell'
$LogName        = 'Application'
$SourceServer   = 'sqlprod-east-01.database.windows.net'
$SourceDatabase = 'AccountingDB'
$TargetServer   = 'sqlprod-west-01.database.windows.net'
$TargetDatabase = 'AccountingDB_Replica'
$RetryBaseMs    = 500

# ---------------------------------------------------------------------------
# SQL Error catalogs — real SQL Server error numbers
# ---------------------------------------------------------------------------

# Source query errors
$script:SourceErrors = @(
    @{
        Number    = 207; State = 1; Class = 16
        Message   = "Invalid column name 'AccountStatus'."
        Category  = 'SCHEMA_DRIFT_COLUMN'; Retryable = $false
    },
    @{
        Number    = 208; State = 1; Class = 16
        Message   = "Invalid object name 'dbo.Accounts'."
        Category  = 'SCHEMA_DRIFT_TABLE'; Retryable = $false
    },
    @{
        Number    = 245; State = 1; Class = 16
        Message   = "Conversion failed when converting the varchar value '`$1,234.56' to data type decimal."
        Category  = 'TYPE_MISMATCH'; Retryable = $false
    },
    @{
        Number    = 1205; State = 51; Class = 13
        Message   = "Transaction (Process ID 52) was deadlocked on lock resources with another process and has been chosen as the deadlock victim."
        Category  = 'DEADLOCK'; Retryable = $true
    },
    @{
        Number    = -2; State = 0; Class = 11
        Message   = "Timeout expired. The timeout period elapsed prior to completion of the operation."
        Category  = 'TIMEOUT'; Retryable = $true
    },
    @{
        Number    = 229; State = 5; Class = 14
        Message   = "The SELECT permission was denied on the object 'Accounts', database '$SourceDatabase', schema 'dbo'."
        Category  = 'PERMISSION_DENIED'; Retryable = $false
    }
)

# Target write errors
$script:TargetErrors = @(
    @{
        Number    = 2627; State = 1; Class = 14
        Message   = "Violation of UNIQUE KEY constraint 'UQ_Accounts_ExternalId'. Cannot insert duplicate key in object 'dbo.Accounts'. The duplicate key value is (ACC-28471)."
        Category  = 'UNIQUE_VIOLATION'; Retryable = $false
    },
    @{
        Number    = 547; State = 0; Class = 16
        Message   = "The INSERT statement conflicted with the FOREIGN KEY constraint 'FK_Accounts_Region'. The conflict occurred in database '$TargetDatabase', table 'dbo.Regions', column 'RegionId'."
        Category  = 'FK_CONSTRAINT'; Retryable = $false
    },
    @{
        Number    = 1205; State = 51; Class = 13
        Message   = "Transaction (Process ID 87) was deadlocked on lock resources with another process and has been chosen as the deadlock victim."
        Category  = 'DEADLOCK'; Retryable = $true
    },
    @{
        Number    = -2; State = 0; Class = 11
        Message   = "Timeout expired. The timeout period elapsed prior to completion of the operation."
        Category  = 'TIMEOUT'; Retryable = $true
    },
    @{
        Number    = 229; State = 5; Class = 14
        Message   = "The INSERT permission was denied on the object 'Accounts', database '$TargetDatabase', schema 'dbo'."
        Category  = 'PERMISSION_DENIED'; Retryable = $false
    },
    @{
        Number    = 3960; State = 2; Class = 16
        Message   = "Snapshot isolation transaction aborted due to update conflict. Cannot use snapshot isolation to access table 'dbo.Accounts' in database '$TargetDatabase'."
        Category  = 'SNAPSHOT_CONFLICT'; Retryable = $true
    }
)

# ---------------------------------------------------------------------------
# Counters for summary
# ---------------------------------------------------------------------------
$script:Stats = @{
    TotalCycles        = 0
    Successes          = 0
    Failures           = 0
    FailuresByType     = @{}
    TotalRetries       = 0
    TotalRecordsFetched = 0
    TotalRecordsWritten = 0
}

# ---------------------------------------------------------------------------
# Helper: Write to Event Log
# ---------------------------------------------------------------------------
function Write-SyncEventLog {
    param(
        [string]$Message,
        [ValidateSet('Information', 'Warning', 'Error')]
        [string]$EntryType,
        [int]$EventId
    )

    $timestamp = Get-Date -Format 'yyyy-MM-ddTHH:mm:ss.fffZ'
    $fullMessage = "[$timestamp] [PID:$PID] $Message"

    try {
        Write-EventLog -LogName $LogName -Source $SourceName -EventId $EventId -EntryType $EntryType -Message $fullMessage
    }
    catch {
        Write-Warning "Failed to write to Event Log (EventId=$EventId): $_"
        Write-Warning "Message was: $fullMessage"
    }

    switch ($EntryType) {
        'Error'       { Write-Host "  [ERROR]   $Message" -ForegroundColor Red }
        'Warning'     { Write-Host "  [WARN]    $Message" -ForegroundColor Yellow }
        'Information' { Write-Host "  [INFO]    $Message" -ForegroundColor Gray }
    }
}

# ---------------------------------------------------------------------------
# Helper: Format a SQL error detail string
# ---------------------------------------------------------------------------
function Format-SqlErrorDetail {
    param(
        [hashtable]$SqlError,
        [string]$ServerName,
        [int]$Attempt,
        [bool]$ShowAttempt
    )

    $detail = "SQL Error #$($SqlError.Number) on ${ServerName}: $($SqlError.Message) " +
              "[state=$($SqlError.State), class=$($SqlError.Class)] -> $($SqlError.Category)"

    if ($ShowAttempt) {
        $detail += " (attempt $Attempt/$MaxRetries, retrying...)"
    }

    return $detail
}

# ---------------------------------------------------------------------------
# Attempt an operation with retries for transient SQL errors
# ---------------------------------------------------------------------------
function Invoke-StepWithRetry {
    param(
        [string]$StepName,
        [string]$ServerName,
        [hashtable[]]$ErrorCatalog,
        [int]$ErrorEventId,
        [double]$StepFailureRate
    )

    for ($attempt = 1; $attempt -le ($MaxRetries + 1); $attempt++) {
        # Simulate delay
        Start-Sleep -Milliseconds (Get-Random -Minimum 20 -Maximum 80)

        # Decide if this attempt fails
        $willFail = (Get-Random -Minimum 0.0 -Maximum 1.0) -lt $StepFailureRate

        if (-not $willFail) {
            return $null  # Success
        }

        # Pick a random error from the catalog
        $sqlError = $ErrorCatalog | Get-Random

        $detail = Format-SqlErrorDetail -SqlError $sqlError -ServerName $ServerName -Attempt $attempt -ShowAttempt $false

        # Non-retryable: fail immediately
        if (-not $sqlError.Retryable) {
            Write-SyncEventLog `
                -Message "$detail (not retryable)" `
                -EntryType 'Error' `
                -EventId $ErrorEventId

            return @{ Category = $sqlError.Category }
        }

        # Retryable but exhausted
        if ($attempt -gt $MaxRetries) {
            Write-SyncEventLog `
                -Message "$detail (exhausted $MaxRetries retries - escalating to error)" `
                -EntryType 'Error' `
                -EventId $ErrorEventId

            return @{ Category = "$($sqlError.Category)_RETRY_EXHAUSTED" }
        }

        # Retryable — log warning and retry
        $retryDetail = Format-SqlErrorDetail -SqlError $sqlError -ServerName $ServerName -Attempt $attempt -ShowAttempt $true

        Write-SyncEventLog `
            -Message $retryDetail `
            -EntryType 'Warning' `
            -EventId 3001

        $script:Stats.TotalRetries++
        Start-Sleep -Milliseconds ($RetryBaseMs * $attempt)
    }
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  Database-to-Database Sync Simulator"                            -ForegroundColor Cyan
Write-Host "  Source: $SourceName | Log: $LogName"                           -ForegroundColor Cyan
Write-Host "  $SourceServer.$SourceDatabase -> $TargetServer.$TargetDatabase" -ForegroundColor Cyan
Write-Host "  Cycles: $RunCount | Delay: ${DelaySeconds}s | Failure Rate: $($FailureRate * 100)%" -ForegroundColor Cyan
Write-Host "  Max Retries: $MaxRetries (for deadlock, timeout, snapshot isolation)" -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""

# Verify event source exists
try {
    if (-not [System.Diagnostics.EventLog]::SourceExists($SourceName)) {
        Write-Error "Event source '$SourceName' is not registered. Run Install-EventSource.ps1 as Administrator first."
        exit 1
    }
}
catch [System.Security.SecurityException] {
    Write-Warning "Cannot verify event source (requires elevation to check). Proceeding anyway - writes may fail."
}

for ($cycle = 1; $cycle -le $RunCount; $cycle++) {
    $script:Stats.TotalCycles++

    Write-Host ""
    Write-Host "--- Sync Cycle $cycle of $RunCount $(('-' * 40))" -ForegroundColor White

    # -----------------------------------------------------------------------
    # Step 1: Query source database
    # -----------------------------------------------------------------------
    $lastSyncTime = (Get-Date).AddMinutes(-(Get-Random -Minimum 5 -Maximum 60)).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

    Write-SyncEventLog `
        -Message "Sync cycle $cycle: Querying $SourceServer.$SourceDatabase dbo.Accounts for changes since $lastSyncTime..." `
        -EntryType 'Information' `
        -EventId 1000

    $sourceFailure = Invoke-StepWithRetry `
        -StepName 'SourceQuery' `
        -ServerName $SourceServer `
        -ErrorCatalog $script:SourceErrors `
        -ErrorEventId 2001 `
        -StepFailureRate $FailureRate

    if ($null -ne $sourceFailure) {
        $cat = $sourceFailure.Category
        $script:Stats.Failures++
        $script:Stats.FailuresByType[$cat] = ($script:Stats.FailuresByType[$cat] ?? 0) + 1

        Write-Host "  => $cat" -ForegroundColor Red

        if ($cycle -lt $RunCount) {
            Write-Host "  Waiting ${DelaySeconds}s before next cycle..." -ForegroundColor DarkGray
            Start-Sleep -Seconds $DelaySeconds
        }
        continue
    }

    # Source query succeeded
    $recordCount = Get-Random -Minimum 50 -Maximum 1000
    $queryDurationMs = Get-Random -Minimum 50 -Maximum 3000
    $script:Stats.TotalRecordsFetched += $recordCount

    Write-SyncEventLog `
        -Message "Sync cycle $cycle: Fetched $recordCount Account records from $SourceServer (${queryDurationMs}ms). Schema version: v43." `
        -EntryType 'Information' `
        -EventId 1000

    # -----------------------------------------------------------------------
    # Step 2: Write to target database
    # -----------------------------------------------------------------------
    Write-SyncEventLog `
        -Message "Sync cycle $cycle: Writing $recordCount records to $TargetServer.$TargetDatabase dbo.Accounts via MERGE statement..." `
        -EntryType 'Information' `
        -EventId 1000

    $targetFailure = Invoke-StepWithRetry `
        -StepName 'TargetWrite' `
        -ServerName $TargetServer `
        -ErrorCatalog $script:TargetErrors `
        -ErrorEventId 2002 `
        -StepFailureRate $FailureRate

    if ($null -ne $targetFailure) {
        $cat = $targetFailure.Category
        $script:Stats.Failures++
        $script:Stats.FailuresByType[$cat] = ($script:Stats.FailuresByType[$cat] ?? 0) + 1

        Write-Host "  => $cat" -ForegroundColor Red

        if ($cycle -lt $RunCount) {
            Write-Host "  Waiting ${DelaySeconds}s before next cycle..." -ForegroundColor DarkGray
            Start-Sleep -Seconds $DelaySeconds
        }
        continue
    }

    # Target write succeeded
    $writeDurationMs = Get-Random -Minimum 100 -Maximum 5000
    $inserted = [math]::Floor($recordCount * (Get-Random -Minimum 10 -Maximum 40) / 100)
    $updated = $recordCount - $inserted
    $script:Stats.TotalRecordsWritten += $recordCount

    Write-SyncEventLog `
        -Message "Sync cycle $cycle: Complete. $inserted inserted, $updated updated, 0 errors on $TargetServer.$TargetDatabase (${writeDurationMs}ms)." `
        -EntryType 'Information' `
        -EventId 1001

    $script:Stats.Successes++

    Write-Host "  => SUCCESS" -ForegroundColor Green

    if ($cycle -lt $RunCount) {
        Write-Host "  Waiting ${DelaySeconds}s before next cycle..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $DelaySeconds
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SIMULATION COMPLETE - SUMMARY"                                  -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Total Cycles Executed:  $($script:Stats.TotalCycles)"          -ForegroundColor White
Write-Host "  Successful Syncs:       $($script:Stats.Successes)"            -ForegroundColor Green
Write-Host "  Failed Syncs:           $($script:Stats.Failures)"             -ForegroundColor $(if ($script:Stats.Failures -gt 0) { 'Red' } else { 'Green' })
Write-Host "  Total Retries:          $($script:Stats.TotalRetries)"         -ForegroundColor $(if ($script:Stats.TotalRetries -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host "  Records Fetched:        $($script:Stats.TotalRecordsFetched)"  -ForegroundColor White
Write-Host "  Records Written:        $($script:Stats.TotalRecordsWritten)"  -ForegroundColor White
Write-Host ""

if ($script:Stats.FailuresByType.Count -gt 0) {
    Write-Host "  Failure Breakdown:" -ForegroundColor White
    foreach ($key in $script:Stats.FailuresByType.Keys | Sort-Object) {
        $count = $script:Stats.FailuresByType[$key]
        $isRetryExhausted = $key -match '_RETRY_EXHAUSTED$'
        $color = if ($isRetryExhausted) { 'Yellow' } else { 'Red' }
        Write-Host "    ${key}: $count" -ForegroundColor $color
    }
    Write-Host ""
}

$successRate = if ($script:Stats.TotalCycles -gt 0) {
    [math]::Round(($script:Stats.Successes / $script:Stats.TotalCycles) * 100, 1)
} else { 0 }
Write-Host "  Success Rate:           ${successRate}%" -ForegroundColor $(if ($successRate -eq 100) { 'Green' } else { 'Yellow' })
Write-Host ""
Write-Host "  Event Log Source: $SourceName" -ForegroundColor Gray
Write-Host "  View logs: Get-EventLog -LogName Application -Source '$SourceName' -Newest 50" -ForegroundColor Gray
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
