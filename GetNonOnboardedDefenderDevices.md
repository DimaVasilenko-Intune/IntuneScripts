# Get-NonOnboardedDefenderDevices.ps1

## 🧭 Overview
This PowerShell script connects to both **Microsoft Intune** and **Microsoft Defender for Endpoint** in a single run.  
It retrieves all managed devices from Intune and all onboarded devices from Defender, then compares them by `azureADDeviceId`.

The result is a **CSV report** listing every Intune device **not onboarded** to Defender for Endpoint.

---

## ⚙️ Features
- ✅ Single sign-on (SSO) login to Microsoft Graph  
- ✅ Automatic Azure CLI token retrieval for Defender API  
- ✅ No app registration or Global Admin consent needed  
- ✅ Works for Intune Admins and Security Admins  
- ✅ Produces one clean CSV file with non-onboarded devices  
- ✅ 100% read-only – no changes are made in the tenant  

---

## 📋 Requirements
| Component | Purpose | Notes |
|------------|----------|-------|
| **PowerShell 5.1+** | Run the script | Windows built-in |
| **Microsoft.Graph PowerShell module** | Retrieve Intune devices | Script auto-installs if missing |
| **Azure CLI** | Retrieve Defender devices | [Download here](https://learn.microsoft.com/cli/azure/install-azure-cli) |
| **Roles** | Access permissions | Intune Admin or Endpoint Security Admin, plus Security Reader/Admin for Defender |
| **Internet access** | API communication | Required |

---

## 🚀 How to Run

1. **Open PowerShell as Administrator**
   ```powershell
   cd "C:\Path\To\ScriptFolder"
Run the script

powershell
Copy code
.\Get-NonOnboardedDefenderDevices.ps1
When prompted:

Sign in with your Microsoft 365 account (SSO window will open).

If you’re not already signed in to Azure CLI, the script will automatically start az login.

Choose where to save the CSV file when the save dialog appears.

Done!
You’ll get output similar to:

css
Copy code
✅ Found 450 devices in Intune.
✅ Found 437 devices in Defender.
🚫 Found 13 devices NOT onboarded to Defender for Endpoint.
💾 CSV exported to: C:\Reports\NonOnboardedDevices-20251031-1530.csv
🧾 CSV Output
DeviceName	OperatingSystem	UserPrincipalName	ComplianceState	LastSyncDateTime	EnrollmentType	AzureADDeviceId
LAPTOP-001	Windows 11	user@company.com	Compliant	2025-10-31	Autopilot	1234-abcd-5678
PC-102	Windows 10	john@company.com	NonCompliant	2025-10-30	Manual	9876-abcd-5432

🔍 What Happens Behind the Scenes
Connects to Microsoft Graph using your credentials → reads Intune devices.

Authenticates silently to Defender API via your Azure CLI session.

Fetches all onboarded Defender machines.

Compares both lists locally (no tenant impact).

Exports non-onboarded results to a CSV report.

The script performs only read operations – it never modifies Intune, Defender, or Entra data.

⚠️ Common Issues
Issue	Explanation	Fix
az : The term 'az' is not recognized	Azure CLI not installed	Install Azure CLI
Failed to connect to Microsoft Graph	Missing permissions or MFA expired	Re-run script and sign in again
Access denied on Defender API	Account lacks Defender roles	Ask Security Admin to grant Security Reader or Security Admin role
CSV is empty	All Intune devices are already onboarded	✅ Normal – nothing to fix

🧠 Pro Tip
To re-run regularly (e.g., weekly compliance checks), you can schedule the script via Task Scheduler or Azure Automation.
Only the first run may require interactive sign-ins; future runs reuse your cached logins.

Author: Dima Vasilenko
Version: 1.0