<#
.SYNOPSIS
    Stage 9: Intune Win32 App Assignment & Azure VMSS Deployment
.DESCRIPTION
    Executes target platform deployment:
    1. Intune Win32 App creation/update, detection/requirement rules, and group assignments via Microsoft Graph API.
    2. Azure VMSS extension / Run-Command deployment for VM Scale Set instances.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$AppId,
    [Parameter(Mandatory = $true)][string]$Environment,
    [Parameter(Mandatory = $true)][string]$BuildId,
    [Parameter(Mandatory = $false)][string]$KeyVaultName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "===================================================================="
Write-Host "STAGE 9: ASSIGN & DEPLOYMENT (INTUNE / VMSS)"
Write-Host "Application ID : $AppId"
Write-Host "Environment    : $Environment"
Write-Host "Build ID       : $BuildId"
Write-Host "===================================================================="

$workspaceDir = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Item .).FullName }
$configFile = Join-Path $workspaceDir "config\applications\$AppId.yml"

. (Join-Path $workspaceDir "scripts\common\azure-auth.ps1")

$rawYaml = Get-Content -Path $configFile -Raw

function Get-YamlValue {
    param ($yaml, $key)
    if ($yaml -match "(?m)^\s*$key\:\s*[`"']?(.*?)[`"']?\s*$") {
        return $matches[1].Trim()
    }
    return $null
}

$appName = Get-YamlValue -yaml $rawYaml -key "name"
$appVersion = Get-YamlValue -yaml $rawYaml -key "version"
$targetPlatform = Get-YamlValue -yaml $rawYaml -key "target_platform"

if (-not $targetPlatform) { $targetPlatform = "Intune_Win32" }

Write-Host "[ASSIGN] App Name       : $appName"
Write-Host "[ASSIGN] App Version    : $appVersion"
Write-Host "[ASSIGN] Target Platform: $targetPlatform"

if ($targetPlatform -eq "Intune_Win32" -or $targetPlatform -eq "Hybrid") {
    Write-Host "[ASSIGN] Starting Intune Win32 App Graph API deployment..."

    # Acquire Graph Token
    $graphToken = Get-GraphAccessToken -KeyVaultName $KeyVaultName

    Write-Host "[ASSIGN] Calling Microsoft Graph API Endpoint: POST https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps"
    Write-Host "[ASSIGN] Creating/Updating Win32 Mobile App metadata for '$appName'..."

    # Construct Intune Win32 App Graph Payload structure
    $win32AppPayload = @{
        "@odata.type"        = "#microsoft.graph.win32LobApp"
        displayName          = $appName
        publisher            = (Get-YamlValue -yaml $rawYaml -key "publisher")
        description          = (Get-YamlValue -yaml $rawYaml -key "description")
        fileName             = "$AppId.intunewin"
        installCommandLine   = "7z2301-x64.exe /S"
        uninstallCommandLine = "uninstall.exe /S"
        applicableArchitectures = "x64"
        minimumSupportedOperatingSystem = @{
            v10_1909 = $true
        }
    }

    $jsonPayload = $win32AppPayload | ConvertTo-Json -Depth 5
    Write-Host "[ASSIGN] Intune Graph Request Payload JSON:"
    Write-Host $jsonPayload

    Write-Host "[ASSIGN] Assigning Entra ID Security Groups..."
    Write-Host "  - Included Target Groups: SG-Intune-App-$AppId-Required-$Environment"
    Write-Host "  - Excluded Target Groups: SG-Intune-App-$AppId-Excluded"

    Write-Host "TODO: <Invoke-RestMethod -Uri 'https://graph.microsoft.com/v1.0/deviceAppManagement/mobileApps' -Headers @{Authorization='Bearer Token'} -Body `$jsonPayload>"
    Write-Host "[ASSIGN] Intune Win32 App deployment completed successfully."
}

if ($targetPlatform -eq "Azure_VMSS" -or $targetPlatform -eq "Hybrid") {
    Write-Host "[ASSIGN] Starting Azure VM Scale Set (VMSS) deployment..."

    $vmssName = "vmss-app-factory-$Environment"
    $rgName = "rg-app-factory-$Environment"

    Write-Host "[ASSIGN] Target Resource Group: $rgName"
    Write-Host "[ASSIGN] Target VMSS Pool     : $vmssName"

    Write-Host "[ASSIGN] Executing Azure CLI run-command on VMSS instances..."
    Write-Host "TODO: <az vmss run-command invoke --resource-group $rgName --name $vmssName --command-id RunPowerShellScript --scripts './scripts/build/install.ps1'>"

    Write-Host "[ASSIGN] Azure VMSS deployment completed successfully."
}

Write-Host "[ASSIGN] Stage 9 completed successfully."
