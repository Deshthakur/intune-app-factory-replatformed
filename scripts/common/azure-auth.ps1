<#
.SYNOPSIS
    Common Azure Authentication and Key Vault Helper Functions.
.DESCRIPTION
    Provides secure OIDC authentication context, Key Vault secret retrieval, 
    and Microsoft Graph access token generation without hardcoding secrets.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

function Get-KeyVaultSecretValue {
    param (
        [Parameter(Mandatory = $true)]
        [string]$VaultName,

        [Parameter(Mandatory = $true)]
        [string]$SecretName
    )

    Write-Host "[AZURE-AUTH] Fetching secret '$SecretName' from Key Vault '$VaultName'..."
    
    # Try fetching using Az module if available, otherwise az CLI
    try {
        if (Get-Command "Get-AzKeyVaultSecret" -ErrorAction SilentlyContinue) {
            $secret = Get-AzKeyVaultSecret -VaultName $VaultName -Name $SecretName -AsPlainText
            return $secret
        } elseif (Get-Command "az" -ErrorAction SilentlyContinue) {
            $secret = az keyvault secret show --vault-name $VaultName --name $SecretName --query "value" -o tsv
            return $secret
        } else {
            # Placeholder for fallback local environment testing
            Write-Warning "[AZURE-AUTH] Neither Az PowerShell module nor Azure CLI detected. Using fallback placeholder."
            return "TODO: <Configure Key Vault Secret '$SecretName' in Azure Key Vault '$VaultName'>"
        }
    } catch {
        Write-Warning "[AZURE-AUTH] Unable to retrieve secret '$SecretName' from Key Vault '$VaultName': $_"
        return "TODO: <Verify Key Vault Secret '$SecretName' exists in '$VaultName'>"
    }
}

function Get-GraphAccessToken {
    param (
        [Parameter(Mandatory = $false)]
        [string]$KeyVaultName
    )

    Write-Host "[AZURE-AUTH] Acquiring Microsoft Graph API access token via OIDC Workload Identity..."

    try {
        if (Get-Command "Get-AzAccessToken" -ErrorAction SilentlyContinue) {
            $tokenObj = Get-AzAccessToken -ResourceUrl "https://graph.microsoft.com"
            return $tokenObj.Token
        } elseif (Get-Command "az" -ErrorAction SilentlyContinue) {
            $token = az account get-access-token --resource-type ms-graph --query "accessToken" -o tsv
            return $token
        } else {
            Write-Warning "[AZURE-AUTH] No Azure login context available. Returning OIDC Graph token placeholder."
            return "TODO: <Microsoft Graph API Access Token acquired from azure/login@v2>"
        }
    } catch {
        Write-Error "[AZURE-AUTH] Failed to acquire Graph API Token: $_"
    }
}

Export-ModuleMember -Function Get-KeyVaultSecretValue, Get-GraphAccessToken -ErrorAction SilentlyContinue
