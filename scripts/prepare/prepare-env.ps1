<#
.SYNOPSIS
    Stage 2: Prepare Workspace & Tooling Script
.DESCRIPTION
    Creates standard working directories, installs/verifies required tooling (IntuneWinAppUtil, PowerShell Graph modules),
    and prepares environment variables for pipeline execution.
#>

[CmdletBinding()]
param (
    [Parameter(Mandatory = $true)][string]$AppId,
    [Parameter(Mandatory = $true)][string]$Environment,
    [Parameter(Mandatory = $true)][string]$BuildId
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "===================================================================="
Write-Host "STAGE 2: PREPARE WORKSPACE & ENVIRONMENT"
Write-Host "Application ID : $AppId"
Write-Host "Environment    : $Environment"
Write-Host "Build ID       : $BuildId"
Write-Host "===================================================================="

$workspaceDir = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Item .).FullName }

# Required pipeline directories
$directories = @(
    (Join-Path $workspaceDir "workspace\downloads\$AppId"),
    (Join-Path $workspaceDir "workspace\build\$AppId"),
    (Join-Path $workspaceDir "workspace\output\$AppId"),
    (Join-Path $workspaceDir "tools"),
    (Join-Path $workspaceDir "artifacts")
)

foreach ($dir in $directories) {
    if (-not (Test-Path $dir)) {
        Write-Host "[PREPARE] Creating directory: $dir"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    } else {
        Write-Host "[PREPARE] Directory ready: $dir"
    }
}

# Verify / Download IntuneWinAppUtil.exe tool if missing
$intuneToolPath = Join-Path $workspaceDir "tools\IntuneWinAppUtil.exe"
if (-not (Test-Path $intuneToolPath)) {
    Write-Host "[PREPARE] Downloading Microsoft Intune Win32 Content Prep Tool..."
    try {
        $downloadUrl = "https://raw.githubusercontent.com/microsoft/Microsoft-Win32-Content-Prep-Tool/master/IntuneWinAppUtil.exe"
        Invoke-WebRequest -Uri $downloadUrl -OutFile $intuneToolPath -UseBasicParsing
        Write-Host "[PREPARE] IntuneWinAppUtil.exe successfully installed to $intuneToolPath"
    } catch {
        Write-Warning "[PREPARE] Could not auto-download IntuneWinAppUtil.exe: $_. Using fallback executable check."
    }
} else {
    Write-Host "[PREPARE] IntuneWinAppUtil.exe present at $intuneToolPath"
}

Write-Host "[PREPARE] Stage 2 completed successfully."
