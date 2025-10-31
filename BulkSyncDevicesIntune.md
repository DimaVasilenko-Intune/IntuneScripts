# 🔄 BulkSyncDevicesIntune.ps1

## 📘 Description
This PowerShell script connects to Microsoft Graph and triggers a **device sync** for every managed device in your Intune tenant.  
It uses your normal **SSO login**, requires no app registration, and exports a CSV log with the result.

---

## ⚙️ Requirements
- PowerShell 5.1 or higher  
- Microsoft.Graph PowerShell module  
- Intune Administrator or Endpoint Security Administrator and/or Global admin 
- Network access to `graph.microsoft.com`

Install module (if missing):
```powershell
Install-Module Microsoft.Graph.DeviceManagement -Scope CurrentUser
