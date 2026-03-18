<#
.SYNOPSIS
    Simulates a SQL Server to Salesforce data sync pipeline that encounters realistic failures.

.DESCRIPTION
    Runs a continuous sync loop simulating an integration pipeline between SQL Server and
    Salesforce. Each cycle queries a fictional dbo.Accounts table, transforms records, and
    pushes them to the Salesforce Account object. Failures are injected randomly based on
    the configured failure rate and logged to the Windows Application event log under the
    source "SQLSync-PowerShell".

    Event IDs:
      1000 = Sync cycle started
      1001 = Sync cycle completed successfully
      2001 = Schema drift detected (column renamed/dropped)
      2002 = Data type mismatch
      2003 = Salesforce field missing
      2004 = Salesforce permission error
      3001 = Salesforce rate limit warning

.PARAMETER RunCount
    Number of sync cycles to execute. Default: 20

.PARAMETER DelaySeconds
    Seconds to wait between each sync cycle. Default: 5

.PARAMETER FailureRate
    Probability (0.0 - 1.0) that any given cycle will fail. Default: 0.3

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
    [double]$FailureRate = 0.3
)

$ErrorActionPreference = 'Stop'

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
$SourceName       = 'SQLSync-PowerShell'
$LogName          = 'Application'
$IntegrationUser  = 'sf-sync@company.com'
$SalesforceOrg    = 'https://company.my.salesforce.com'

# Track API usage across cycles (simulated)
$script:ApiCallsUsed = Get-Random -Minimum 12000 -Maximum 13500

# ---------------------------------------------------------------------------
# Counters for summary
# ---------------------------------------------------------------------------
$script:Stats = @{
    TotalCycles       = 0
    Successes         = 0
    SchemaDrift       = 0
    DataTypeMismatch  = 0
    SfFieldMissing    = 0
    SfPermissionError = 0
    RateLimitWarnings = 0
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

    # Also echo to console with color coding
    switch ($EntryType) {
        'Error'       { Write-Host "  [ERROR]   $Message" -ForegroundColor Red }
        'Warning'     { Write-Host "  [WARN]    $Message" -ForegroundColor Yellow }
        'Information' { Write-Host "  [INFO]    $Message" -ForegroundColor Gray }
    }
}

