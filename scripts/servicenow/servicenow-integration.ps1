<#
.SYNOPSIS
    ServiceNow SCTASK Bi-Directional Integration Module for Intune App Factory.
.DESCRIPTION
    Integrates GitHub Actions with ServiceNow ITSM Catalog Tasks (sc_task Table API).
    Supports:
      1. Looking up SCTASK records by Number (e.g., SCTASK0010293) to retrieve sys_id.
      2. Updating Task state to 'Work in Progress' (2) on pipeline initialization.
      3. Adding rich work notes with GitHub Run URLs, Runner info, and execution logs.
      4. Auto-closing Tasks with 'Closed Complete' (3) or 'Closed Incomplete' (4).
      5. Safe Dry-Run execution for testing without mutating ServiceNow records.
      6. Secret retrieval from Azure Key Vault or Environment variables (Basic Auth or OAuth Bearer).
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)]
    [ValidateSet("StartTask", "UpdateNote", "CloseTask", "CreateTask", "LookupTask")]
    [string]$Action,

    [Parameter(Mandatory = $false)]
    [string]$TaskNumber = "",

    [Parameter(Mandatory = $false)]
    [string]$SysId = "",

    [Parameter(Mandatory = $true)]
    [string]$AppId,

    [Parameter(Mandatory = $true)]
    [string]$Environment,

    [Parameter(Mandatory = $false)]
    [string]$BuildId = "",

    [Parameter(Mandatory = $false)]
    [ValidateSet("Successful", "Failed", "InProgress")]
    [string]$Status = "InProgress",

    [Parameter(Mandatory = $false)]
    [string]$Message = "",

    [Parameter(Mandatory = $false)]
    [string]$KeyVaultName = "",

    [Parameter(Mandatory = $false)]
    [switch]$DryRun = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "===================================================================="
Write-Host "SERVICENOW INTEGRATION STAGE"
Write-Host "Action          : $Action"
Write-Host "Task Number     : $(if ($TaskNumber) { $TaskNumber } else { 'N/A' })"
Write-Host "Sys ID          : $(if ($SysId) { $SysId } else { 'Will resolve dynamically' })"
Write-Host "Application ID  : $AppId"
Write-Host "Environment     : $Environment"
Write-Host "Build ID        : $BuildId"
Write-Host "Status          : $Status"
Write-Host "DryRun Mode     : $DryRun"
Write-Host "===================================================================="

$workspaceDir = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Item .).FullName }

# Resolve GitHub Run URL for audit logging
$serverUrl = if ($env:GITHUB_SERVER_URL) { $env:GITHUB_SERVER_URL } else { "https://github.com" }
$repository = if ($env:GITHUB_REPOSITORY) { $env:GITHUB_REPOSITORY } else { "organization/intune-app-factory" }
$runId = if ($env:GITHUB_RUN_ID) { $env:GITHUB_RUN_ID } else { "local-dev" }
$runUrl = "$serverUrl/$repository/actions/runs/$runId"
$runnerHost = if ($env:RUNNER_NAME) { $env:RUNNER_NAME } else { $env:COMPUTERNAME }

# ---------------------------------------------------------------------------
# 1. Resolve ServiceNow Credentials (Key Vault -> Environment Variables)
# ---------------------------------------------------------------------------
$snowInstance = ""
$snowUser = ""
$snowPassword = ""
$snowToken = ""

if ($KeyVaultName) {
    Write-Host "[SERVICENOW] Retrieving credentials from Azure Key Vault '$KeyVaultName'..."
    $authHelper = Join-Path $workspaceDir "scripts\common\azure-auth.ps1"
    if (Test-Path $authHelper) {
        . $authHelper
        $snowInstance = Get-KeyVaultSecretValue -VaultName $KeyVaultName -SecretName "ServiceNowInstanceUrl"
        $snowToken = Get-KeyVaultSecretValue -VaultName $KeyVaultName -SecretName "ServiceNowApiToken"
        $snowUser = Get-KeyVaultSecretValue -VaultName $KeyVaultName -SecretName "ServiceNowUser"
        $snowPassword = Get-KeyVaultSecretValue -VaultName $KeyVaultName -SecretName "ServiceNowPassword"
    }
}

# Fallback to Environment Variables if not retrieved from Key Vault
if (-not $snowInstance -or $snowInstance -like "TODO*") {
    $snowInstance = if ($env:SERVICENOW_INSTANCE) { $env:SERVICENOW_INSTANCE } else { "" }
}
if (-not $snowToken -or $snowToken -like "TODO*") {
    $snowToken = if ($env:SERVICENOW_TOKEN) { $env:SERVICENOW_TOKEN } else { "" }
}
if (-not $snowUser -or $snowUser -like "TODO*") {
    $snowUser = if ($env:SERVICENOW_USER) { $env:SERVICENOW_USER } else { "" }
}
if (-not $snowPassword -or $snowPassword -like "TODO*") {
    $snowPassword = if ($env:SERVICENOW_PASSWORD) { $env:SERVICENOW_PASSWORD } else { "" }
}

