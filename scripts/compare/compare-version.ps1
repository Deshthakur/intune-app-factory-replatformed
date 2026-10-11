<#
.SYNOPSIS
    Stage 4: Compare Requested vs Deployed Application Version
.DESCRIPTION
    Queries target environment (Intune Graph API / Azure VMSS) to compare current deployed version 
    against requested version. Supports skipping redundant deployments in Standard mode.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$AppId,
    [Parameter(Mandatory = $true)][string]$Environment,
    [Parameter(Mandatory = $true)][string]$RequestedVersion,
    [Parameter(Mandatory = $true)][string]$DeploymentMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "===================================================================="
Write-Host "STAGE 4: COMPARE APPLICATION VERSIONS"
Write-Host "Application ID    : $AppId"
Write-Host "Environment       : $Environment"
Write-Host "Requested Version : $RequestedVersion"
Write-Host "Deployment Mode   : $DeploymentMode"
Write-Host "===================================================================="

$skipDeployment = "false"

# Query Intune Graph API / Azure VMSS for existing deployed version placeholder
$currentDeployedVersion = "0.0.0" # Simulated baseline query result

Write-Host "[COMPARE] Current deployed version in target environment: $currentDeployedVersion"
Write-Host "[COMPARE] Target requested pipeline version           : $RequestedVersion"

if ($DeploymentMode -eq "Force") {
    Write-Host "[COMPARE] DeploymentMode='Force' active. Pipeline will proceed regardless of version match."
    $skipDeployment = "false"
} elseif ($RequestedVersion -eq $currentDeployedVersion -and $DeploymentMode -eq "Standard") {
    Write-Host "[COMPARE] Requested version matches currently deployed version ($RequestedVersion). Skipping redundant deployment."
    $skipDeployment = "true"
} else {
    Write-Host "[COMPARE] Version delta detected ($currentDeployedVersion -> $RequestedVersion). Proceeding with deployment."
    $skipDeployment = "false"
}

if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "skip_deployment=$skipDeployment"
}

Write-Host "[COMPARE] Stage 4 completed successfully. Skip Flag: $skipDeployment"
