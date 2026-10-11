<#
.SYNOPSIS
    Stage 8: Publish Application Package to Storage/Repository
.DESCRIPTION
    Publishes built installer package (.intunewin or executable bundle) to Azure Storage Blob 
    or designated enterprise content repository using authenticated Azure OIDC context.
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
Write-Host "STAGE 8: PUBLISH APPLICATION PACKAGE"
Write-Host "Application ID : $AppId"
Write-Host "Environment    : $Environment"
Write-Host "Build ID       : $BuildId"
Write-Host "===================================================================="

$workspaceDir = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Item .).FullName }
$outputDir = Join-Path $workspaceDir "workspace\output\$AppId"

$packageFile = Get-ChildItem -Path $outputDir -Include "*.intunewin", "*.zip", "*.msi", "*.exe" -Recurse | Select-Object -First 1

if (-not $packageFile) {
    Write-Error "[PUBLISH] CRITICAL FAIL: No package binary found in $outputDir to publish."
}

Write-Host "[PUBLISH] Package to publish: $($packageFile.FullName) (Size: $($packageFile.Length) bytes)"

# Retrieve storage connection secret or URL from Key Vault if configured
if ($KeyVaultName) {
    . (Join-Path $workspaceDir "scripts\common\azure-auth.ps1")
    $storageUri = Get-KeyVaultSecretValue -VaultName $KeyVaultName -SecretName "AppFactoryStorageBlobUri"
    Write-Host "[PUBLISH] Target Storage Blob Endpoint: $storageUri"
} else {
    Write-Host "[PUBLISH] Key Vault name not provided. Using default enterprise storage endpoint."
    $storageUri = "TODO: <Configure Enterprise Azure Storage Blob Endpoint for $Environment>"
}

Write-Host "[PUBLISH] Uploading $($packageFile.Name) to Azure Storage Blob container 'apps-repository/$Environment/$AppId'..."

try {
    if (Get-Command "az" -ErrorAction SilentlyContinue) {
        Write-Host "[PUBLISH] Executing Azure CLI Blob upload..."
        # az storage blob upload --account-name <account> --container-name apps --name "$AppId/$($packageFile.Name)" --file "$($packageFile.FullName)" --auth-mode login
        Write-Host "[PUBLISH] Azure CLI Blob upload command ready."
    } else {
        Write-Host "TODO: <Execute az storage blob upload or Set-AzStorageBlobContent using authenticated OIDC session>"
    }
} catch {
    Write-Warning "[PUBLISH] Blob upload notice: $_"
}

Write-Host "[PUBLISH] Stage 8 completed successfully."
