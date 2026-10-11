<#
.SYNOPSIS
    Stage 1: Initialize Script
.DESCRIPTION
    Loads application YAML configuration, validates basic parameters, generates unique build ID,
    and sets GITHUB_OUTPUT environment variables for downstream pipeline stages.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$AppId,
    [Parameter(Mandatory = $true)][string]$Environment,
    [Parameter(Mandatory = $false)][string]$VersionOverride,
    [Parameter(Mandatory = $true)][string]$DeploymentMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "===================================================================="
Write-Host "STAGE 1: INITIALIZE APPLICATION PIPELINE"
Write-Host "Application ID  : $AppId"
Write-Host "Environment     : $Environment"
Write-Host "Deployment Mode : $DeploymentMode"
Write-Host "===================================================================="

# Locate application configuration YAML file
$workspaceDir = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Item .).FullName }
$configFile = Join-Path $workspaceDir "config\applications\$AppId.yml"

if (-not (Test-Path $configFile)) {
    Write-Error "CRITICAL: Application configuration file not found at: $configFile"
}

Write-Host "[INIT] Parsing configuration file: $configFile"
$rawYaml = Get-Content -Path $configFile -Raw

# Helper to extract key from YAML line without external library dependency
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

if (-not $appName) { $appName = $AppId }
if (-not $targetPlatform) { $targetPlatform = "Intune_Win32" }

# Override version if requested via workflow_dispatch
if ($VersionOverride -and $VersionOverride.Trim() -ne "") {
    Write-Host "[INIT] Version override provided: $VersionOverride (Original: $appVersion)"
    $appVersion = $VersionOverride.Trim()
}

# Generate deployment build ID
$timestamp = Get-Date -Format "yyyyMMddHHmmss"
$guidSnippet = [guid]::NewGuid().ToString().Substring(0, 6)
$buildId = "${AppId}-${Environment}-${timestamp}-${guidSnippet}"

Write-Host "[INIT] App Name       : $appName"
Write-Host "[INIT] App Version    : $appVersion"
Write-Host "[INIT] Target Platform: $targetPlatform"
Write-Host "[INIT] Generated Build ID: $buildId"

# Export values to GitHub Actions Output
if ($env:GITHUB_OUTPUT) {
    Add-Content -Path $env:GITHUB_OUTPUT -Value "build_id=$buildId"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "app_name=$appName"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "app_version=$appVersion"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "target_platform=$targetPlatform"
    Add-Content -Path $env:GITHUB_OUTPUT -Value "config_file=$configFile"
}

Write-Host "[INIT] Stage 1 completed successfully."
