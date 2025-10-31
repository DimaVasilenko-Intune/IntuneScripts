#Requires -Version 5.1
<#
.SYNOPSIS
    Exports non-compliant Intune devices to CSV using SSO authentication.
.DESCRIPTION
    Gets non-compliant devices from Intune and exports them to a CSV file.
    Uses modern authentication with SSO for simplified login.
    Allows user to choose the export location through a Save File dialog.
.NOTES
    Version: 1.6
    Last Modified: October 30, 2025
#>

# Enable strict mode for better error handling
Set-StrictMode -Version Latest

# Load Windows Forms assembly for Save File Dialog
Add-Type -AssemblyName System.Windows.Forms

try {
    Write-Host "📦 Checking Microsoft Graph module..." -ForegroundColor Cyan
    if (-not (Get-Module -ListAvailable Microsoft.Graph)) {
        Install-Module Microsoft.Graph -Force -Scope CurrentUser -ErrorAction Stop
    }

    Write-Host "🔐 Connecting to Microsoft Graph..." -ForegroundColor Cyan
    
    # Define connection parameters for modern auth
    $connectionParams = @{
        NoWelcome = $true
        ErrorAction = 'Stop'
        UseDeviceAuthentication = $false
        Scopes = @(
            'DeviceManagementManagedDevices.Read.All',
            'DeviceManagementConfiguration.Read.All'
        )
    }
    
    # Attempt connection with timeout
    $timeoutSeconds = 60
    $timer = [System.Diagnostics.Stopwatch]::StartNew()
    
    # Connect with modern authentication
    Connect-MgGraph @connectionParams
    
    # Wait for connection with timeout
    while (-not (Get-MgContext) -and $timer.Elapsed.TotalSeconds -lt $timeoutSeconds) {
        Start-Sleep -Seconds 1
    }
    
    if (-not (Get-MgContext)) {
        throw "Authentication timed out after $timeoutSeconds seconds"
    }

    # Verify connection and display tenant info
    $context = Get-MgContext
    if ($null -eq $context) {
        throw "Failed to get Microsoft Graph context"
    }
    
    Write-Host ("✅ Connected as {0}" -f $context.Account) -ForegroundColor Green
    Write-Host ("🏢 Organization: {0}" -f (Get-MgOrganization).DisplayName) -ForegroundColor Yellow
    Write-Host ""

    Write-Host "📱 Getting non-compliant devices..." -ForegroundColor Cyan
    $nonCompliantDevices = Get-MgDeviceManagementManagedDevice -Filter "complianceState eq 'noncompliant'"

    if ($nonCompliantDevices) {
        # Create timestamp for default filename
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $defaultFileName = "NonCompliantDevices-$timestamp.csv"

        # Create Save File Dialog
        $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveFileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
        $saveFileDialog.FileName = $defaultFileName
        $saveFileDialog.Title = "Save Non-Compliant Devices Report"
        $saveFileDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')

        # Show dialog and export if user selects a location
        if ($saveFileDialog.ShowDialog() -eq 'OK') {
            $exportPath = $saveFileDialog.FileName

            # Create directory if it doesn't exist
            $exportDir = Split-Path $exportPath -Parent
            if (-not (Test-Path $exportDir)) {
                New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
            }

            # Select relevant properties and export to CSV
            $nonCompliantDevices | Select-Object `
                DeviceName, `
                UserPrincipalName, `
                OperatingSystem, `
                OSVersion, `
                LastSyncDateTime, `
                ComplianceState, `
                Model, `
                Manufacturer, `
                SerialNumber | 
            Export-Csv -Path $exportPath -NoTypeInformation

            Write-Host "✅ Exported $($nonCompliantDevices.Count) devices to: $exportPath" -ForegroundColor Green
        }
        else {
            Write-Host "❌ Export cancelled by user" -ForegroundColor Yellow
        }
    }
    else {
        Write-Host "✨ No non-compliant devices found" -ForegroundColor Yellow
    }
}
catch {
    Write-Error "Error: $_"
    exit 1
}
finally {
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Write-Host "👋 Disconnected from Microsoft Graph" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Failed to disconnect from Microsoft Graph: $_"
    }
    
    # Clean up any remaining connections
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}