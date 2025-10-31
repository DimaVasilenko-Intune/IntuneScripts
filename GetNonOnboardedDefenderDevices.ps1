<#
.SYNOPSIS
Retrieves all Intune devices that are not onboarded to Microsoft Defender for Endpoint (MDE).

.DESCRIPTION
Connects interactively to Microsoft Graph (Intune) and Microsoft Defender (via Azure CLI).  
Forces credential prompts each run to ensure the correct tenant is used.  
Compares devices by AzureADDeviceId and exports a CSV report listing devices not onboarded to Defender for Endpoint.  
Automatically logs out from Azure CLI and Microsoft Graph when complete.

.OUTPUTS
CSV report with:
DeviceName, OperatingSystem, UserPrincipalName, ComplianceState, LastSyncDateTime, EnrollmentType, AzureADDeviceId

.REQUIREMENTS
- Microsoft.Graph PowerShell module installed
- Azure CLI installed
- Intune Admin or Endpoint Security Admin role
- Security Reader or Security Admin role (for Defender)
#>

Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Windows.Forms

Write-Host "-----------------------------------------------------------"
Write-Host "📋 Intune + Defender Device Audit Tool" -ForegroundColor Cyan
Write-Host "-----------------------------------------------------------`n"

# 1️⃣ Connect to Microsoft Graph (Intune)
Write-Host "🔐 Connecting to Microsoft Graph (Intune)..." -ForegroundColor Cyan
Connect-MgGraph -Scopes "DeviceManagementManagedDevices.Read.All" -ErrorAction SilentlyContinue | Out-Null

# Verify connection
try {
    $tenantInfo = Get-MgOrganization -ErrorAction Stop
    $tenantName = $tenantInfo.DisplayName
    Write-Host "🌐 Connected to tenant: $tenantName" -ForegroundColor Cyan
}
catch {
    Write-Host "❌ Could not confirm Graph connection. This tenant may require admin consent." -ForegroundColor Red
    Write-Host "➡️  Ask a Global Admin to approve: https://login.microsoftonline.com/common/adminconsent?client_id=14d82eec-204b-4c2f-b7e8-296a70dab67e" -ForegroundColor Yellow
    exit 1
}

# 2️⃣ Retrieve all Intune devices
Write-Host "📦 Fetching Intune managed devices..." -ForegroundColor Cyan
$intuneDevices = @()
$uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices"

do {
    try {
        $resp = Invoke-MgGraphRequest -Uri $uri -Method GET -ErrorAction Stop
        $intuneDevices += $resp.value
        $uri = $resp.'@odata.nextLink'
        Write-Progress -Activity "Fetching Intune devices" -Status "Retrieved $($intuneDevices.Count) devices..." -PercentComplete 0
    }
    catch {
        Write-Host "❌ Failed to retrieve Intune devices. Check your permissions or network connection." -ForegroundColor Red
        exit 1
    }
} while ($uri)

Write-Progress -Activity "Fetching Intune devices" -Completed
Write-Host "✅ Found $($intuneDevices.Count) devices in Intune." -ForegroundColor Green

# 3️⃣ Force new Azure CLI login for Defender API
Write-Host "`n🛡️ Signing in to Microsoft Defender API..." -ForegroundColor Cyan
try {
    az logout --only-show-errors | Out-Null
    Write-Host "🔑 Please sign in to the correct tenant when prompted..." -ForegroundColor Yellow
    az login --allow-no-subscriptions --only-show-errors | Out-Null
    $token = (az account get-access-token --resource https://api.securitycenter.microsoft.com --query accessToken -o tsv)
}
catch {
    Write-Error "❌ Azure CLI login failed. Ensure Azure CLI is installed and you have Defender access in the target tenant."
    exit 1
}

# 4️⃣ Retrieve Defender devices
Write-Host "📥 Fetching onboarded devices from Defender for Endpoint..." -ForegroundColor Cyan
$defenderDevices = @()
$defenderUri = "https://api.securitycenter.microsoft.com/api/machines"

do {
    try {
        $resp = Invoke-RestMethod -Uri $defenderUri -Headers @{ Authorization = "Bearer $token" } -Method GET -ErrorAction Stop
        $defenderDevices += $resp.value
        $defenderUri = $resp.'@odata.nextLink'
        Write-Progress -Activity "Fetching Defender devices" -Status "Retrieved $($defenderDevices.Count) devices..." -PercentComplete 0
    }
    catch {
        Write-Host "❌ Failed to retrieve Defender devices. Check your Defender API permissions." -ForegroundColor Red
        exit 1
    }
} while ($defenderUri)

Write-Progress -Activity "Fetching Defender devices" -Completed
Write-Host "✅ Found $($defenderDevices.Count) devices in Defender." -ForegroundColor Green

# 5️⃣ Compare datasets (Intune vs Defender)
Write-Host "🔎 Comparing device lists..." -ForegroundColor Cyan
$defenderIDs = $defenderDevices.azureADDeviceId | Where-Object { $_ }
$nonOnboarded = $intuneDevices | Where-Object { $_.azureADDeviceId -and ($_.azureADDeviceId -notin $defenderIDs) }

Write-Host "🚫 Found $($nonOnboarded.Count) devices NOT onboarded to Defender for Endpoint." -ForegroundColor Yellow

# 6️⃣ Export CSV
if ($nonOnboarded.Count -gt 0) {
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "CSV files (*.csv)|*.csv"
    $saveDialog.FileName = "NonOnboardedDevices-$($tenantName.Replace(' ',''))-$((Get-Date).ToString('yyyyMMdd-HHmmss')).csv"
    $saveDialog.Title = "Save Non-Onboarded Devices Report"

    if ($saveDialog.ShowDialog() -eq 'OK') {
        $nonOnboarded | Select-Object `
            deviceName,
            operatingSystem,
            userPrincipalName,
            complianceState,
            lastSyncDateTime,
            enrollmentType,
            azureADDeviceId |
        Export-Csv -Path $saveDialog.FileName -NoTypeInformation -Encoding UTF8

        Write-Host "💾 CSV exported successfully: $($saveDialog.FileName)" -ForegroundColor Green
    }
    else {
        Write-Host "❌ Export cancelled by user." -ForegroundColor Yellow
    }
}
else {
    Write-Host "🎉 All Intune devices are onboarded to Defender!" -ForegroundColor Green
}

# 7️⃣ Cleanup
Write-Host "`n🧹 Cleaning up sessions..." -ForegroundColor Cyan
try {
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    az logout --only-show-errors | Out-Null
    Write-Host "👋 Disconnected from Microsoft Graph and Azure CLI." -ForegroundColor Cyan
}
catch {
    Write-Host "⚠️ Cleanup failed (no active sessions)." -ForegroundColor Yellow
}

Write-Host "`n✅ Script completed successfully for tenant: $tenantName" -ForegroundColor Green