# ---------------------------------------------------------------------------
# Simulate a successful sync cycle
# ---------------------------------------------------------------------------
function Invoke-SuccessfulSync {
    param([int]$CycleNumber)

    $recordCount   = Get-Random -Minimum 10 -Maximum 501
    $lastSyncTime  = (Get-Date).AddMinutes(-(Get-Random -Minimum 5 -Maximum 60)).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $queryDuration = Get-Random -Minimum 120 -Maximum 4500
    $transformMs   = Get-Random -Minimum 45 -Maximum 800
    $pushDuration  = Get-Random -Minimum 500 -Maximum 6000
    $batchSize     = [math]::Min($recordCount, 200)

    # Step 1: Start
    Write-SyncEventLog `
        -Message "Sync cycle $CycleNumber started. Querying SQL Server for Account changes since $lastSyncTime. Connection: sqlprod-east-01.database.windows.net:1433, Database: AccountingDB, Timeout: 30s" `
        -EntryType 'Information' `
        -EventId 1000

    Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 800)

    # Step 2: Records retrieved
    Write-SyncEventLog `
        -Message "Retrieved $recordCount records from dbo.Accounts (query took ${queryDuration}ms). Filter: LastModified > '$lastSyncTime'. Columns: AccountId, AccountName, AccountStatus, Revenue, Segment, OwnerId, LastModified. Server: sqlprod-east-01" `
        -EntryType 'Information' `
        -EventId 1000

    Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 400)

    # Step 3: Transform
    Write-SyncEventLog `
        -Message "Transforming $recordCount records for Salesforce Account object. Mapping: dbo.Accounts.AccountId -> Account.External_Id__c, dbo.Accounts.AccountName -> Account.Name, dbo.Accounts.Revenue -> Account.AnnualRevenue. Transform duration: ${transformMs}ms. Null handling: skip-null-fields." `
        -EntryType 'Information' `
        -EventId 1000

    Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 300)

    # Step 4: Push to Salesforce
    $batches = [math]::Ceiling($recordCount / $batchSize)
    $script:ApiCallsUsed += $batches
    Write-SyncEventLog `
        -Message "Pushing $recordCount records to Salesforce API ($SalesforceOrg/services/data/v59.0/composite/sobjects). Batch size: $batchSize, Total batches: $batches. Using upsert on External_Id__c. Push duration: ${pushDuration}ms." `
        -EntryType 'Information' `
        -EventId 1000

    Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 600)

    # Step 5: Success
    $totalDuration = $queryDuration + $transformMs + $pushDuration
    Write-SyncEventLog `
        -Message "Sync cycle $CycleNumber completed successfully. $recordCount records synced to Salesforce Account object in ${totalDuration}ms. Created: $(Get-Random -Minimum 0 -Maximum ([math]::Max(1, [int]($recordCount * 0.1)))), Updated: $($recordCount - (Get-Random -Minimum 0 -Maximum ([math]::Max(1, [int]($recordCount * 0.1))))), Errors: 0. API calls this session: $($script:ApiCallsUsed)/15000." `
        -EntryType 'Information' `
        -EventId 1001

    $script:Stats.Successes++
}

# ---------------------------------------------------------------------------
# Failure Scenario A: SQL Schema Drift - Column Renamed
# ---------------------------------------------------------------------------
function Invoke-SchemaDriftColumnRenamed {
    param([int]$CycleNumber)

    $lastSyncTime = (Get-Date).AddMinutes(-(Get-Random -Minimum 5 -Maximum 60)).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

    Write-SyncEventLog `
        -Message "Sync cycle $CycleNumber started. Querying SQL Server for Account changes since $lastSyncTime. Connection: sqlprod-east-01.database.windows.net:1433, Database: AccountingDB, Timeout: 30s" `
        -EntryType 'Information' `
        -EventId 1000

    Start-Sleep -Milliseconds (Get-Random -Minimum 300 -Maximum 900)

    Write-SyncEventLog `
        -Message "SCHEMA_DRIFT_DETECTED: Column 'AccountStatus' not found in dbo.Accounts. Expected column was renamed or dropped. Last known schema hash: 0x7F3A. Current schema hash: 0x9B2C. Query: SELECT AccountId, AccountName, AccountStatus, LastModified FROM dbo.Accounts WHERE LastModified > @LastSync. Server: sqlprod-east-01.database.windows.net, Database: AccountingDB. Schema cache age: 4h 22m. Run 'EXEC sp_IntegrationSchemaRefresh @Table=N''dbo.Accounts''' to update cached schema." `
        -EntryType 'Error' `
        -EventId 2001

    Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 300)

    Write-SyncEventLog `
        -Message "SQL_QUERY_FAILED: Invalid column name 'AccountStatus'. The column may have been renamed to 'Status' in a recent migration (see migration #847 applied 2024-01-15T08:15:00Z by deploy-svc@company.com). Integration mapping requires update. Affected query: SELECT AccountId, AccountName, AccountStatus, LastModified FROM dbo.Accounts WHERE LastModified > '${lastSyncTime}'. Suggestion: Update integration column mapping in config table dbo.IntegrationFieldMap (MapId=12, SourceColumn='AccountStatus' -> 'Status')." `
        -EntryType 'Error' `
        -EventId 2001

    $script:Stats.SchemaDrift++
}

