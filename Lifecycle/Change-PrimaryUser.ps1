#Requires -Version 7.0
<#
.SYNOPSIS
    Change the Primary User of an Intune-managed device.
.DESCRIPTION
    Interactively updates the Primary User assignment for a device in Microsoft Intune
    using Microsoft Graph API. Supports modern authentication and provides clear feedback.
.NOTES
    Version: 1.1.0
    Author: Dima Vasilenko
    Last Modified: October 30, 2025
#>

# Enable strict mode for better error handling
Set-StrictMode -Version Latest

# Clear any existing sessions and cached credentials
Disconnect-MgGraph -ErrorAction SilentlyContinue

try {
    #region AUTHENTICATION
    Write-Host "📦 Checking Microsoft Graph modules..." -ForegroundColor Cyan
    
    # Install and import required modules
    $requiredModules = @('Microsoft.Graph.Authentication', 'Microsoft.Graph.DeviceManagement')
    foreach ($module in $requiredModules) {
        if (-not (Get-Module -ListAvailable $module)) {
            Write-Host "   Installing $module..." -ForegroundColor Cyan
            Install-Module $module -Force -Scope CurrentUser -ErrorAction Stop
        }
        Import-Module $module -ErrorAction Stop
    }

    Write-Host "🔐 Connecting to Microsoft Graph (SSO prompt)..." -ForegroundColor Cyan
    Write-Host "   Please select your account when prompted" -ForegroundColor Yellow
    $graphParams = @{
        NoWelcome = $true
        ErrorAction = 'Stop'
        ContextScope = 'Process'
        Scopes = @(
            'DeviceManagementManagedDevices.ReadWrite.All',
            'User.Read.All',
            'Directory.Read.All'
        )
    }
    Connect-MgGraph @graphParams

    $context = Get-MgContext
    if ($null -eq $context) {
        throw "Failed to get Microsoft Graph context"
    }
    Write-Host ("✅ Connected as {0}" -f $context.Account) -ForegroundColor Green
    Write-Host ("🏢 Organization: {0}" -f (Get-MgOrganization).DisplayName) -ForegroundColor Yellow
    Write-Host ""
    #endregion AUTHENTICATION

    #region INPUT
    # Accept either a hostname or a serial number as the device identifier.
    # The script will search both deviceName and serialNumber and present
    # a selection if multiple matches are found.
    $deviceIdentifier = Read-Host -Prompt "Enter device identifier (hostname or serial number)"
    if ([string]::IsNullOrWhiteSpace($deviceIdentifier)) {
        throw "Device identifier cannot be empty"
    }

    # Get new primary user UPN
    $userUPN = Read-Host -Prompt "Enter new primary user's email (UPN)"
    if ([string]::IsNullOrWhiteSpace($userUPN)) {
        throw "User UPN cannot be empty"
    }
    #endregion INPUT

    #region VALIDATION
    Write-Host "🔍 Validating device and user..." -ForegroundColor Cyan

    # Search for devices by name and by serial number (case-insensitive where supported).
    $filterName = "deviceName eq '$deviceIdentifier'"
    $filterSerial = "serialNumber eq '$deviceIdentifier'"

    $allDevices = [System.Collections.ArrayList]::new()
    
    try { 
        $devicesByName = @(Get-MgDeviceManagementManagedDevice -Filter $filterName -ErrorAction Stop)
        if ($devicesByName) { $allDevices.AddRange($devicesByName) }
    } catch { }
    
    try { 
        $devicesBySerial = @(Get-MgDeviceManagementManagedDevice -Filter $filterSerial -ErrorAction Stop)
        if ($devicesBySerial) { $allDevices.AddRange($devicesBySerial) }
    } catch { }

    # Remove duplicates by Id
    $allDevices = @($allDevices | Sort-Object -Property Id -Unique)

    if (-not $allDevices -or $allDevices.Count -eq 0) {
        throw "No devices found matching '$deviceIdentifier'"
    }

    # If multiple devices are found, prompt the user to choose one
    if ($allDevices.Count -gt 1) {
        Write-Host "Multiple devices matched the identifier. Please select the correct device:" -ForegroundColor Yellow
        for ($i = 0; $i -lt $allDevices.Count; $i++) {
            $d = $allDevices[$i]
            Write-Host "[$i] Name: $($d.DeviceName) | Model: $($d.Model) | OS: $($d.OperatingSystem) | Serial: $($d.SerialNumber) | Id: $($d.Id)"
        }
        $selection = Read-Host -Prompt "Enter the number of the device to update"
        if (-not ($selection -as [int]) -or [int]$selection -lt 0 -or [int]$selection -ge $allDevices.Count) {
            throw "Invalid selection"
        }
        $device = $allDevices[[int]$selection]
    }
    else {
        $device = $allDevices[0]
    }

    # Find user in Azure AD
    $user = Get-MgUser -Filter "userPrincipalName eq '$userUPN'" -ErrorAction SilentlyContinue
    if ($null -eq $user) {
        throw "User '$userUPN' not found in Azure AD"
    }

    # Display current state
    Write-Host "📱 Device selected:" -ForegroundColor Green
    Write-Host "   Name: $($device.DeviceName)"
    Write-Host "   Serial: $($device.SerialNumber)"
    Write-Host "   Model: $($device.Model)"
    Write-Host "   OS: $($device.OperatingSystem) $($device.OSVersion)"
    Write-Host ""

    Write-Host "👤 New primary user:" -ForegroundColor Green
    Write-Host "   Name: $($user.DisplayName)"
    Write-Host "   Email: $($user.UserPrincipalName)"
    Write-Host ""

    # Confirm change
    $confirmation = Read-Host -Prompt "Confirm primary user change? (y/n)"
    if ($confirmation -ne 'y') {
        throw "Operation cancelled by user"
    }
    #endregion VALIDATION

    #region UPDATE
    Write-Host "📝 Updating primary user..." -ForegroundColor Cyan

    try {
        Write-Host "   Assigning new primary user..." -ForegroundColor Cyan
        
        # Attempt 1: Try beta endpoint with users reference (most reliable method)
        try {
            $apiUrl = "https://graph.microsoft.com/beta/deviceManagement/managedDevices('$($device.Id)')/users/`$ref"
            $requestBody = @{
                "@odata.id" = "https://graph.microsoft.com/beta/users/$($user.Id)"
            }
            
            # Remove existing primary user first
            try {
                Invoke-MgGraphRequest -Method DELETE -Uri $apiUrl -ErrorAction SilentlyContinue
                Write-Host "   Removed existing primary user" -ForegroundColor Yellow
                Start-Sleep -Seconds 2
            } catch {
                # Ignore if no existing user
            }
            
            # Add new primary user
            Invoke-MgGraphRequest -Method POST -Uri $apiUrl -Body ($requestBody | ConvertTo-Json)
            Write-Host "   New primary user assigned via beta endpoint" -ForegroundColor Green
        }
        catch {
            Write-Host "   Beta endpoint failed, trying v1.0..." -ForegroundColor Yellow
            
            # Attempt 2: Try v1.0 endpoint
            $apiUrl = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices('$($device.Id)')/users/`$ref"
            $requestBody = @{
                "@odata.id" = "https://graph.microsoft.com/v1.0/users/$($user.Id)"
            }
            
            Invoke-MgGraphRequest -Method POST -Uri $apiUrl -Body ($requestBody | ConvertTo-Json)
            Write-Host "   New primary user assigned via v1.0 endpoint" -ForegroundColor Green
        }
        
        # Wait for change to propagate
        Write-Host "   Waiting for changes to sync..." -ForegroundColor Cyan
        Start-Sleep -Seconds 5
        
        # Verify the update
        $updatedDevice = Get-MgDeviceManagementManagedDevice -ManagedDeviceId $device.Id
        if ($updatedDevice.UserId -eq $user.Id -or $updatedDevice.UserPrincipalName -eq $userUPN) {
            Write-Host "✅ Primary user successfully updated and verified!" -ForegroundColor Green
        }
        else {
            Write-Host "⚠️ Update completed but verification inconclusive. Please check Intune portal." -ForegroundColor Yellow
        }
    }
    catch {
        Write-Error "Failed to update primary user: $_"
        Write-Host ""
        Write-Host "💡 Troubleshooting tips:" -ForegroundColor Yellow
        Write-Host "   1. Verify you have 'Cloud Device Administrator' or 'Intune Administrator' role"
        Write-Host "   2. Check if the device is actively syncing with Intune"
        Write-Host "   3. Try updating manually in Intune portal to confirm permissions"
        throw
    }
    #endregion UPDATE
}
catch {
    Write-Error "Error: $_"
    exit 1
}
finally {
    #region CLEANUP
    try {
        Disconnect-MgGraph -ErrorAction SilentlyContinue
        Write-Host "👋 Disconnected from Microsoft Graph" -ForegroundColor Cyan
    }
    catch {
        Write-Warning "Failed to disconnect from Microsoft Graph: $_"
    }
    
    # Clean up sensitive variables
    Remove-Variable -Name user, device, context -ErrorAction SilentlyContinue
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    #endregion CLEANUP
}
