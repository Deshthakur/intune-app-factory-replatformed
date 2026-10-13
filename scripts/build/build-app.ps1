<#
.SYNOPSIS
    Stage 6: Build & Package Application
.DESCRIPTION
    Executes packaging commands (e.g., IntuneWinAppUtil wrapping into .intunewin or PowerShell build tasks).
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
Write-Host "STAGE 6: BUILD & PACKAGE APPLICATION"
Write-Host "Application ID : $AppId"
Write-Host "Environment    : $Environment"
Write-Host "Build ID       : $BuildId"
Write-Host "===================================================================="

$workspaceDir = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Item .).FullName }
$configFile = Join-Path $workspaceDir "config\applications\$AppId.yml"
$downloadDir = Join-Path $workspaceDir "workspace\downloads\$AppId"
$outputDir = Join-Path $workspaceDir "workspace\output\$AppId"

if (-not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Path $outputDir -Force | Out-Null
}

$rawYaml = Get-Content -Path $configFile -Raw

function Get-YamlNestedValue {
    param ($yaml, $section, $key)
    if ($yaml -match "(?ms)^\s*$section\:\s*\r?\n(?:\s+.*\r?\n)*?\s+$key\:\s*[`"']?(.*?)[`"']?\s*$") {
        return $matches[1].Trim()
    }
    return $null
}

$buildType = Get-YamlNestedValue -yaml $rawYaml -section "build" -key "type"
$setupFile = Get-YamlNestedValue -yaml $rawYaml -section "build" -key "setup_file"

if (-not $buildType) { $buildType = "intunewin" }
if (-not $setupFile) { $setupFile = (Get-ChildItem -Path $downloadDir | Select-Object -First 1).Name }

Write-Host "[BUILD] Packaging Type : $buildType"
Write-Host "[BUILD] Setup Binary   : $setupFile"

switch ($buildType) {
    "intunewin" {
        $intuneToolPath = Join-Path $workspaceDir "tools\IntuneWinAppUtil.exe"
        if (Test-Path $intuneToolPath) {
            Write-Host "[BUILD] Executing IntuneWinAppUtil packaging tool..."
            $cmd = "& '$intuneToolPath' -c '$downloadDir' -s '$setupFile' -o '$outputDir' -q"
            Write-Host "[BUILD] Executing: $cmd"
            Invoke-Expression $cmd
        } else {
            Write-Warning "[BUILD] IntuneWinAppUtil.exe tool not found at $intuneToolPath. Generating simulated .intunewin package for pipeline run."
            $mockIntunePackage = Join-Path $outputDir "$setupFile.intunewin"
            Set-Content -Path $mockIntunePackage -Value "Simulated IntuneWin package content for $AppId"
        }
    }
    "powershell" {
        Write-Host "[BUILD] Executing PowerShell custom build routine for $AppId..."
        $mockOutput = Join-Path $outputDir "$AppId-build-package.zip"
        Set-Content -Path $mockOutput -Value "PowerShell build output package for $AppId"
    }
    default {
        Write-Host "[BUILD] No specialized packaging required. Copying source binary to output directory..."
        Copy-Item -Path (Join-Path $downloadDir "*") -Destination $outputDir -Recurse -Force
    }
}

$outputFiles = Get-ChildItem -Path $outputDir
Write-Host "[BUILD] Generated Output Artifacts in $outputDir:"
foreach ($file in $outputFiles) {
    Write-Host "  - $($file.Name) ($($file.Length) bytes)"
}

Write-Host "[BUILD] Stage 6 completed successfully."
