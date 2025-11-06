#Requires -Version 7.0
<#
.SYNOPSIS
    Calculate device risk score based on multiple security and compliance factors.
.DESCRIPTION
    Analyzes Intune devices and calculates a risk score based on:
    - Compliance state
    - Last sync date
    - OS version currency
    - Encryption status
    - Microsoft Defender for Endpoint (ATP) health and onboarding status
    
    The script retrieves real-time ATP data from Intune's Defender Agents report including:
    - Onboarding status (WDATPOnboardingState)
    - Defender sensor running status (IsWDATPSenseRunning)
    - Real-time protection enabled
    - Tamper protection enabled
    - Malware protection status
    
    Provides weighted risk scoring with recommendations for remediation.
    Exports detailed report to CSV with risk categorization and ATP details.
.NOTES
    Version: 1.1.0
    Author: Dima Vasilenko
    Last Modified: November 6, 2025
    Changed: Now uses Intune Defender Agents report for accurate ATP data
#>

# Enable strict mode for better error handling
Set-StrictMode -Version Latest

# Load Windows Forms assembly for Save File Dialog
Add-Type -AssemblyName System.Windows.Forms

try {
    #region AUTHENTICATION
    Write-Host "📦 Checking Microsoft Graph modules..." -ForegroundColor Cyan
    
    # Install and import required modules
    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.DeviceManagement'
    )
    
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable $module)) {
            Write-Host "   Installing $module..." -ForegroundColor Cyan
            Install-Module $module -Force -Scope CurrentUser -ErrorAction Stop
        }
        Import-Module $module -ErrorAction Stop
    }

    Write-Host "🔐 Connecting to Microsoft Graph (SSO prompt)..." -ForegroundColor Cyan
    Write-Host "   Please select your account when prompted" -ForegroundColor Yellow
    
    # Define connection parameters for modern auth with forced SSO
    $connectionParams = @{
        NoWelcome = $true
        ErrorAction = 'Stop'
        ContextScope = 'Process'
        Scopes = @(
            'DeviceManagementManagedDevices.Read.All',
            'DeviceManagementConfiguration.Read.All',
            'Directory.Read.All'
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
    #endregion AUTHENTICATION

    #region DATA COLLECTION
    Write-Host "📱 Retrieving managed devices..." -ForegroundColor Cyan
    
    # Get all managed devices
    $allDevices = @(Get-MgDeviceManagementManagedDevice -All)
    
    Write-Host "   Found $($allDevices.Count) managed devices" -ForegroundColor Yellow
    
    if ($allDevices.Count -eq 0) {
        Write-Host "✨ No managed devices found in this tenant" -ForegroundColor Green
        return
    }

    # Get Defender ATP data from Intune Reports
    Write-Host "🛡️  Retrieving Microsoft Defender for Endpoint data from Intune..." -ForegroundColor Cyan
    
    $atpLookup = @{}
    $atpDeviceCount = 0
    
    try {
        # Use Intune Reports API to get Defender Agents data
        $reportParams = @{
            id = "DefenderAgents_00000000-0000-0000-0000-000000000001"
            skip = 0
            top = 9999  # Get all devices
            select = @(
                "DeviceName",
                "DeviceId",
                "WDATPOnboardingState",
                "IsWDATPSenseRunning",
                "RealTimeProtectionEnabled",
                "TamperProtectionEnabled",
                "MalwareProtectionEnabled",
                "NetworkInspectionSystemEnabled",
                "ProductStatus",
                "LastReportedDateTime",
                "AntiMalwareVersion",
                "EngineVersion"
            )
            filter = ""
            search = ""
            orderBy = @()
        }
        
        $uri = "https://graph.microsoft.com/beta/deviceManagement/reports/getCachedReport"
        $body = $reportParams | ConvertTo-Json -Depth 10
        
        Write-Host "   Querying Defender Agents report..." -ForegroundColor Gray
        $atpResponse = Invoke-MgGraphRequest -Uri $uri -Method POST -Body $body -ContentType "application/json" -ErrorAction Stop
        
        if ($atpResponse.Values -and $atpResponse.Values.Count -gt 0) {
            $atpDeviceCount = $atpResponse.Values.Count
            
            Write-Host "   ✅ Found $atpDeviceCount devices with Defender data" -ForegroundColor Green
            
            # Parse the response - Schema tells us column order
            $schema = $atpResponse.Schema
            $deviceNameIndex = ($schema | Where-Object { $_.Column -eq "DeviceName" }).Column
            $deviceIdIndex = ($schema | Where-Object { $_.Column -eq "DeviceId" }).Column
            $onboardingStateIndex = ($schema | Where-Object { $_.Column -eq "WDATPOnboardingState" }).Column
            $senseRunningIndex = ($schema | Where-Object { $_.Column -eq "IsWDATPSenseRunning" }).Column
            $rtpEnabledIndex = ($schema | Where-Object { $_.Column -eq "RealTimeProtectionEnabled" }).Column
            $tamperProtectionIndex = ($schema | Where-Object { $_.Column -eq "TamperProtectionEnabled" }).Column
            $malwareProtectionIndex = ($schema | Where-Object { $_.Column -eq "MalwareProtectionEnabled" }).Column
            $productStatusIndex = ($schema | Where-Object { $_.Column -eq "ProductStatus" }).Column
            $lastReportedIndex = ($schema | Where-Object { $_.Column -eq "LastReportedDateTime" }).Column
            
            # Get column indices
            $colIndices = @{}
            for ($i = 0; $i -lt $schema.Count; $i++) {
                $colIndices[$schema[$i].Column] = $i
            }
            
            # Build lookup table
            foreach ($row in $atpResponse.Values) {
                $deviceName = $row[$colIndices["DeviceName"]]
                $deviceId = $row[$colIndices["DeviceId"]]
                
                if ($deviceName) {
                    $atpDevice = @{
                        DeviceName = $deviceName
                        DeviceId = $deviceId
                        WDATPOnboardingState = $row[$colIndices["WDATPOnboardingState"]]
                        IsWDATPSenseRunning = $row[$colIndices["IsWDATPSenseRunning"]]
                        RealTimeProtectionEnabled = $row[$colIndices["RealTimeProtectionEnabled"]]
                        TamperProtectionEnabled = $row[$colIndices["TamperProtectionEnabled"]]
                        MalwareProtectionEnabled = $row[$colIndices["MalwareProtectionEnabled"]]
                        NetworkInspectionSystemEnabled = $row[$colIndices["NetworkInspectionSystemEnabled"]]
                        ProductStatus = $row[$colIndices["ProductStatus"]]
                        LastReportedDateTime = $row[$colIndices["LastReportedDateTime"]]
                        AntiMalwareVersion = $row[$colIndices["AntiMalwareVersion"]]
                        EngineVersion = $row[$colIndices["EngineVersion"]]
                    }
                    
                    # Add to lookup by both device name (lowercase) and device ID
                    $atpLookup[$deviceName.ToLower()] = $atpDevice
                    if ($deviceId) {
                        $atpLookup[$deviceId] = $atpDevice
                    }
                }
            }
            
            # Show sample for diagnostics
            if ($atpDeviceCount -gt 0) {
                Write-Host "   Sample Defender device:" -ForegroundColor Gray
                $sample = $atpResponse.Values[0]
                Write-Host "      Name: $($sample[$colIndices['DeviceName']])" -ForegroundColor Gray
                Write-Host "      Onboarding State: $($sample[$colIndices['WDATPOnboardingState']])" -ForegroundColor Gray
                Write-Host "      Sense Running: $($sample[$colIndices['IsWDATPSenseRunning']])" -ForegroundColor Gray
            }
        }
        else {
            Write-Host "   ⚠️  No devices found in Defender Agents report" -ForegroundColor Yellow
            Write-Host "   This could mean:" -ForegroundColor Yellow
            Write-Host "   - Defender for Endpoint is not activated in this tenant" -ForegroundColor Yellow
            Write-Host "   - No Windows devices are reporting Defender status yet" -ForegroundColor Yellow
        }
    }
    catch {
        $errorDetails = $_.Exception.Message
        Write-Warning "Could not retrieve Defender ATP data from Intune Reports"
        Write-Host "   Error: $errorDetails" -ForegroundColor Red
        Write-Host "   ℹ️  Continuing without ATP data - other risk factors will still be assessed" -ForegroundColor Cyan
    }

    Write-Host "🔍 Calculating risk scores for each device..." -ForegroundColor Cyan
    Write-Host ""
    
    # Create array to store risk assessment results
    $riskAssessments = [System.Collections.ArrayList]@()
    $processedCount = 0
    
    # Get current date for calculations
    $currentDate = Get-Date

    foreach ($device in $allDevices) {
        $processedCount++
        Write-Progress -Activity "Calculating Risk Scores" `
                      -Status "Device $processedCount of $($allDevices.Count): $($device.DeviceName)" `
                      -PercentComplete (($processedCount / $allDevices.Count) * 100)
        
        try {
            # Initialize risk factors
            $riskPoints = 0
            $recommendations = @()
            
            #region RISK FACTOR 1: Compliance State (30 points max)
            $complianceRisk = 0
            switch ($device.ComplianceState) {
                'noncompliant' { $complianceRisk = 30; $recommendations += "Device is non-compliant - review failed policies" }
                'unknown' { $complianceRisk = 15; $recommendations += "Compliance state unknown - trigger device sync" }
                'conflict' { $complianceRisk = 20; $recommendations += "Policy conflict detected - review policy assignments" }
                'error' { $complianceRisk = 25; $recommendations += "Compliance evaluation error - check device logs" }
                'compliant' { $complianceRisk = 0 }
                default { $complianceRisk = 10 }
            }
            $riskPoints += $complianceRisk
            #endregion

            #region RISK FACTOR 2: Last Sync Date (20 points max)
            $lastSyncRisk = 0
            if ($device.LastSyncDateTime) {
                $daysSinceSync = ($currentDate - $device.LastSyncDateTime).Days
                
                if ($daysSinceSync -gt 30) {
                    $lastSyncRisk = 20
                    $recommendations += "Device stale (last sync: $daysSinceSync days ago) - device may be lost/retired"
                }
                elseif ($daysSinceSync -gt 14) {
                    $lastSyncRisk = 15
                    $recommendations += "Device not synced in $daysSinceSync days - check device connectivity"
                }
                elseif ($daysSinceSync -gt 7) {
                    $lastSyncRisk = 10
                    $recommendations += "Device sync overdue ($daysSinceSync days) - user may need support"
                }
                elseif ($daysSinceSync -gt 3) {
                    $lastSyncRisk = 5
                }
            }
            else {
                $lastSyncRisk = 20
                $recommendations += "No sync date available - device may never have checked in"
            }
            $riskPoints += $lastSyncRisk
            #endregion

            #region RISK FACTOR 3: OS Version (15 points max)
            $osVersionRisk = 0
            $osVersionStatus = "Unknown"
            
            # Windows version checking
            if ($device.OperatingSystem -eq 'Windows' -and $device.OSVersion) {
                $osVersion = $device.OSVersion
                
                # Windows 11 versions
                if ($osVersion -match '^10\.0\.2[2-9]') {
                    $osVersionRisk = 0
                    $osVersionStatus = "Current (Windows 11)"
                }
                # Windows 10 21H2 or newer (10.0.19044+)
                elseif ($osVersion -match '^10\.0\.19044' -or $osVersion -match '^10\.0\.19045') {
                    $osVersionRisk = 5
                    $osVersionStatus = "Supported (Windows 10 21H2+)"
                }
                # Windows 10 older versions
                elseif ($osVersion -match '^10\.0\.1') {
                    $osVersionRisk = 10
                    $osVersionStatus = "Outdated (Windows 10 old version)"
                    $recommendations += "OS version outdated - upgrade to Windows 11 or latest Windows 10"
                }
                # Very old Windows
                else {
                    $osVersionRisk = 15
                    $osVersionStatus = "Critical (Very old Windows)"
                    $recommendations += "OS critically outdated - immediate upgrade required"
                }
            }
            # iOS version checking
            elseif ($device.OperatingSystem -eq 'iOS' -and $device.OSVersion) {
                $iosVersion = [version]$device.OSVersion
                
                if ($iosVersion.Major -ge 17) {
                    $osVersionRisk = 0
                    $osVersionStatus = "Current (iOS 17+)"
                }
                elseif ($iosVersion.Major -eq 16) {
                    $osVersionRisk = 5
                    $osVersionStatus = "Supported (iOS 16)"
                }
                elseif ($iosVersion.Major -eq 15) {
                    $osVersionRisk = 10
                    $osVersionStatus = "Outdated (iOS 15)"
                    $recommendations += "iOS version outdated - update to latest version"
                }
                else {
                    $osVersionRisk = 15
                    $osVersionStatus = "Critical (iOS <15)"
                    $recommendations += "iOS critically outdated - immediate update required"
                }
            }
            # Android version checking
            elseif ($device.OperatingSystem -eq 'Android' -and $device.OSVersion) {
                $androidVersion = [version]$device.OSVersion
                
                if ($androidVersion.Major -ge 13) {
                    $osVersionRisk = 0
                    $osVersionStatus = "Current (Android 13+)"
                }
                elseif ($androidVersion.Major -ge 11) {
                    $osVersionRisk = 5
                    $osVersionStatus = "Supported (Android 11-12)"
                }
                elseif ($androidVersion.Major -ge 9) {
                    $osVersionRisk = 10
                    $osVersionStatus = "Outdated (Android 9-10)"
                    $recommendations += "Android version outdated - update to latest version"
                }
                else {
                    $osVersionRisk = 15
                    $osVersionStatus = "Critical (Android <9)"
                    $recommendations += "Android critically outdated - immediate update required"
                }
            }
            $riskPoints += $osVersionRisk
            #endregion

            #region RISK FACTOR 4: Encryption Status (20 points max)
            $encryptionRisk = 0
            $encryptionStatus = "Unknown"
            
            if ($device.IsEncrypted -eq $true) {
                $encryptionRisk = 0
                $encryptionStatus = "Encrypted"
            }
            elseif ($device.IsEncrypted -eq $false) {
                $encryptionRisk = 20
                $encryptionStatus = "Not Encrypted"
                $recommendations += "Device not encrypted - enable BitLocker/FileVault immediately"
            }
            else {
                $encryptionRisk = 10
                $encryptionStatus = "Unknown"
                $recommendations += "Encryption status unknown - verify device encryption"
            }
            $riskPoints += $encryptionRisk
            #endregion

            #region RISK FACTOR 5: Defender ATP Health (15 points max)
            $atpRisk = 0
            $atpStatus = "Not Available"
            $atpOnboardingStatus = "Unknown"
            $atpSenseRunning = "N/A"
            $atpRealTimeProtection = "N/A"
            $atpTamperProtection = "N/A"
            $atpProductStatus = "N/A"
            
            # Check if device is Windows (ATP is primarily for Windows)
            if ($device.OperatingSystem -eq 'Windows') {
                # Try to find device in ATP by device name or device ID
                $deviceNameLower = $device.DeviceName.ToLower()
                $deviceId = $device.Id
                
                $atpDevice = $null
                if ($atpLookup.ContainsKey($deviceNameLower)) {
                    $atpDevice = $atpLookup[$deviceNameLower]
                }
                elseif ($atpLookup.ContainsKey($deviceId)) {
                    $atpDevice = $atpLookup[$deviceId]
                }
                
                if ($atpDevice) {
                    # Device found in Defender report
                    $onboardingState = $atpDevice.WDATPOnboardingState
                    
                    # Onboarding state: 0=Not Onboarded, 1=Onboarded
                    if ($onboardingState -eq 1) {
                        $atpOnboardingStatus = "Onboarded"
                        
                        # Check if Sense (Defender sensor) is running
                        $senseRunning = $atpDevice.IsWDATPSenseRunning
                        if ($senseRunning -eq 1 -or $senseRunning -eq $true) {
                            $atpSenseRunning = "Running"
                            $atpRisk = 0
                            $atpStatus = "Healthy (Onboarded & Active)"
                        }
                        else {
                            $atpSenseRunning = "Not Running"
                            $atpRisk = 12
                            $atpStatus = "Sensor Not Running"
                            $recommendations += "Defender ATP sensor not running - check service status"
                        }
                        
                        # Check Real-Time Protection
                        if ($atpDevice.RealTimeProtectionEnabled -eq 1 -or $atpDevice.RealTimeProtectionEnabled -eq $true) {
                            $atpRealTimeProtection = "Enabled"
                        }
                        else {
                            $atpRealTimeProtection = "Disabled"
                            $atpRisk = [math]::Max($atpRisk, 10)
                            $recommendations += "Real-time protection disabled - enable immediately"
                        }
                        
                        # Check Tamper Protection
                        if ($atpDevice.TamperProtectionEnabled -eq 1 -or $atpDevice.TamperProtectionEnabled -eq $true) {
                            $atpTamperProtection = "Enabled"
                        }
                        else {
                            $atpTamperProtection = "Disabled"
                            $atpRisk = [math]::Max($atpRisk, 8)
                            $recommendations += "Tamper protection disabled - enable for better security"
                        }
                        
                        # Check Product Status (524288 = OK, other values indicate issues)
                        $productStatus = $atpDevice.ProductStatus
                        if ($productStatus -eq 524288) {
                            $atpProductStatus = "Healthy"
                        }
                        elseif ($productStatus -eq 524544) {
                            $atpProductStatus = "Quick Scan Overdue"
                            $atpRisk = [math]::Max($atpRisk, 5)
                        }
                        elseif ($productStatus -eq 524672) {
                            $atpProductStatus = "Full Scan Overdue"
                            $atpRisk = [math]::Max($atpRisk, 6)
                        }
                        elseif ($productStatus -eq 525056) {
                            $atpProductStatus = "Reboot Required"
                            $atpRisk = [math]::Max($atpRisk, 7)
                        }
                        elseif ($productStatus -eq 1) {
                            $atpProductStatus = "Not Protected"
                            $atpRisk = 15
                            $recommendations += "Defender not protecting device - investigate immediately"
                        }
                        else {
                            $atpProductStatus = "Status Code: $productStatus"
                            $atpRisk = [math]::Max($atpRisk, 8)
                        }
                    }
                    elseif ($onboardingState -eq 0) {
                        $atpOnboardingStatus = "Not Onboarded"
                        $atpRisk = 15
                        $atpStatus = "Not Onboarded to Defender"
                        $recommendations += "Device not onboarded to Defender for Endpoint - onboard immediately"
                    }
                    else {
                        $atpOnboardingStatus = "Unknown State: $onboardingState"
                        $atpRisk = 10
                        $atpStatus = "Unknown Onboarding State"
                    }
                }
                elseif ($atpDeviceCount -gt 0) {
                    # ATP is configured but this Windows device is not in the report
                    $atpRisk = 15
                    $atpStatus = "Not Reporting"
                    $atpOnboardingStatus = "Not Reporting"
                    $recommendations += "Device not found in Defender report - may need onboarding or agent installation"
                }
                else {
                    # ATP not configured in tenant
                    $atpRisk = 0
                    $atpStatus = "Defender Not Configured"
                    $atpOnboardingStatus = "N/A"
                }
            }
            else {
                # Non-Windows device
                $atpRisk = 0
                $atpStatus = "N/A (Non-Windows)"
                $atpOnboardingStatus = "N/A"
            }
            $riskPoints += $atpRisk
            #endregion

            #region RISK CATEGORIZATION
            $riskLevel = if ($riskPoints -ge 76) { "Critical" }
                        elseif ($riskPoints -ge 51) { "High" }
                        elseif ($riskPoints -ge 26) { "Medium" }
                        else { "Low" }
            
            $riskColor = switch ($riskLevel) {
                "Critical" { "Red" }
                "High" { "DarkYellow" }
                "Medium" { "Yellow" }
                "Low" { "Green" }
            }
            #endregion

            # Create risk assessment entry
            $assessment = [PSCustomObject]@{
                DeviceName = $device.DeviceName
                UserPrincipalName = $device.UserPrincipalName
                OperatingSystem = $device.OperatingSystem
                OSVersion = $device.OSVersion
                OSVersionStatus = $osVersionStatus
                ComplianceState = $device.ComplianceState
                LastSyncDateTime = $device.LastSyncDateTime
                DaysSinceSync = if ($device.LastSyncDateTime) { ($currentDate - $device.LastSyncDateTime).Days } else { "Never" }
                EncryptionStatus = $encryptionStatus
                DefenderATPStatus = $atpStatus
                DefenderATPOnboarding = $atpOnboardingStatus
                DefenderATPSenseRunning = $atpSenseRunning
                DefenderATPRealTimeProtection = $atpRealTimeProtection
                DefenderATPTamperProtection = $atpTamperProtection
                DefenderATPProductStatus = $atpProductStatus
                RiskScore = $riskPoints
                RiskLevel = $riskLevel
                Recommendations = if ($recommendations.Count -gt 0) { $recommendations -join "; " } else { "All checks passed - no action needed" }
                Model = $device.Model
                Manufacturer = $device.Manufacturer
                SerialNumber = $device.SerialNumber
                DeviceId = $device.Id
            }
            
            [void]$riskAssessments.Add($assessment)
            
            # Display progress for high/critical risk devices
            if ($riskLevel -in @("High", "Critical")) {
                Write-Host "   ⚠️  $($device.DeviceName): $riskLevel Risk (Score: $riskPoints)" -ForegroundColor $riskColor
            }
        }
        catch {
            Write-Warning "Failed to assess risk for $($device.DeviceName): $_"
        }
    }
    
    Write-Progress -Activity "Calculating Risk Scores" -Completed
    Write-Host ""
    #endregion DATA COLLECTION

    #region SUMMARY STATISTICS
    Write-Host "📊 Risk Assessment Summary:" -ForegroundColor Cyan
    
    # Fix: Ensure we get arrays, not nulls
    $criticalDevices = @($riskAssessments | Where-Object { $_.RiskLevel -eq "Critical" })
    $highDevices = @($riskAssessments | Where-Object { $_.RiskLevel -eq "High" })
    $mediumDevices = @($riskAssessments | Where-Object { $_.RiskLevel -eq "Medium" })
    $lowDevices = @($riskAssessments | Where-Object { $_.RiskLevel -eq "Low" })
    
    $criticalCount = $criticalDevices.Count
    $highCount = $highDevices.Count
    $mediumCount = $mediumDevices.Count
    $lowCount = $lowDevices.Count
    
    Write-Host "   🔴 Critical Risk: $criticalCount devices" -ForegroundColor Red
    Write-Host "   🟠 High Risk: $highCount devices" -ForegroundColor DarkYellow
    Write-Host "   🟡 Medium Risk: $mediumCount devices" -ForegroundColor Yellow
    Write-Host "   🟢 Low Risk: $lowCount devices" -ForegroundColor Green
    Write-Host ""
    Write-Host "   Total Devices Assessed: $($riskAssessments.Count)" -ForegroundColor White
    
    if ($riskAssessments.Count -gt 0) {
        $averageRisk = [math]::Round(($riskAssessments | Measure-Object -Property RiskScore -Average).Average, 2)
        Write-Host "   Average Risk Score: $averageRisk / 100" -ForegroundColor White
    }
    
    # Show ATP onboarding summary if data was retrieved
    if ($atpDeviceCount -gt 0) {
        $onboardedCount = @($riskAssessments | Where-Object { $_.DefenderATPOnboarding -eq "Onboarded" }).Count
        $notOnboardedCount = @($riskAssessments | Where-Object { $_.DefenderATPOnboarding -eq "Not Onboarded" }).Count
        Write-Host ""
        Write-Host "🛡️  Defender for Endpoint Summary:" -ForegroundColor Cyan
        Write-Host "   ✅ Onboarded: $onboardedCount devices" -ForegroundColor Green
        Write-Host "   ❌ Not Onboarded: $notOnboardedCount devices" -ForegroundColor Red
    }
    
    Write-Host ""
    #endregion SUMMARY STATISTICS

    #region EXPORT
    if ($riskAssessments.Count -gt 0) {
        Write-Host "💾 Preparing to export risk assessment report..." -ForegroundColor Cyan
        Write-Host "   Opening Save File Dialog..." -ForegroundColor Yellow
        Write-Host ""
        
        # Create SaveFileDialog
        $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
        $saveDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
        $saveDialog.Title = "Save Device Risk Assessment Report"
        $saveDialog.FileName = "DeviceRiskAssessment_$(Get-Date -Format 'yyyyMMdd-HHmmss').csv"
        $saveDialog.InitialDirectory = [Environment]::GetFolderPath('Desktop')
        
        # Make dialog topmost
        $saveDialog.RestoreDirectory = $true
        
        # Show dialog
        $result = $saveDialog.ShowDialog()
        
        if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
            $exportPath = $saveDialog.FileName
            
            try {
                # Sort by risk score (highest first)
                $riskAssessments | Sort-Object -Property RiskScore -Descending | 
                    Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
                
                Write-Host ""
                Write-Host "✅ Export completed successfully!" -ForegroundColor Green
                Write-Host ""
                Write-Host "📄 Report Details:" -ForegroundColor Cyan
                Write-Host "   Location: $exportPath" -ForegroundColor White
                Write-Host "   Devices: $($riskAssessments.Count)" -ForegroundColor White
                Write-Host "   Critical/High Risk: $($criticalCount + $highCount)" -ForegroundColor White
                Write-Host ""
                
                # Ask if user wants to open the file
                $openFile = Read-Host "Would you like to open the CSV file now? (y/n)"
                if ($openFile -eq 'y') {
                    Start-Process $exportPath
                }
            }
            catch {
                throw "Failed to export CSV: $_"
            }
        }
        else {
            Write-Host "❌ Export cancelled by user" -ForegroundColor Yellow
        }
        
        $saveDialog.Dispose()
    }
    #endregion EXPORT
}
catch {
    Write-Error "Error: $_"
    exit 1
}
finally {
    #region CLEANUP
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue | Out-Null
        Write-Host "👋 Disconnected from Microsoft Graph" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Failed to disconnect from Microsoft Graph: $_"
    }
    
    # Clean up sensitive variables
    Remove-Variable -Name riskAssessments, allDevices, context -ErrorAction SilentlyContinue
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    #endregion CLEANUP
}