# Export-IntuneAppAssignments.ps1

## Purpose
Export all Intune application assignments (Win32, Store Apps, LOB, Managed Apps) with their assigned groups to CSV format. Provides a comprehensive "Intune app inventory" useful for audits, documentation, and compliance reviews.

## Requirements

### Permissions Required
- **Intune Administrator** or **Global Reader** role
- Microsoft Graph API Permissions:
  - `DeviceManagementApps.Read.All` - Read Intune app information
  - `Group.Read.All` - Read Azure AD group information
  - `Directory.Read.All` - Read directory objects

### Prerequisites
- PowerShell 7.0 or higher
- Microsoft.Graph.Intune PowerShell module
- Microsoft.Graph.Authentication PowerShell module
- Microsoft.Graph.Groups PowerShell module

## Features

### Application Types Covered
- ✅ **Win32 Apps** - Custom .intunewin packages
- ✅ **Microsoft Store Apps** - Apps from Microsoft Store for Business
- ✅ **Line-of-Business (LOB) Apps** - Custom MSI/MSIX packages
- ✅ **Managed Apps** - MAM policy protected apps
- ✅ **Web Links** - Web app shortcuts
- ✅ **Built-in Apps** - iOS/Android built-in apps

### Assignment Information Exported
- Application Name
- Application Type
- Publisher
- Assignment Type (Required, Available, Uninstall)
- Target Group Name
- Target Group ID
- Assignment Intent
- Filter Mode (Include/Exclude)
- Filter Name
- Platform (Windows, iOS, Android, macOS)

### Output Format
CSV file with the following columns:
```
AppName, AppType, Publisher, Platform, AssignmentType, GroupName, GroupID, Intent, FilterMode, FilterName, AppID
```

## Constraints & Considerations

### Performance
- Large tenants (500+ apps) may take 5-10 minutes to complete
- Script uses throttling to respect Graph API rate limits
- Progress indicator shows current processing status

### Limitations
- Requires delegated authentication (interactive SSO)
- Does not export app configuration settings
- Does not show deployment status or installation counts
- Group membership details are not expanded

### Security
- No app registration required (uses delegated permissions)
- Does not export sensitive data like package content or install commands
- Disconnects from Graph session upon completion

## Steps to Execute

### 1. Authentication
```powershell
Connect-MgGraph -Scopes "DeviceManagementApps.Read.All", "Group.Read.All", "Directory.Read.All"
```

### 2. Data Collection Process
1. Retrieve all application types from Intune
2. For each application:
   - Get app metadata (name, type, publisher, platform)
   - Retrieve all assignments
   - Resolve group names from group IDs
   - Extract assignment intent and filter information
3. Combine all data into a structured array

### 3. CSV Export
- Prompts user with SaveFileDialog to choose export location
- Default filename: `IntuneAppAssignments_YYYY-MM-DD.csv`
- UTF-8 encoding with BOM for Excel compatibility

### 4. Cleanup
- Disconnect from Microsoft Graph
- Clear sensitive variables from memory
- Display export summary (total apps, total assignments)

## Output

### Success Output
```
✅ Export completed successfully!
📊 Summary:
   - Total Apps: 145
   - Total Assignments: 423
   - Export Location: C:\Users\...\IntuneAppAssignments_2025-11-05.csv
```

### CSV Example
```csv
AppName,AppType,Publisher,Platform,AssignmentType,GroupName,GroupID,Intent,FilterMode,FilterName,AppID
"Microsoft 365 Apps","Win32App","Microsoft","Windows","Required","All Users","abc-123","required","","",""
"Company Portal","ManagedApp","Microsoft","iOS","Available","All Devices","def-456","available","include","Corporate Devices",""
```

## Testing Steps

### 1. Pre-Test Validation
- Verify you have appropriate admin role
- Confirm PowerShell 7+ is installed: `pwsh --version`
- Check module availability

### 2. Test Execution
```powershell
.\Export-IntuneAppAssignments.ps1
```

### 3. Validation Checks
- ✅ Script prompts for SSO login
- ✅ Progress indicator shows app processing
- ✅ SaveFileDialog appears
- ✅ CSV file is created at chosen location
- ✅ Excel/LibreOffice can open the CSV without errors
- ✅ Data contains expected apps and assignments
- ✅ Group names are resolved (not just IDs)

### 4. Test Cases
- **Test 1**: Run in tenant with 0 apps → Should create empty CSV with headers
- **Test 2**: Run in tenant with apps but no assignments → Should list apps with "No Assignments"
- **Test 3**: Run in tenant with 50+ apps → Verify performance and accuracy
- **Test 4**: Cancel SaveFileDialog → Script should exit gracefully

## Troubleshooting

### Common Issues

**Issue**: "Insufficient privileges to complete the operation"
- **Solution**: Verify you have Intune Administrator or Global Reader role

**Issue**: Script hangs during app retrieval
- **Solution**: Graph API throttling - wait 60 seconds and retry

**Issue**: Group names show as GUIDs instead of friendly names
- **Solution**: Ensure `Group.Read.All` permission is consented

**Issue**: Missing some app types in export
- **Solution**: Check if you're using beta vs v1.0 Graph API endpoint

## Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | 2025-11-05 | Dima Vasilenko | Initial release with Win32, Store, LOB, Managed app support |

## Related Scripts
- `Create-IntuneNonCompliantDevices.ps1` - Export non-compliant devices
- `Change-PrimaryUser.ps1` - Change device primary user

## Notes
- Script is multi-tenant compatible
- No app registration or certificate required
- Safe for production use (read-only operations)
- Recommended to run monthly for audit purposes
