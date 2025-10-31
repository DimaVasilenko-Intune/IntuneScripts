#Requires -Version 5.1
<#
.SYNOPSIS
Bulk sync all Intune devices in the tenant.

.DESCRIPTION
Logs in with Microsoft Graph (SSO), retrieves all managed devices,
and triggers a syncDevice command for each. Includes error handling
and safe pagination for large tenants.

.OUTPUTS
CSV log with device name, ID, result, and timestamp.

.NOTES
Author: Dima Vasilenko
Version: 1.1
Date: 31.10.2025
#>

Set-StrictMode -Version Latest
Add-Type -AssemblyName System.Windows.Forms

Write-Host "-----------------------------------------------------------"
Write-Host "🔄 Intune Bulk Device Sync Tool" -ForegroundColor Cyan
Write-Host "-----------------------------------------------------------`n"

# 1️⃣ Connect to Microsoft Graph
try {
    Write-Host "🔐 Connecting to Microsoft Graph (Intune)..." -ForegroundColor Cyan
    Connect-MgGraph -Scopes "DeviceManagementManagedDevices.ReadWrite.All" -NoWelcome
    $context = Get-MgContext
    Write-Host "🌍 Connected to tenant: $($context.TenantId)" -ForegroundColor Green
}
catch {
    Write-Error "❌ Failed to connect to Microsoft Graph. Check your permissions or network connection."
    exit 1
}

# 2️⃣ Retrieve all managed devices
Write-Host "📦 Fetching all managed devices..." -ForegroundColor Cyan
$devices = @()
$uri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices"

do {
    try {
        $response = Invoke-MgGraphRequest -Uri $uri -Method GET -OutputType PSObject
        if ($response.value) {
            $devices += $response.value
        }
        $uri = $response.PSObject.Properties["@odata.nextLink"]?.Value
    }
    catch {
        Write-Warning "⚠️ Failed to retrieve devices from Graph: $($_.Exception.Message)"
        break
    }
} while ($uri)

if (-not $devices -or $devices.Count -eq 0) {
    Write-Host "❌ No devices found in Intune or insufficient permissions." -ForegroundColor Red
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    exit
}

Write-Host "✅ Found $($devices.Count) managed devices in Intune." -ForegroundColor Green

# 3️⃣ Confirm bulk action
$confirm = Read-Host "Do you want to trigger sync for ALL $($devices.Count) devices? (Y/N)"
if ($confirm -ne 'Y' -and $confirm -ne 'y') {
    Write-Host "🛑 Cancelled by user."
    Disconnect-MgGraph -ErrorAction SilentlyContinue
    exit
}

# 4️⃣ Trigger device sync
Write-Host "🚀 Starting sync requests..." -ForegroundColor Cyan
$results = @()
$count = 0
$total = $devices.Count

foreach ($device in $devices) {
    $count++
    $name = if ($device.deviceName) { $device.deviceName } else { "Unknown" }
    $id = $device.id

    Write-Progress -Activity "Syncing Intune devices" -Status "Syncing $name ($count/$total)" -PercentComplete (($count / $total) * 100)

    try {
        Invoke-MgGraphRequest -Uri "https://graph.microsoft.com/beta/deviceManagement/managedDevices/$id/syncDevice" -Method POST -ErrorAction Stop
        $results += [PSCustomObject]@{
            DeviceName = $name
            DeviceId   = $id
            Result     = "Triggered"
            Timestamp  = (Get-Date)
        }
    }
    catch {
        $errorMsg = $_.Exception.Message
Write-Warning "⚠️ Failed to sync ${name}: ${errorMsg}"
        $results += [PSCustomObject]@{
            DeviceName = $name
            DeviceId   = $id
            Result     = "Failed - $errorMsg"
            Timestamp  = (Get-Date)
        }
    }

    Start-Sleep -Milliseconds 500  # prevent API throttling
}

Write-Progress -Activity "Syncing Intune devices" -Completed
Write-Host "✅ Sync requests sent for all devices." -ForegroundColor Green

# 5️⃣ Export results to CSV
$saveDialog = New-Object System.Windows.Forms.SaveFileDialog
$saveDialog.Filter = "CSV files (*.csv)|*.csv"
$saveDialog.FileName = "BulkSyncResults-$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"

if ($saveDialog.ShowDialog() -eq 'OK') {
    try {
        $results | Export-Csv -Path $saveDialog.FileName -NoTypeInformation -Encoding UTF8
        Write-Host "💾 Exported log to: $($saveDialog.FileName)" -ForegroundColor Green
    }
    catch {
        Write-Warning "⚠️ Could not export CSV file: $($_.Exception.Message)"
    }
}

# 6️⃣ Disconnect cleanly
Disconnect-MgGraph -ErrorAction SilentlyContinue
Write-Host "`n👋 Disconnected from Microsoft Graph."
Write-Host "✅ Done!"
