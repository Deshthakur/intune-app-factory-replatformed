# Intune App Factory – Replatformed Architecture CI/CD Automation Framework

Welcome to the enterprise-grade, configuration-driven **Intune App Factory** CI/CD automation framework. This repository provides a scalable, secure, and unified GitHub Actions pipeline capable of building, packaging, publishing, and deploying **approximately 30 applications** (and beyond) without repeating workflow code.

---

## 🏛️ Architecture & System Topology

```
                  ┌────────────────────────────────────────────────────────┐
                  │              Application Sources                       │
                  │  - vCME VM  - AWS DFS FileShare  - GitHub  - Azure Blob│
                  └───────────────────────────┬────────────────────────────┘
                                              │
                                              ▼
┌─────────────────────────────────────────────────────────────────────────────────────────────┐
│                                    GitHub Actions Automation                                │
│                                                                                             │
│  .github/workflows/application.yml  ──────►  .github/workflows/reusable-application.yml     │
│  (Main Dispatch & App Discovery)             (Reusable 9-Stage Pipeline)                    │
│                                                                                             │
│    ┌──────────────┬──────────────┬──────────────┬──────────────┬──────────────┐             │
│    │ 1.Initialize │ 2. Prepare   │ 3. Validate  │ 4. Compare   │ 5. Download  │             │
│    └──────┬───────┴──────┬───────┴──────┬───────┴──────┬───────┴──────┬───────┘             │
│           │              │              │              │              │                     │
│           ▼              ▼              ▼              ▼              ▼                     │
│    ┌──────────────┬──────────────┬──────────────┬──────────────┐                            │
│    │ 6. Build     │ 7. Archive   │ 8. Publish   │ 9. Assign    │                            │
│    └──────────────┴──────────────┴──────────────┴──────┬───────┘                            │
└────────────────────────────────────────────────────────┼────────────────────────────────────┘
                                                         │
         ┌───────────────────────────────────────────────┼────────────────────────────────┐
         │                                               │                                │
         ▼                                               ▼                                ▼
┌──────────────────────┐                     ┌──────────────────────┐         ┌──────────────────────┐
│ Microsoft Entra ID   │                     │ Azure Services       │         │ ServiceNow ITSM      │
│ (OIDC Auth / WIF)    │                     │ - Azure Key Vault    │         │ - Create SCTASK      │
│                      │                     │ - Azure VMSS         │         │ - Approval Check     │
│ Microsoft Graph API  │                     │ - Azure Monitor / LA │         │ - Close SCTASK       │
│ (Intune Win32 Apps)  │                     │ - Azure Blob Storage │         │                      │
└──────────────────────┘                     └──────────────────────┘         └──────────────────────┘
```

---

## 📁 Repository Structure

```
.github/
  workflows/
    application.yml             # Main trigger workflow with workflow_dispatch & app discovery
    reusable-application.yml    # Reusable workflow containing the 9 sequential pipeline stages

config/
  schema-app-config.json        # JSON Schema for validating application YAML configurations
  applications/
    app01-7zip.yml              # Sample config: 7-Zip Enterprise (Intune Win32 App target)
    app02-vscode.yml            # Sample config: VS Code (Azure VMSS target)
    ...                         # Add app03.yml through app30.yml here

scripts/
  common/
    azure-auth.ps1              # Helper module for OIDC token acquisition & Key Vault lookup
  initialize/
    init-app.ps1                # Stage 1: Load config, generate Build ID, set outputs
  prepare/
    prepare-env.ps1             # Stage 2: Create directories, install IntuneWinAppUtil
  validate/
    validate-config.ps1         # Stage 3: Schema validation, Key Vault & permission checks
  compare/
    compare-version.ps1         # Stage 4: Version comparison vs Intune/VMSS baseline
  download/
    fetch-source.ps1            # Stage 5: Fetch installer from GitHub/vCME/AWS DFS/Blob
  build/
    build-app.ps1              # Stage 6: Build/Package installer into .intunewin or executable
  archive/
    archive-artifact.ps1        # Stage 7: Generate zip bundle (app-version-buildnumber.zip)
  publish/
    publish-package.ps1         # Stage 8: Upload package to Azure Storage Blob repository
  assign/
    deploy-intune-vmss.ps1      # Stage 9: Graph API Win32 deployment & VMSS run-command
  servicenow/
    servicenow-integration.ps1  # ServiceNow SCTASK creation, update, and closure helper
```

---

## 🔒 1. Complete Authentication Flow

This framework eliminates long-lived credentials by leveraging **GitHub Actions OpenID Connect (OIDC)** federated with **Microsoft Entra ID Workload Identity Federation**.

