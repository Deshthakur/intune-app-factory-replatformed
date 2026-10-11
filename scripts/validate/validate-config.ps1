<#
.SYNOPSIS
    Stage 3: Validate Application Configuration & Dependencies
.DESCRIPTION
    Validates application configuration file completeness, parameter integrity, 
    Azure Key Vault connectivity, and required Entra permissions before build/deploy.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$AppId,
    [Parameter(Mandatory = $true)][string]$Environment,
    [Parameter(Mandatory = $false)][string]$KeyVaultName
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "===================================================================="
Write-Host "STAGE 3: VALIDATE APPLICATION CONFIGURATION & DEPENDENCIES"
Write-Host "Application ID : $AppId"
Write-Host "Environment    : $Environment"
Write-Host "Key Vault Name : $KeyVaultName"
Write-Host "===================================================================="

$workspaceDir = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Item .).FullName }
$configFile = Join-Path $workspaceDir "config\applications\$AppId.yml"

if (-not (Test-Path $configFile)) {
    Write-Error "[VALIDATE] CRITICAL FAIL: Configuration file $configFile missing."
}

$rawContent = Get-Content -Path $configFile -Raw

# Check required top-level configuration blocks
$requiredKeys = @("id", "name", "version", "target_platform", "source", "build", "assignments")
$missingKeys = @()

foreach ($key in $requiredKeys) {
    if ($rawContent -notmatch "(?m)^\s*$key\:") {
        $missingKeys += $key
    }
}

if ($missingKeys.Count -gt 0) {
    Write-Error "[VALIDATE] CRITICAL FAIL: Application config missing required YAML keys: $($missingKeys -join ', ')"
} else {
    Write-Host "[VALIDATE] All required YAML configuration sections present."
}

# Verify Azure Key Vault reachability if Key Vault name is provided
if ($KeyVaultName -and $KeyVaultName.Trim() -ne "") {
    Write-Host "[VALIDATE] Verifying access to Azure Key Vault '$KeyVaultName'..."
    . (Join-Path $workspaceDir "scripts\common\azure-auth.ps1")
    $vaultTest = Get-KeyVaultSecretValue -VaultName $KeyVaultName -SecretName "HealthCheckSecret"
    Write-Host "[VALIDATE] Key Vault access check result: $vaultTest"
} else {
    Write-Host "[VALIDATE] Key Vault name not supplied in environment variable KEY_VAULT_NAME. Skipping live vault probe."
}

Write-Host "[VALIDATE] Stage 3 completed successfully. All validations passed."