# ---------------------------------------------------------------------------
# Failure Scenario B: SQL Schema Drift - Data Type Change
# ---------------------------------------------------------------------------
function Invoke-SchemaDriftDataType {
    param([int]$CycleNumber)

    $lastSyncTime = (Get-Date).AddMinutes(-(Get-Random -Minimum 5 -Maximum 60)).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $recordCount  = Get-Random -Minimum 10 -Maximum 501
    $failedRecord = Get-Random -Minimum 1 -Maximum $recordCount

    Write-SyncEventLog `
        -Message "Sync cycle $CycleNumber started. Querying SQL Server for Account changes since $lastSyncTime. Connection: sqlprod-east-01.database.windows.net:1433, Database: AccountingDB, Timeout: 30s" `
        -EntryType 'Information' `
        -EventId 1000

    Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 600)

    Write-SyncEventLog `
        -Message "Retrieved $recordCount records from dbo.Accounts (query took $(Get-Random -Minimum 120 -Maximum 4500)ms). Filter: LastModified > '$lastSyncTime'." `
        -EntryType 'Information' `
        -EventId 1000

    Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 500)

    Write-SyncEventLog `
        -Message "SCHEMA_DRIFT_DETECTED: Data type mismatch on column 'Revenue' in dbo.Accounts. Expected: DECIMAL(18,2), Found: VARCHAR(50). Migration #852 changed column type without updating integration config. ALTER TABLE detected at 2024-01-14T22:45:00Z. Previous successful type validation: 2024-01-14T10:30:00Z. Schema version: 852, Integration config expects schema version: 849. Database: AccountingDB, Server: sqlprod-east-01.database.windows.net." `
        -EntryType 'Error' `
        -EventId 2002

    Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 300)

    Write-SyncEventLog `
        -Message "DATA_TRANSFORM_FAILED: Cannot convert 'Revenue' value '`$1,234.56' (VARCHAR) to Decimal for Salesforce field Account.AnnualRevenue. Source type changed from DECIMAL to VARCHAR in dbo.Accounts. Failed at record index $failedRecord of $recordCount (AccountId='ACC-$(Get-Random -Minimum 10000 -Maximum 99999)'). Transform rule 'DecimalToSalesforceNumber' does not support VARCHAR input. $($failedRecord - 1) records processed before failure. Batch rolled back. To resume: set LastSync='$lastSyncTime' in dbo.IntegrationState and fix type mapping." `
        -EntryType 'Error' `
        -EventId 2002

    $script:Stats.DataTypeMismatch++
}

# ---------------------------------------------------------------------------
# Failure Scenario C: Salesforce Field Missing
# ---------------------------------------------------------------------------
function Invoke-SalesforceFieldMissing {
    param([int]$CycleNumber)

    $lastSyncTime = (Get-Date).AddMinutes(-(Get-Random -Minimum 5 -Maximum 60)).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $recordCount  = Get-Random -Minimum 10 -Maximum 501

    Write-SyncEventLog `
        -Message "Sync cycle $CycleNumber started. Querying SQL Server for Account changes since $lastSyncTime. Connection: sqlprod-east-01.database.windows.net:1433, Database: AccountingDB, Timeout: 30s" `
        -EntryType 'Information' `
        -EventId 1000

    Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 600)

    Write-SyncEventLog `
        -Message "Retrieved $recordCount records from dbo.Accounts. Transforming for Salesforce Account object..." `
        -EntryType 'Information' `
        -EventId 1000

    Start-Sleep -Milliseconds (Get-Random -Minimum 300 -Maximum 800)

    Write-SyncEventLog `
        -Message "Pushing $recordCount records to Salesforce API ($SalesforceOrg/services/data/v59.0/composite/sobjects)..." `
        -EntryType 'Information' `
        -EventId 1000

    Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 500)

    $requestId = [guid]::NewGuid().ToString('N').Substring(0, 16).ToUpper()

    Write-SyncEventLog `
        -Message "SALESFORCE_API_ERROR: Field 'Custom_Segment__c' does not exist on object 'Account'. Check field-level security and custom field deployment status. API Response: [{`"errorCode`":`"INVALID_FIELD`",`"message`":`"No such column 'Custom_Segment__c' on entity 'Account'. If you are attempting to use a custom field, be sure to append the '__c' after the custom field name. Refer to the custom field list at $SalesforceOrg/p/setup/field/StandardFieldList/Account`"}]. HTTP 400 Bad Request. Request-Id: $requestId. Endpoint: /services/data/v59.0/composite/sobjects/Account/External_Id__c. Batch: 1 of $([math]::Ceiling($recordCount / 200)). All $recordCount records in this cycle failed." `
        -EntryType 'Error' `
        -EventId 2003

    Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 200)

    $lastSuccessTime = (Get-Date).AddHours(-2).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

    Write-SyncEventLog `
        -Message "FIELD_MAPPING_BROKEN: Source field dbo.Accounts.Segment maps to Account.Custom_Segment__c which no longer exists. Last successful sync used this mapping at $lastSuccessTime ($([math]::Round((Get-Date - (Get-Date).AddHours(-2)).TotalMinutes)) minutes ago). Possible cause: field deleted in Salesforce org, sandbox refresh overwrote production metadata, or field-level security revoked for profile 'Integration_User'. Mapping config: dbo.IntegrationFieldMap (MapId=8, SourceColumn='Segment', TargetObject='Account', TargetField='Custom_Segment__c'). Contact Salesforce admin to verify field exists and is accessible." `
        -EntryType 'Warning' `
        -EventId 2003

    $script:Stats.SfFieldMissing++
}