```
GitHub Actions Runner
      │
      │ (1) Request OIDC JWT Token
      ▼
GitHub OIDC Identity Provider (token.actions.githubusercontent.com)
      │
      │ (2) Returns Signed JWT Token with repository & environment claims
      ▼
Azure Login Action (azure/login@v2)
      │
      │ (3) Exchanges JWT Token with Entra ID (login.microsoftonline.com)
      ▼
Microsoft Entra ID (Workload Identity Federation)
      │
      │ (4) Validates claims & issues short-lived Azure Access Token
      ▼
Azure & Microsoft Graph API Context
      ├─► Access Azure Key Vault (Fetch secrets dynamically at runtime)
      ├─► Microsoft Graph API (Deploy Win32 Apps & Manage Intune Assignments)
      └─► Azure VM Scale Sets (Execute VMSS custom deployment commands)
```

### Required Workflow Permissions
```yaml
permissions:
  id-token: write  # Mandatory for acquiring OIDC token
  contents: read   # Mandatory for checking out repository code
```

### Azure Credentials in GitHub Secrets / Variables
No client secrets are stored in GitHub repository settings. Only non-sensitive identity GUIDs are configured:
- `AZURE_CLIENT_ID`: Entra ID Application / Managed Identity Client ID
- `AZURE_TENANT_ID`: Microsoft Entra ID Tenant ID
- `AZURE_SUBSCRIPTION_ID`: Target Azure Subscription ID
- `KEY_VAULT_NAME`: Target Azure Key Vault Name (per environment)

---

## 🔄 2. The 9 Pipeline Stages Breakdown

The reusable workflow (`reusable-application.yml`) organizes execution into 9 sequential jobs:

| Stage # | Stage Name | Responsibility | Main Script |
| :--- | :--- | :--- | :--- |
| **1** | **Initialize** | Parses application configuration, validates inputs, generates unique `BuildId`. | `scripts/initialize/init-app.ps1` |
| **2** | **Prepare** | Creates workspace directories (`workspace/downloads`, `workspace/output`, `tools`, `artifacts`) and downloads `IntuneWinAppUtil.exe`. | `scripts/prepare/prepare-env.ps1` |
| **3** | **Validate** | Performs schema validation, checks Key Vault connectivity and Entra permissions. Fails early on missing requirements. | `scripts/validate/validate-config.ps1` |
| **4** | **Compare** | Compares requested app version against baseline deployed in Intune/VMSS. Sets `skip_deployment=true` if identical in `Standard` mode. | `scripts/compare/compare-version.ps1` |
| **5** | **Download** | Fetches installer package from configured source (`vCME VM`, `AWS DFS FileShare`, `GitHub`, or `Azure Blob`). | `scripts/download/fetch-source.ps1` |
| **6** | **Build** | Wraps setup installer into `.intunewin` package using `IntuneWinAppUtil.exe` or executes PowerShell build tasks. | `scripts/build/build-app.ps1` |
| **7** | **Archive** | Bundles package and metadata manifest into `app-version-buildnumber.zip` and uploads to GitHub Artifacts. | `scripts/archive/archive-artifact.ps1` |
| **8** | **Publish** | Uploads package binary to enterprise Azure Blob Storage repository under `apps-repository/{ENV}/{AppId}/`. | `scripts/publish/publish-package.ps1` |
| **9** | **Assign & Deploy** | Performs Intune Win32 App creation/update, requirement rules, group assignment via Microsoft Graph API, or updates VMSS instances. | `scripts/assign/deploy-intune-vmss.ps1` |

---

## 🎫 3. ServiceNow SCTASK & RTIM Integration

To guarantee ITIL compliance and change auditing, the pipeline automatically manages ServiceNow Service Requests (RTIM) and Change Tasks (SCTASK):

```
Pipeline Starts (Assign Stage)
      │
      ▼
Create ServiceNow SCTASK  ──►  Returns Task ID (e.g. SCTASK0094821)
      │
      ▼
Execute Intune / VMSS Deployment
      │
      ├─── [SUCCESS] ──► Update SCTASK State to Closed Complete (State=3)
      │
      └─── [FAILURE] ──► Update SCTASK State to Closed Incomplete (State=4) & Record Logs
```

ServiceNow instance credentials (`ServiceNowInstanceUrl`, `ServiceNowApiToken`) are dynamically fetched from Azure Key Vault at runtime.

---

## ⚙️ 4. Application Configuration Schema & Example

Applications are defined entirely inside YAML files located in `config/applications/`.