# Clean instance URL
if ($snowInstance) {
    $snowInstance = $snowInstance.TrimEnd('/')
}

# Check if we should activate Mock/DryRun automatically if credentials are missing
$isMockExecution = $false
if ($DryRun -or [string]::IsNullOrWhiteSpace($snowInstance) -or ($snowInstance -like "*TODO*") -or ([string]::IsNullOrWhiteSpace($snowToken) -and [string]::IsNullOrWhiteSpace($snowUser))) {
    $isMockExecution = $true
    Write-Warning "[SERVICENOW] Operating in DRY-RUN / SIMULATION mode. No real API requests will be dispatched to ServiceNow."
    if (-not $snowInstance) { $snowInstance = "https://mock-instance.service-now.com" }
}

# Build Authorization Headers
$headers = @{
    "Accept"       = "application/json"
    "Content-Type" = "application/json"
}

if (-not $isMockExecution) {
    if ($snowToken) {
        $headers["Authorization"] = "Bearer $snowToken"
    } elseif ($snowUser -and $snowPassword) {
        $base64Auth = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes("${snowUser}:${snowPassword}"))
        $headers["Authorization"] = "Basic $base64Auth"
    }
}

# ---------------------------------------------------------------------------
# 2. Helper Functions: Lookup SysId by Task Number
# ---------------------------------------------------------------------------
function Get-SCTaskSysId {
    param ([string]$TaskNum)

    if ($isMockExecution) {
        Write-Host "[SERVICENOW-MOCK] Resolved $TaskNum to mock sys_id: mock_sys_id_99a8b7c6d5e4"
        return "mock_sys_id_99a8b7c6d5e4"
    }

    $lookupUri = "$snowInstance/api/now/table/sc_task?sysparm_query=number=$TaskNum&sysparm_fields=sys_id,number,state,short_description&sysparm_limit=1"
    Write-Host "[SERVICENOW] Looking up SCTASK record: $lookupUri"

    try {
        $response = Invoke-RestMethod -Uri $lookupUri -Method Get -Headers $headers -TimeoutSec 30
        if ($response.result -and $response.result.Count -gt 0) {
            $record = $response.result[0]
            Write-Host "[SERVICENOW] Found record '$($record.number)' with sys_id: $($record.sys_id)"
            return $record.sys_id
        } else {
            Write-Error "[SERVICENOW] No SCTASK found matching number '$TaskNum'."
        }
    } catch {
        Write-Error "[SERVICENOW] Failed to lookup SCTASK '$TaskNum': $_"
    }
}

# Resolve SysId if TaskNumber is provided and SysId is missing
if (-not $SysId -and $TaskNumber) {
    $SysId = Get-SCTaskSysId -TaskNum $TaskNumber
}