# ---------------------------------------------------------------------------
# Failure Scenario D: Salesforce Permission Error
# ---------------------------------------------------------------------------
function Invoke-SalesforcePermissionError {
    param([int]$CycleNumber)

    $lastSyncTime = (Get-Date).AddMinutes(-(Get-Random -Minimum 5 -Maximum 60)).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')
    $recordCount  = Get-Random -Minimum 50 -Maximum 300
    $failedIndex  = Get-Random -Minimum 10 -Maximum $recordCount

    Write-SyncEventLog `
        -Message "Sync cycle $CycleNumber started. Querying SQL Server for Account changes since $lastSyncTime. Connection: sqlprod-east-01.database.windows.net:1433, Database: AccountingDB, Timeout: 30s" `
        -EntryType 'Information' `
        -EventId 1000

    Start-Sleep -Milliseconds (Get-Random -Minimum 200 -Maximum 500)

    Write-SyncEventLog `
        -Message "Retrieved $recordCount records from dbo.Accounts. Transforming and pushing to Salesforce..." `
        -EntryType 'Information' `
        -EventId 1000

    Start-Sleep -Milliseconds (Get-Random -Minimum 400 -Maximum 1000)

    $requestId   = [guid]::NewGuid().ToString('N').Substring(0, 16).ToUpper()
    $accountId   = "ACC-$(Get-Random -Minimum 10000 -Maximum 99999)"
    $sfAccountId = "001$(Get-Random -Minimum 1000000000 -Maximum 9999999999)$(Get-Random -Minimum 100 -Maximum 999)"

    Write-SyncEventLog `
        -Message "SALESFORCE_API_ERROR: INSUFFICIENT_ACCESS_OR_READONLY - Cannot update field 'OwnerId' on Account. Profile 'Integration_User' lacks Edit permission on Account.OwnerId. Error occurred at record index $failedIndex of $recordCount (SourceId='$accountId', SalesforceId='$sfAccountId'). API Response: [{`"errorCode`":`"INSUFFICIENT_ACCESS_OR_READONLY`",`"message`":`"insufficient access rights on cross-reference id`",`"fields`":[`"OwnerId`"]}]. HTTP 400 Bad Request. Request-Id: $requestId. Records processed before failure: $($failedIndex - 1). Records remaining: $($recordCount - $failedIndex). Partial batch committed: false (all-or-nothing mode)." `
        -EntryType 'Error' `
        -EventId 2004

    Start-Sleep -Milliseconds (Get-Random -Minimum 100 -Maximum 200)

    $lastSuccessTime = (Get-Date).AddHours(-(Get-Random -Minimum 2 -Maximum 48)).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

    Write-SyncEventLog `
        -Message "PERMISSION_DEGRADED: Integration user '$IntegrationUser' permissions changed. Previous sync succeeded at $lastSuccessTime. Current failure suggests profile or permission set modification. User profile: 'Integration_User', Permission sets: ['SF_API_Access', 'Account_ReadWrite', 'Data_Integration_Full']. Recommended action: Verify permission set assignments at $SalesforceOrg/lightning/setup/PermSets/home and check Setup Audit Trail for recent changes to 'Integration_User' profile. Escalation: contact Salesforce admin team (sf-admins@company.com, Slack: #salesforce-admin)." `
        -EntryType 'Warning' `
        -EventId 2004

    $script:Stats.SfPermissionError++
}

