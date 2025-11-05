#Requires -Version 7.0
<#
.SYNOPSIS
    Export all Intune application assignments to CSV.
.DESCRIPTION
    Exports all application assignments (Win32, Store, LOB, Managed) from Microsoft Intune
    with their assigned groups to CSV format. Provides comprehensive app inventory for audits.
.NOTES
    Version: 1.0.0
    Author: Dima Vasilenko
    Last Modified: November 5, 2025
#>

# Enable strict mode for better error handling
Set-StrictMode -Version Latest

# Clear any existing sessions and cached credentials
Disconnect-MgGraph -ErrorAction SilentlyContinue

try {
    #region AUTHENTICATION
    Write-Host "📦 Checking Microsoft Graph modules..." -ForegroundColor Cyan
    
    # Install and import required modules
    $requiredModules = @(
        'Microsoft.Graph.Authentication',
        'Microsoft.Graph.DeviceManagement',
        'Microsoft.Graph.Groups'
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
    
    $graphParams = @{
        NoWelcome = $true
        ErrorAction = 'Stop'
        ContextScope = 'Process'
        Scopes = @(
            'DeviceManagementApps.Read.All',
            'Group.Read.All',
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

    #region DATA COLLECTION
    Write-Host "📱 Retrieving Intune applications..." -ForegroundColor Cyan
    
    # Initialize results array
    $allAssignments = [System.Collections.ArrayList]::new()
    $allApps = [System.Collections.ArrayList]::new()
    $appCount = 0
    
    # Retrieve all apps at once (simpler and more reliable)
    try {
        Write-Host "   Querying all mobile apps..." -ForegroundColor Cyan
        $uri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps"
        $response = Invoke-MgGraphRequest -Method GET -Uri $uri
        
        if ($response.value) {
            $allApps.AddRange($response.value)
            $appCount += $response.value.Count
        }
        
        # Handle pagination
        while ($response.PSObject.Properties.Name -contains '@odata.nextLink') {
            $response = Invoke-MgGraphRequest -Method GET -Uri $response.'@odata.nextLink'
            if ($response.value) {
                $allApps.AddRange($response.value)
                $appCount += $response.value.Count
            }
        }
        
        # Count apps by type for summary
        $appTypeCounts = $allApps | Group-Object -Property '@odata.type' | ForEach-Object {
            $typeName = $_.Name -replace '#microsoft.graph.', ''
            Write-Host "      Found $($_.Count) $typeName apps" -ForegroundColor Gray
        }
    }
    catch {
        throw "Failed to retrieve apps from Intune: $_"
    }
    
    Write-Host ""
    Write-Host "✅ Found $appCount applications" -ForegroundColor Green
    Write-Host ""
    
    if ($appCount -eq 0) {
        Write-Host "⚠️  No applications found in this tenant" -ForegroundColor Yellow
        throw "No applications to export"
    }
    
    # Process each app and get assignments
    Write-Host "🔍 Processing application assignments..." -ForegroundColor Cyan
    $processedCount = 0
    
    foreach ($app in $allApps) {
        $processedCount++
        $percentComplete = [math]::Round(($processedCount / $appCount) * 100, 0)
        Write-Host "`r   Processing: $processedCount/$appCount ($percentComplete%) - $($app.displayName)" -NoNewline -ForegroundColor Gray
        
        try {
            # Get assignments for this app
            $assignmentsUri = "https://graph.microsoft.com/beta/deviceAppManagement/mobileApps/$($app.id)/assignments"
            $assignmentsResponse = Invoke-MgGraphRequest -Method GET -Uri $assignmentsUri
            
            if ($assignmentsResponse.value -and $assignmentsResponse.value.Count -gt 0) {
                foreach ($assignment in $assignmentsResponse.value) {
                    # Determine assignment type
                    $assignmentType = switch ($assignment.intent) {
                        'required' { 'Required' }
                        'available' { 'Available' }
                        'uninstall' { 'Uninstall' }
                        default { $assignment.intent }
                    }
                    
                    # Get group name if target is a group
                    $groupName = 'N/A'
                    $groupId = 'N/A'
                    
                    if ($assignment.target.'@odata.type' -eq '#microsoft.graph.groupAssignmentTarget') {
                        $groupId = $assignment.target.groupId
                        try {
                            $group = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/v1.0/groups/$groupId"
                            $groupName = $group.displayName
                        }
                        catch {
                            $groupName = "Unknown Group"
                        }
                    }
                    elseif ($assignment.target.'@odata.type' -eq '#microsoft.graph.allLicensedUsersAssignmentTarget') {
                        $groupName = 'All Users'
                    }
                    elseif ($assignment.target.'@odata.type' -eq '#microsoft.graph.allDevicesAssignmentTarget') {
                        $groupName = 'All Devices'
                    }
                    
                    # Determine platform
                    $platform = switch -Wildcard ($app.'@odata.type') {
                        '*win32*' { 'Windows' }
                        '*windows*' { 'Windows' }
                        '*ios*' { 'iOS' }
                        '*android*' { 'Android' }
                        '*macOS*' { 'macOS' }
                        '*webApp*' { 'Web' }
                        default { 'Unknown' }
                    }
                    
                    # Get filter information
                    $filterMode = if ($assignment.target.deviceAndAppManagementAssignmentFilterType) {
                        $assignment.target.deviceAndAppManagementAssignmentFilterType
                    } else { 'None' }
                    
                    $filterName = if ($assignment.target.deviceAndAppManagementAssignmentFilterId) {
                        try {
                            $filter = Invoke-MgGraphRequest -Method GET -Uri "https://graph.microsoft.com/beta/deviceManagement/assignmentFilters/$($assignment.target.deviceAndAppManagementAssignmentFilterId)"
                            $filter.displayName
                        }
                        catch {
                            'Unknown Filter'
                        }
                    } else { 'N/A' }
                    
                    # Create assignment object
                    $assignmentObj = [PSCustomObject]@{
                        AppName        = $app.displayName
                        AppType        = ($app.'@odata.type' -replace '#microsoft.graph.', '')
                        Publisher      = if ($app.publisher) { $app.publisher } else { 'N/A' }
                        Platform       = $platform
                        AssignmentType = $assignmentType
                        GroupName      = $groupName
                        GroupID        = $groupId
                        Intent         = $assignment.intent
                        FilterMode     = $filterMode
                        FilterName     = $filterName
                        AppID          = $app.id
                    }
                    
                    [void]$allAssignments.Add($assignmentObj)
                }
            }
            else {
                # App has no assignments
                $assignmentObj = [PSCustomObject]@{
                    AppName        = $app.displayName
                    AppType        = ($app.'@odata.type' -replace '#microsoft.graph.', '')
                    Publisher      = if ($app.publisher) { $app.publisher } else { 'N/A' }
                    Platform       = switch -Wildcard ($app.'@odata.type') {
                        '*win32*' { 'Windows' }
                        '*windows*' { 'Windows' }
                        '*ios*' { 'iOS' }
                        '*android*' { 'Android' }
                        '*macOS*' { 'macOS' }
                        '*webApp*' { 'Web' }
                        default { 'Unknown' }
                    }
                    AssignmentType = 'No Assignment'
                    GroupName      = 'N/A'
                    GroupID        = 'N/A'
                    Intent         = 'N/A'
                    FilterMode     = 'N/A'
                    FilterName     = 'N/A'
                    AppID          = $app.id
                }
                
                [void]$allAssignments.Add($assignmentObj)
            }
        }
        catch {
            Write-Warning "`nFailed to process assignments for $($app.displayName): $_"
        }
        
        # Rate limiting - small delay every 50 apps
        if ($processedCount % 50 -eq 0) {
            Start-Sleep -Milliseconds 500
        }
    }
    
    Write-Host "" # New line after progress
    Write-Host ""
    Write-Host "✅ Processed $processedCount applications" -ForegroundColor Green
    Write-Host "✅ Found $($allAssignments.Count) total assignments" -ForegroundColor Green
    Write-Host ""
    #endregion DATA COLLECTION

    #region EXPORT
    Write-Host "💾 Preparing to export..." -ForegroundColor Cyan
    
    # Create SaveFileDialog
    Add-Type -AssemblyName System.Windows.Forms
    
    # Create a dummy form to be the owner (prevents dialog hanging)
    $ownerForm = New-Object System.Windows.Forms.Form
    $ownerForm.TopMost = $true
    $ownerForm.StartPosition = 'CenterScreen'
    $ownerForm.WindowState = 'Minimized'
    $ownerForm.ShowInTaskbar = $false
    
    $saveDialog = New-Object System.Windows.Forms.SaveFileDialog
    $saveDialog.Filter = "CSV files (*.csv)|*.csv|All files (*.*)|*.*"
    $saveDialog.Title = "Save Intune App Assignments Export"
    $saveDialog.FileName = "IntuneAppAssignments_$(Get-Date -Format 'yyyy-MM-dd').csv"
    
    # Set initial directory to script location or user's Documents
    if ($PSScriptRoot) {
        $saveDialog.InitialDirectory = $PSScriptRoot
    } else {
        $saveDialog.InitialDirectory = [Environment]::GetFolderPath('MyDocuments')
    }
    
    $result = $saveDialog.ShowDialog($ownerForm)
    $ownerForm.Dispose()
    
    if ($result -eq [System.Windows.Forms.DialogResult]::OK) {
        $exportPath = $saveDialog.FileName
        
        try {
            $allAssignments | Export-Csv -Path $exportPath -NoTypeInformation -Encoding UTF8
            
            Write-Host ""
            Write-Host "✅ Export completed successfully!" -ForegroundColor Green
            Write-Host ""
            Write-Host "📊 Summary:" -ForegroundColor Cyan
            Write-Host "   - Total Apps: $appCount" -ForegroundColor White
            Write-Host "   - Total Assignments: $($allAssignments.Count)" -ForegroundColor White
            Write-Host "   - Export Location: $exportPath" -ForegroundColor White
            Write-Host ""
            
            # Ask if user wants to open the file
            $openFile = Read-Host "Open the CSV file now? (y/n)"
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
    #endregion EXPORT
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
    Remove-Variable -Name allAssignments, allApps, context -ErrorAction SilentlyContinue
    [System.GC]::Collect()
    [System.GC]::WaitForPendingFinalizers()
    #endregion CLEANUP
}