# ---------------------------------------------------------------------------
# 3. Action Handlers
# ---------------------------------------------------------------------------
switch ($Action) {
    "StartTask" {
        Write-Host "[SERVICENOW] Dispatching Task Initialization (Work in Progress)..."
        
        $workNoteText = @"
[GitHub Actions Dispatch]
Pipeline initiated for Intune App Factory deployment.
- Application ID : $AppId
- Environment    : $Environment
- Build ID       : $BuildId
- Runner         : $runnerHost
- Workflow Run   : $runUrl
- Timestamp      : $((Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss UTC"))
"@

        $payload = @{
            state      = "2" # 2 = Work in Progress
            work_notes = $workNoteText
        } | ConvertTo-Json

        Write-Host "[SERVICENOW] Payload JSON:"
        Write-Host $payload

        if ($isMockExecution) {
            Write-Host "[SERVICENOW-MOCK] Simulated PATCH to $snowInstance/api/now/table/sc_task/$SysId"
            Write-Host "[SERVICENOW-MOCK] SCTASK successfully updated to 'Work in Progress'."
        } else {
            if (-not $SysId) {
                Write-Error "[SERVICENOW] Cannot update task: sys_id could not be resolved."
            }
            $targetUri = "$snowInstance/api/now/table/sc_task/$SysId"
            $res = Invoke-RestMethod -Uri $targetUri -Method Patch -Headers $headers -Body $payload
            Write-Host "[SERVICENOW] Successfully updated SCTASK ($SysId) to Work in Progress."
        }
    }

    "UpdateNote" {
        Write-Host "[SERVICENOW] Adding Work Note to SCTASK..."
        $noteBody = if ($Message) { $Message } else { "Pipeline progress update for $AppId (Build: $BuildId)" }
        $formattedNote = @"
[GitHub Actions Progress]
$noteBody
- Run URL: $runUrl
- Timestamp: $((Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss UTC"))
"@
        $payload = @{
            work_notes = $formattedNote
        } | ConvertTo-Json

        Write-Host "[SERVICENOW] Payload JSON:"
        Write-Host $payload

        if ($isMockExecution) {
            Write-Host "[SERVICENOW-MOCK] Simulated PATCH to $snowInstance/api/now/table/sc_task/$SysId (Add Work Note)"
        } else {
            $targetUri = "$snowInstance/api/now/table/sc_task/$SysId"
            $res = Invoke-RestMethod -Uri $targetUri -Method Patch -Headers $headers -Body $payload
            Write-Host "[SERVICENOW] Work note added successfully."
        }
    }

    "CloseTask" {
        Write-Host "[SERVICENOW] Auto-closing SCTASK record with status: $Status..."
        
        $stateValue = if ($Status -eq "Successful") { "3" } else { "4" } # 3 = Closed Complete, 4 = Closed Incomplete
        $closeCode = if ($Status -eq "Successful") { "Closed Successful" } else { "Closed Incomplete" }
        
        $closeNoteText = if ($Status -eq "Successful") {
@"
[Intune App Factory - Deployment Successful]
Application deployment completed and verified.
- Application ID : $AppId
- Environment    : $Environment
- Build ID       : $BuildId
- Status         : Deployed & Assigned
- GitHub Run     : $runUrl
- Runner Host    : $runnerHost
- Completion Time: $((Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss UTC"))
"@
        } else {
@"
[Intune App Factory - Deployment Failed]
Application deployment encountered an error in the GitHub Actions pipeline.
- Application ID : $AppId
- Environment    : $Environment
- Build ID       : $BuildId
- Failure Reason : $(if ($Message) { $Message } else { 'Review GitHub Actions workflow logs' })
- Workflow Run   : $runUrl
- Timestamp      : $((Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss UTC"))
"@
        }

        $closePayload = @{
            state       = $stateValue
            close_code  = $closeCode
            close_notes = $closeNoteText
            work_notes  = "Automated pipeline completion status: $Status. Closing SCTASK."
        } | ConvertTo-Json

        Write-Host "[SERVICENOW] Close Payload JSON:"
        Write-Host $closePayload

        if ($isMockExecution) {
            Write-Host "[SERVICENOW-MOCK] Simulated PATCH to $snowInstance/api/now/table/sc_task/$SysId"
            Write-Host "[SERVICENOW-MOCK] SCTASK record closed with state '$stateValue' ($closeCode)."
        } else {
            if (-not $SysId) {
                Write-Error "[SERVICENOW] Cannot close task: sys_id could not be resolved."
            }
            $targetUri = "$snowInstance/api/now/table/sc_task/$SysId"
            $res = Invoke-RestMethod -Uri $targetUri -Method Patch -Headers $headers -Body $closePayload
            Write-Host "[SERVICENOW] SCTASK ($SysId) closed successfully with state '$stateValue'."
        }
    }

    "CreateTask" {
        Write-Host "[SERVICENOW] Creating new SCTASK record (Standalone trigger)..."
        $createPayload = @{
            short_description = "Intune App Factory: Deploy $AppId to $Environment"
            description       = "Automated deployment task initiated by GitHub Actions run $runId (Build ID: $BuildId)"
            assignment_group  = "EUC Endpoint Management"
            state             = "2" # Work in Progress
            priority          = "3" # Moderate
        } | ConvertTo-Json

        Write-Host "[SERVICENOW] Create Payload JSON:"
        Write-Host $createPayload

        if ($isMockExecution) {
            Write-Host "[SERVICENOW-MOCK] Simulated POST to $snowInstance/api/now/table/sc_task"
            Write-Host "[SERVICENOW-MOCK] SCTASK record created: SCTASK0099999 (sys_id: mock_new_task_12345)"
            if ($env:GITHUB_OUTPUT) {
                Add-Content -Path $env:GITHUB_OUTPUT -Value "sctask_number=SCTASK0099999"
                Add-Content -Path $env:GITHUB_OUTPUT -Value "sctask_sys_id=mock_new_task_12345"
            }
        } else {
            $targetUri = "$snowInstance/api/now/table/sc_task"
            $res = Invoke-RestMethod -Uri $targetUri -Method Post -Headers $headers -Body $createPayload
            $newNumber = $res.result.number
            $newSysId = $res.result.sys_id
            Write-Host "[SERVICENOW] Created SCTASK $newNumber (sys_id: $newSysId)"
            if ($env:GITHUB_OUTPUT) {
                Add-Content -Path $env:GITHUB_OUTPUT -Value "sctask_number=$newNumber"
                Add-Content -Path $env:GITHUB_OUTPUT -Value "sctask_sys_id=$newSysId"
            }
        }
    }

    default {
        Write-Error "[SERVICENOW] Invalid action: $Action"
    }
}

Write-Host "===================================================================="
Write-Host "[SERVICENOW] Integration execution completed successfully."
Write-Host "===================================================================="