# ---------------------------------------------------------------------------
# Warning Scenario E: Salesforce Rate Limit
# ---------------------------------------------------------------------------
function Invoke-SalesforceRateLimit {
    param([int]$CycleNumber)

    $script:ApiCallsUsed += Get-Random -Minimum 200 -Maximum 600
    if ($script:ApiCallsUsed -gt 15000) { $script:ApiCallsUsed = Get-Random -Minimum 14200 -Maximum 14800 }

    $remaining    = 15000 - $script:ApiCallsUsed
    $batchCalls   = Get-Random -Minimum 150 -Maximum 300
    $resetTime    = (Get-Date).Date.AddDays(1).ToString('yyyy-MM-ddTHH:mm:ss.fffZ')

    Write-SyncEventLog `
        -Message "SALESFORCE_RATE_LIMIT: API call limit approaching. Used $($script:ApiCallsUsed.ToString('N0')) of 15,000 daily API calls ($([math]::Round(($script:ApiCallsUsed / 15000) * 100, 1))% consumed). Current sync batch requires ~$batchCalls additional calls. Remaining: $remaining calls. Rate limit resets at $resetTime. Throttling sync frequency from every ${DelaySeconds}s to every $($DelaySeconds * 4)s. Org: $SalesforceOrg. Monitor usage: $SalesforceOrg/lightning/setup/CompanyProfileInfo/home. If limit is reached, all API integrations will be blocked until reset. Consider requesting higher API limit from Salesforce (current edition: Enterprise, max: 15,000/day)." `
        -EntryType 'Warning' `
        -EventId 3001

    $script:Stats.RateLimitWarnings++
}

# ---------------------------------------------------------------------------
# Main execution
# ---------------------------------------------------------------------------

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SQL Server -> Salesforce Integration Sync Simulator"           -ForegroundColor Cyan
Write-Host "  Source: $SourceName | Log: $LogName"                           -ForegroundColor Cyan
Write-Host "  Cycles: $RunCount | Delay: ${DelaySeconds}s | Failure Rate: $($FailureRate * 100)%" -ForegroundColor Cyan
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

$failureScenarios = @(
    'SchemaDriftColumnRenamed',
    'SchemaDriftDataType',
    'SalesforceFieldMissing',
    'SalesforcePermissionError'
)

for ($cycle = 1; $cycle -le $RunCount; $cycle++) {
    $script:Stats.TotalCycles++

    Write-Host ""
    Write-Host "--- Sync Cycle $cycle of $RunCount $(('-' * 40))" -ForegroundColor White

    $shouldFail = (Get-Random -Minimum 0.0 -Maximum 1.0) -lt $FailureRate

    # Rate limit warning can happen independently (10% chance per cycle, more likely as cycles progress)
    $rateLimitChance = [math]::Min(0.4, 0.05 + ($cycle / $RunCount) * 0.3)
    $shouldRateLimit = (Get-Random -Minimum 0.0 -Maximum 1.0) -lt $rateLimitChance

    if ($shouldFail) {
        $scenario = $failureScenarios | Get-Random

        switch ($scenario) {
            'SchemaDriftColumnRenamed'   { Invoke-SchemaDriftColumnRenamed -CycleNumber $cycle }
            'SchemaDriftDataType'        { Invoke-SchemaDriftDataType -CycleNumber $cycle }
            'SalesforceFieldMissing'     { Invoke-SalesforceFieldMissing -CycleNumber $cycle }
            'SalesforcePermissionError'  { Invoke-SalesforcePermissionError -CycleNumber $cycle }
        }
    }
    else {
        Invoke-SuccessfulSync -CycleNumber $cycle
    }

    # Rate limit warning can fire on top of success or failure
    if ($shouldRateLimit) {
        Write-Host ""
        Invoke-SalesforceRateLimit -CycleNumber $cycle
    }

    if ($cycle -lt $RunCount) {
        Write-Host "  Waiting ${DelaySeconds}s before next cycle..." -ForegroundColor DarkGray
        Start-Sleep -Seconds $DelaySeconds
    }
}

# ---------------------------------------------------------------------------
# Summary
# ---------------------------------------------------------------------------
$totalFailures = $script:Stats.SchemaDrift + $script:Stats.DataTypeMismatch + $script:Stats.SfFieldMissing + $script:Stats.SfPermissionError

Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host "  SIMULATION COMPLETE - SUMMARY"                                  -ForegroundColor Cyan
Write-Host "================================================================" -ForegroundColor Cyan
Write-Host ""
Write-Host "  Total Cycles Executed:    $($script:Stats.TotalCycles)"        -ForegroundColor White
Write-Host "  Successful Syncs:         $($script:Stats.Successes)"          -ForegroundColor Green
Write-Host "  Failed Syncs:             $totalFailures"                       -ForegroundColor $(if ($totalFailures -gt 0) { 'Red' } else { 'Green' })
Write-Host ""
Write-Host "  Failure Breakdown:" -ForegroundColor White
Write-Host "    Schema Drift (Column):  $($script:Stats.SchemaDrift)"        -ForegroundColor $(if ($script:Stats.SchemaDrift -gt 0) { 'Red' } else { 'Gray' })
Write-Host "    Data Type Mismatch:     $($script:Stats.DataTypeMismatch)"   -ForegroundColor $(if ($script:Stats.DataTypeMismatch -gt 0) { 'Red' } else { 'Gray' })
Write-Host "    SF Field Missing:       $($script:Stats.SfFieldMissing)"     -ForegroundColor $(if ($script:Stats.SfFieldMissing -gt 0) { 'Red' } else { 'Gray' })
Write-Host "    SF Permission Error:    $($script:Stats.SfPermissionError)"  -ForegroundColor $(if ($script:Stats.SfPermissionError -gt 0) { 'Red' } else { 'Gray' })
Write-Host "    Rate Limit Warnings:    $($script:Stats.RateLimitWarnings)"  -ForegroundColor $(if ($script:Stats.RateLimitWarnings -gt 0) { 'Yellow' } else { 'Gray' })
Write-Host ""
Write-Host "  Success Rate:             $([math]::Round(($script:Stats.Successes / $script:Stats.TotalCycles) * 100, 1))%" -ForegroundColor $(if ($script:Stats.Successes -eq $script:Stats.TotalCycles) { 'Green' } else { 'Yellow' })
Write-Host "  Simulated API Calls Used: $($script:ApiCallsUsed.ToString('N0')) / 15,000" -ForegroundColor White
Write-Host ""
Write-Host "  Event Log Source: $SourceName" -ForegroundColor Gray
Write-Host "  View logs: Get-EventLog -LogName Application -Source '$SourceName' -Newest 50" -ForegroundColor Gray
Write-Host ""
Write-Host "================================================================" -ForegroundColor Cyan
