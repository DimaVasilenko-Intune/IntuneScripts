#Requires -Version 5.1
<#
.SYNOPSIS
    Exports non-compliant Intune devices with detailed compliance reasons to CSV.
.DESCRIPTION
    Gets non-compliant devices from Intune with detailed compliance policy failure information.
    Uses modern authentication with SSO for simplified login.
    Exports device details along with which compliance policies failed and why.
    Includes failed settings, grace period information, and policy names.
.NOTES
    Version: 2.0
    Last Modified: November 5, 2025
    Author: Dima Vasilenko
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

    Write-Host "🔐 Connecting to Microsoft Graph (SSO prompt)..." -ForegroundColor Cyan
    Write-Host "   Please select your account when prompted" -ForegroundColor Yellow
    
    # Define connection parameters for modern auth with forced SSO
    $connectionParams = @{
        NoWelcome = $true
        ErrorAction = 'Stop'
        ContextScope = 'Process'  # Forces SSO prompt every time
        Scopes = @(
            'DeviceManagementManagedDevices.Read.All',
            'DeviceManagementConfiguration.Read.All'
        )
    }
    
    # Connect with modern authentication
    $null = Connect-MgGraph @connectionParams
    
    # Small delay to ensure context is available
    Start-Sleep -Milliseconds 500

    # Verify connection and display tenant info
    $context = Get-MgContext
    if ($null -eq $context) {
        throw "Failed to get Microsoft Graph context"
    }
    
    Write-Host ("✅ Connected as {0}" -f $context.Account) -ForegroundColor Green
    
    try {
        $org = Get-MgOrganization -ErrorAction Stop
        Write-Host ("🏢 Organization: {0}" -f $org.DisplayName) -ForegroundColor Yellow
    }
    catch {
        Write-Host "🏢 Organization: Connected" -ForegroundColor Yellow
    }
    Write-Host ""

    Write-Host "📱 Retrieving non-compliant devices..." -ForegroundColor Cyan
    $nonCompliantDevices = @(Get-MgDeviceManagementManagedDevice -Filter "complianceState eq 'noncompliant'")
    
    Write-Host "   Found $($nonCompliantDevices.Count) non-compliant devices" -ForegroundColor Yellow
    
    if ($nonCompliantDevices.Count -eq 0) {
        Write-Host "✨ No non-compliant devices found - tenant is fully compliant!" -ForegroundColor Green
        return
    }

    Write-Host "🔍 Retrieving compliance details for each device..." -ForegroundColor Cyan
    
    # Create array to store detailed compliance information
    $detailedComplianceReport = [System.Collections.ArrayList]@()
    $processedCount = 0

    foreach ($device in $nonCompliantDevices) {
        $processedCount++
        Write-Progress -Activity "Processing Compliance Details" `
                      -Status "Device $processedCount of $($nonCompliantDevices.Count): $($device.DeviceName)" `
                      -PercentComplete (($processedCount / $nonCompliantDevices.Count) * 100)
        
        try {
            # Get device compliance policy states
            $complianceUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($device.Id)')/deviceCompliancePolicyStates"
            $complianceStates = Invoke-MgGraphRequest -Uri $complianceUri -Method GET
            
            # Process each policy state
            if ($complianceStates.value) {
                foreach ($policyState in $complianceStates.value) {
                    # Only process non-compliant policies
                    if ($policyState.state -eq 'nonCompliant') {
                        # Get detailed setting states for this policy
                        $settingsUri = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($device.Id)')/deviceCompliancePolicyStates('$($policyState.id)')/settingStates"
                        $settingStates = Invoke-MgGraphRequest -Uri $settingsUri -Method GET -ErrorAction SilentlyContinue
                        
                        # Collect failed settings
                        $failedSettings = @()
                        if ($settingStates.value) {
                            foreach ($setting in $settingStates.value) {
                                if ($setting.state -eq 'nonCompliant') {
                                    $failedSettings += "$($setting.setting): $($setting.errorDescription)"
                                }
                            }
                        }
                        
                        # Create detailed report entry
                        $reportEntry = [PSCustomObject]@{
                            DeviceName = $device.DeviceName
                            UserPrincipalName = $device.UserPrincipalName
                            OperatingSystem = $device.OperatingSystem
                            OSVersion = $device.OSVersion
                            ComplianceState = $device.ComplianceState
                            PolicyName = $policyState.displayName
                            PolicyState = $policyState.state
                            LastReportedDateTime = $policyState.lastReportedDateTime
                            FailedSettings = if ($failedSettings.Count -gt 0) { $failedSettings -join "; " } else { "Details not available" }
                            GracePeriodExpirationDateTime = $policyState.gracePeriodExpirationDateTime
                            Model = $device.Model
                            Manufacturer = $device.Manufacturer
                            SerialNumber = $device.SerialNumber
                            LastSyncDateTime = $device.LastSyncDateTime
                            DeviceId = $device.Id
                        }
                        
                        [void]$detailedComplianceReport.Add($reportEntry)
                    }
                }
            }
            else {
                # No policy states found - create entry with basic info
                $reportEntry = [PSCustomObject]@{
                    DeviceName = $device.DeviceName
                    UserPrincipalName = $device.UserPrincipalName
                    OperatingSystem = $device.OperatingSystem
                    OSVersion = $device.OSVersion
                    ComplianceState = $device.ComplianceState
                    PolicyName = "No policy information available"
                    PolicyState = "Unknown"
                    LastReportedDateTime = $null
                    FailedSettings = "Unable to retrieve compliance details"
                    GracePeriodExpirationDateTime = $null
                    Model = $device.Model
                    Manufacturer = $device.Manufacturer
                    SerialNumber = $device.SerialNumber
                    LastSyncDateTime = $device.LastSyncDateTime
                    DeviceId = $device.Id
                }
                
                [void]$detailedComplianceReport.Add($reportEntry)
            }
        }
        catch {
            Write-Warning "Failed to get compliance details for $($device.DeviceName): $_"
            
            # Add entry with error information
            $reportEntry = [PSCustomObject]@{
                DeviceName = $device.DeviceName
                UserPrincipalName = $device.UserPrincipalName
                OperatingSystem = $device.OperatingSystem
                OSVersion = $device.OSVersion
                ComplianceState = $device.ComplianceState
                PolicyName = "Error retrieving policy"
                PolicyState = "Error"
                LastReportedDateTime = $null
                FailedSettings = "Error: $($_.Exception.Message)"
                GracePeriodExpirationDateTime = $null
                Model = $device.Model
                Manufacturer = $device.Manufacturer
                SerialNumber = $device.SerialNumber
                LastSyncDateTime = $device.LastSyncDateTime
                DeviceId = $device.Id
            }
            
            [void]$detailedComplianceReport.Add($reportEntry)
        }
        
        # Rate limiting - avoid API throttling
        Start-Sleep -Milliseconds 100
    }
    
    Write-Progress -Activity "Processing Compliance Details" -Completed

    Write-Host "✅ Processed compliance details for $($nonCompliantDevices.Count) devices" -ForegroundColor Green
    Write-Host "📊 Total policy violations found: $($detailedComplianceReport.Count)" -ForegroundColor Yellow
    Write-Host ""

    if ($detailedComplianceReport) {
        # Create timestamp for default filename
        $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $defaultFileName = "NonCompliantDevices-Detailed-$timestamp.csv"

        # Create Save File Dialog with owner form for topmost behavior
        $ownerForm = New-Object System.Windows.Forms.Form
        $ownerForm.TopMost = $true
        $ownerForm.StartPosition = 'CenterScreen'
        
        $saveFileDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveFileDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
        $saveFileDialog.FileName = $defaultFileName
        $saveFileDialog.Title = "Save Non-Compliant Devices Report with Compliance Details"
        $saveFileDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
        $saveFileDialog.ShowHelp = $true

        # Show dialog and export if user selects a location
        if ($saveFileDialog.ShowDialog($ownerForm) -eq 'OK') {
            $exportPath = $saveFileDialog.FileName

            # Create directory if it doesn't exist
            $exportDir = Split-Path $exportPath -Parent
            if (-not (Test-Path $exportDir)) {
                New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
            }

            # Export to CSV
            $detailedComplianceReport | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8

            Write-Host "💾 Exported to: $exportPath" -ForegroundColor Green
            Write-Host ""
            Write-Host "📊 Report Summary:" -ForegroundColor Cyan
            Write-Host "   Total Devices: $($nonCompliantDevices.Count)" -ForegroundColor Yellow
            Write-Host "   Total Policy Violations: $($detailedComplianceReport.Count)" -ForegroundColor Yellow
            Write-Host ""
            
            # Ask if user wants to open the file
            $openFile = Read-Host "Would you like to open the CSV file now? (y/n)"
            if ($openFile -eq 'y') {
                Start-Process $exportPath
            }
        }
        else {
            Write-Host "❌ Export cancelled by user" -ForegroundColor Yellow
        }
        
        $ownerForm.Dispose()
    }
}
catch {
    Write-Error "Error: $_"
    exit 1
}
finally {
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Host "👋 Disconnected from Microsoft Graph" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Failed to disconnect from Microsoft Graph: $_"
    }
    
    # Clean up sensitive variables
    Remove-Variable -Name detailedComplianceReport, nonCompliantDevices, context -ErrorAction SilentlyContinue
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
}