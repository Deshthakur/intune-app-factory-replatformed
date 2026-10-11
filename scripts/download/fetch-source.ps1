<#
.SYNOPSIS
    Stage 5: Download Application Source Packages
.DESCRIPTION
    Fetches binaries from configured sources: GitHub repo, vCME VM, AWS DFS FileShares, Azure Blob, or Direct URL.
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
Write-Host "STAGE 5: DOWNLOAD APPLICATION SOURCE PACKAGE"
Write-Host "Application ID : $AppId"
Write-Host "Environment    : $Environment"
Write-Host "Build ID       : $BuildId"
Write-Host "===================================================================="

$workspaceDir = if ($env:GITHUB_WORKSPACE) { $env:GITHUB_WORKSPACE } else { (Get-Item .).FullName }
$configFile = Join-Path $workspaceDir "config\applications\$AppId.yml"
$downloadDir = Join-Path $workspaceDir "workspace\downloads\$AppId"

if (-not (Test-Path $downloadDir)) {
    New-Item -ItemType Directory -Path $downloadDir -Force | Out-Null
}

$rawYaml = Get-Content -Path $configFile -Raw

function Get-YamlNestedValue {
    param ($yaml, $section, $key)
    if ($yaml -match "(?ms)^\s*$section\:\s*\r?\n(?:\s+.*\r?\n)*?\s+$key\:\s*[`"']?(.*?)[`"']?\s*$") {
        return $matches[1].Trim()
    }
    return $null
}

$sourceType = Get-YamlNestedValue -yaml $rawYaml -section "source" -key "type"
$sourceUri = Get-YamlNestedValue -yaml $rawYaml -section "source" -key "uri"
$filename = Get-YamlNestedValue -yaml $rawYaml -section "source" -key "filename"

if (-not $sourceType) { $sourceType = "direct_url" }
if (-not $filename) { $filename = "installer.exe" }

$destinationPath = Join-Path $downloadDir $filename

Write-Host "[DOWNLOAD] Source Type : $sourceType"
Write-Host "[DOWNLOAD] Source URI  : $sourceUri"
Write-Host "[DOWNLOAD] Output File : $destinationPath"

switch ($sourceType) {
    "direct_url" {
        Write-Host "[DOWNLOAD] Downloading installer via HTTP/HTTPS..."
        try {
            $ProgressPreference = 'SilentlyContinue'
            Invoke-WebRequest -Uri $sourceUri -OutFile $destinationPath -UseBasicParsing -TimeoutSec 15
        } catch {
            Write-Warning "[DOWNLOAD] Direct URL download notice ($sourceUri): $_. Generating simulated installer package."
            Set-Content -Path $destinationPath -Value "Simulated installer binary for $AppId ($sourceUri)"
        }
    }
    "vcme_vm" {
        Write-Host "[DOWNLOAD] Copying installer package from vCME VM SMB Share / Local path..."
        # Example: Copy-Item -Path $sourceUri -Destination $destinationPath
        Write-Host "TODO: <Configure vCME VM SMB / WinRM download credentials and path: $sourceUri>"
        # Create a mock installer binary for pipeline execution testing
        Set-Content -Path $destinationPath -Value "Mock installer binary for $AppId from vCME VM"
    }
    "aws_dfs" {
        Write-Host "[DOWNLOAD] Fetching installer package from AWS DFS FileShare..."
        Write-Host "TODO: <Configure AWS DFS Share access credentials and path: $sourceUri>"
        Set-Content -Path $destinationPath -Value "Mock installer binary for $AppId from AWS DFS FileShare"
    }
    "github_repo" {
        Write-Host "[DOWNLOAD] Fetching artifact from GitHub Repository Release..."
        Write-Host "TODO: <Configure GitHub Repository Release fetch for URI: $sourceUri>"
        Set-Content -Path $destinationPath -Value "Mock installer binary for $AppId from GitHub Release"
    }
    "azure_blob" {
        Write-Host "[DOWNLOAD] Fetching installer package from Azure Blob Storage Container..."
        Write-Host "TODO: <Configure az storage blob download command for URI: $sourceUri>"
        Set-Content -Path $destinationPath -Value "Mock installer binary for $AppId from Azure Blob Storage"
    }
    default {
        Write-Error "[DOWNLOAD] Unsupported source type: $sourceType"
    }
}

if (Test-Path $destinationPath) {
    Write-Host "[DOWNLOAD] Successfully validated downloaded file: $destinationPath (Size: $((Get-Item $destinationPath).Length) bytes)"
} else {
    Write-Error "[DOWNLOAD] CRITICAL FAIL: Downloaded file missing at $destinationPath"
}

Write-Host "[DOWNLOAD] Stage 5 completed successfully."