### Example 1: Intune Win32 App (`config/applications/app01-7zip.yml`)
```yaml
id: "app01-7zip"
name: "7-Zip 23.01 x64 Enterprise"
version: "23.01"
publisher: "Igor Pavlov"
description: "High-compression file archiver utility for enterprise deployment."
target_platform: "Intune_Win32"

source:
  type: "direct_url" # Options: github_repo, vcme_vm, aws_dfs, azure_blob, direct_url
  uri: "https://7-zip.org/a/7z2301-x64.exe"
  filename: "7z2301-x64.exe"

build:
  type: "intunewin"
  setup_file: "7z2301-x64.exe"
  install_command: "7z2301-x64.exe /S"
  uninstall_command: "\"C:\\Program Files\\7-Zip\\Uninstall.exe\" /S"

detection:
  type: "file"
  file_path: "C:\\Program Files\\7-Zip\\7z.exe"

requirements:
  os_architecture: "x64"
  minimum_supported_windows_release: "10_1909"

assignments:
  intent: "Required"
  included_groups:
    - "SG-Intune-App-7Zip-Required-DEV"
    - "SG-Intune-App-7Zip-Required-PROD"
  excluded_groups:
    - "SG-Intune-App-7Zip-Excluded"

servicenow:
  auto_approval: true
  assignment_group: "EUC Endpoint Management"
```

---

## 🚀 5. How 1 Workflow Supports 30 Applications (Scaling Guide)

Adding application **#31** requires **ZERO code or workflow modifications**:

### Step 1: Create Config File
Create a new file `config/applications/app31-mycustomapp.yml` following the schema above.

### Step 2: Push to Repository
Commit and push the configuration file to GitHub:
```bash
git add config/applications/app31-mycustomapp.yml
git commit -m "feat: Onboard App #31 - My Custom App"
git push origin main
```

### Step 3: Execute Pipeline
Navigate to **Actions** -> **Intune App Factory - Main Automation Workflow** -> **Run workflow**, select `app31-mycustomapp`, target environment, and hit **Run workflow**.

---

## 🛠️ 6. Zero to Hero Setup & Execution Guide

Follow these steps to configure your repository from scratch:

### Step 1: Configure Entra ID OIDC Federation
1. In Azure Portal -> Entra ID -> App Registrations -> Create registration: `app-factory-github-oidc`.
2. Under **Federated credentials**, add a credential:
   - Issuer: `https://token.actions.githubusercontent.com`
   - Subject identifier: `repo:<your-org>/<your-repo>:environment:<DEV/TEST/UAT/PROD>`
3. Assign RBAC Roles:
   - **Key Vault Secrets User** on Azure Key Vault.
   - **Contributor** or custom role on target Azure VMSS resource groups.
4. Assign Microsoft Graph API Application Permissions:
   - `DeviceAppManagement-Fluent.ReadWrite.All`
   - `Group.Read.All`

### Step 2: Configure GitHub Environments & Secrets
Create environments in GitHub Repository Settings -> **Environments**: `DEV`, `TEST`, `UAT`, `PROD`.

Add variables / secrets under each environment:
- `AZURE_CLIENT_ID`: `<App Registration Client ID>`
- `AZURE_TENANT_ID`: `<Entra Tenant ID>`
- `AZURE_SUBSCRIPTION_ID`: `<Subscription ID>`
- `KEY_VAULT_NAME`: `<Environment Key Vault Name>`

### Step 3: Triggering a Deployment
To deploy an application manually:
1. Go to GitHub Repository -> **Actions**.
2. Select **Intune App Factory - Main Automation Workflow**.
3. Fill in inputs:
   - **Application**: `app01-7zip` (or `ALL` to deploy matrix of all 30 apps)
   - **Target Environment**: `DEV`
   - **Version Override**: *(Optional)*
   - **Deployment Mode**: `Standard`
4. Click **Run workflow**.

---

## 📌 Placeholders & Enterprise Customization (`TODO` Tags)

All environment-specific endpoints and custom enterprise connectors are clearly tagged across scripts with `TODO:` markers:

- `scripts/common/azure-auth.ps1`: Key Vault secret lookup fallback.
- `scripts/download/fetch-source.ps1`: SMB / WinRM credentials for vCME VM & AWS DFS FileShares.
- `scripts/publish/publish-package.ps1`: Custom Azure Storage Blob endpoint.
- `scripts/assign/deploy-intune-vmss.ps1`: Microsoft Graph REST API endpoint call & Azure CLI VMSS run-command.
- `scripts/servicenow/servicenow-integration.ps1`: Enterprise ServiceNow instance table REST endpoint.

---

## 📜 License & Support
Managed by Senior DevOps & Cloud Architecture Team. Designed for high resilience, auditability, and zero workflow duplication across enterprise application suites.
