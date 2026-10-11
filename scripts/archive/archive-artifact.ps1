<#
.SYNOPSIS
    Stage 7: Archive Pipeline Artifacts
.DESCRIPTION
    Bundles build outputs, logs, and deployment manifests into an archive bundle 
    named app-version-buildnumber.zip for GitHub Actions artifact retention.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$AppId,
    [Parameter(Mandatory = $true)][string]$AppVersion,
    [Parameter(Mandatory = $true)][string]$BuildId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "===================================================================="
Write-Host "STAGE 7: ARCHIVE PIPELINE ARTIFACTS"
Write-Host "Application ID : $AppId"
Write-Host "App Version    : $AppVersion"
Write-Host "Build ID       : $BuildId"
Write-Host "===================================================================="

$workspaceDir = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Item .).FullName }
$outputDir = Join-Path $workspaceDir "workspace\output\$AppId"
$artifactsDir = Join-Path $workspaceDir "artifacts"

if (-not (Test-Path $artifactsDir)) {
    New-Item -ItemType Directory -Path $artifactsDir -Force | Out-Null
}

# Generate deployment manifest
$manifest = @{
    AppId       = $AppId
    AppVersion  = $AppVersion
    BuildId     = $BuildId
    Timestamp   = (Get-Date -Format "o")
    MachineName = $env:COMPUTERNAME
}

$manifestPath = Join-Path $outputDir "manifest.json"
$manifest | ConvertTo-Json -Depth 5 | Set-Content -Path $manifestPath

# Package into ZIP archive
$zipName = "${AppId}-${AppVersion}-${BuildId}.zip"
$zipPath = Join-Path $artifactsDir $zipName

Write-Host "[ARCHIVE] Compressing output artifacts into $zipPath..."
Compress-Archive -Path (Join-Path $outputDir "*") -DestinationPath $zipPath -Force

Write-Host "[ARCHIVE] Successfully generated artifact bundle: $zipPath (Size: $((Get-Item $zipPath).Length) bytes)"
Write-Host "[ARCHIVE] Stage 7 completed successfully."
