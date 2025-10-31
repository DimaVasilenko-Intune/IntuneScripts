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

# Clear any existing sessions
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

    Write-Host "🔐 Connecting to Microsoft Graph..." -ForegroundColor Cyan
    $graphParams = @{
        NoWelcome = $true
        ErrorAction = 'Stop'
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
    # Get device name from user
    $deviceName = Read-Host -Prompt "Enter device name"
    if ([string]::IsNullOrWhiteSpace($deviceName)) {
        throw "Device name cannot be empty"
    }

    # Get new primary user UPN
    $userUPN = Read-Host -Prompt "Enter new primary user's email (UPN)"
    if ([string]::IsNullOrWhiteSpace($userUPN)) {
        throw "User UPN cannot be empty"
    }
    #endregion INPUT

    #region VALIDATION
    Write-Host "🔍 Validating device and user..." -ForegroundColor Cyan

    # Find device in Intune
    $device = Get-MgDeviceManagementManagedDevice -Filter "deviceName eq '$deviceName'" -ErrorAction Stop
    if ($null -eq $device) {
        throw "Device '$deviceName' not found in Intune"
    }

    # Find user in Azure AD
    $user = Get-MgUser -Filter "userPrincipalName eq '$userUPN'" -ErrorAction Stop
    if ($null -eq $user) {
        throw "User '$userUPN' not found in Azure AD"
    }

    # Display current state
    Write-Host "📱 Device found:" -ForegroundColor Green
    Write-Host "   Name: $($device.DeviceName)"
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
        
        # Use v1.0 endpoint with direct user assignment
        $apiUrl = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices('$($device.Id)')"
        
        $requestBody = @{
            userPrincipalName = $userUPN
        }

        # Update the primary user
        Write-Host "   Applying changes..." -ForegroundColor Cyan
        Invoke-MgGraphRequest -Method PATCH -Uri $apiUrl -Body ($requestBody | ConvertTo-Json)
        
        # Wait for change to propagate
        Write-Host "   Waiting for changes to apply..." -ForegroundColor Cyan
        Start-Sleep -Seconds 3
        
        # Verify the update
        $updatedDevice = Get-MgDeviceManagementManagedDevice -ManagedDeviceId $device.Id
        if ($updatedDevice.UserPrincipalName -eq $userUPN) {
            Write-Host "✅ Primary user successfully updated!" -ForegroundColor Green
        }
        else {
            throw "Failed to verify primary user update"
        }
    }
    catch {
        throw "Failed to update primary user: $_"
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