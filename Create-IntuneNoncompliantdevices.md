# Create-IntuneNonCompliantDevices.ps1

## Purpose
Export all non-compliant devices from Microsoft Intune with detailed compliance policy failure information. Provides actionable insights into which compliance policies are failing and why, enabling IT teams to remediate non-compliant devices efficiently.

## Requirements

### Permissions Required
- **Intune Administrator** or **Global Reader** role
- Microsoft Graph API Permissions:
  - `DeviceManagementManagedDevices.Read.All` - Read Intune managed devices
  - `DeviceManagementConfiguration.Read.All` - Read compliance policies and configurations

### Prerequisites
- PowerShell 5.1 or higher
- Microsoft.Graph PowerShell module
- Internet connectivity for SSO authentication

## Features

### Compliance Details Captured
- ✅ **Device Information** - Name, OS, OS version, manufacturer, model, serial number
- ✅ **User Assignment** - Primary user (UserPrincipalName)
- ✅ **Compliance State** - Current compliance status
- ✅ **Policy Details** - Name of failed compliance policy
- ✅ **Failed Settings** - Specific settings that caused non-compliance with error descriptions
- ✅ **Grace Period** - When device will be marked non-compliant if not remediated
- ✅ **Last Sync** - When device last checked in with Intune
- ✅ **Last Reported** - When compliance state was last evaluated

### Output Format
CSV file with the following columns:
```
DeviceName, UserPrincipalName, OperatingSystem, OSVersion, ComplianceState,
PolicyName, PolicyState, FailedSettings, GracePeriodExpirationDateTime,
LastReportedDateTime, Model, Manufacturer, SerialNumber, LastSyncDateTime, DeviceId
```

## Technical Architecture

### Authentication
- Uses delegated authentication with SSO (Single Sign-On)
- `ContextScope = 'Process'` forces fresh authentication every run
- Perfect for multi-tenant scenarios
- No cached credentials - always prompts for account selection

### Data Retrieval Process
1. **Connect to Microsoft Graph** - SSO authentication with delegated permissions
2. **Retrieve Non-Compliant Devices** - Filter by `complianceState eq 'noncompliant'`
3. **For Each Device:**
   - Query device compliance policy states via Graph beta endpoint
   - Retrieve setting-level details for failed policies
   - Extract failed settings with error descriptions
   - Compile detailed report entry
4. **Export to CSV** - SaveFileDialog prompts user for export location

### Rate Limiting
- 100ms delay between device processing
- Prevents API throttling during bulk operations
- Suitable for tenants with hundreds of devices

## Constraints & Considerations

### Performance
- Small tenants (< 50 devices): ~30 seconds
- Medium tenants (50-200 devices): 1-3 minutes
- Large tenants (200+ devices): 3-10 minutes
- Progress indicator shows real-time status

### Limitations
- Requires delegated authentication (interactive SSO)
- Uses beta Graph API endpoints for detailed compliance data
- One row per policy failure (device can have multiple rows if failing multiple policies)
- Cannot remediate devices automatically (read-only permissions)

### Security
- No app registration required (uses delegated permissions)
- Read-only access - cannot modify device or policy settings
- Disconnects from Graph session upon completion
- Cleans up sensitive variables from memory

## Steps to Execute

### 1. Authentication
```powershell
# Script handles this automatically with SSO prompt
# Select your account when browser opens
```

### 2. Device Retrieval
- Script queries all managed devices with non-compliant status
- Displays count of non-compliant devices found
- If zero devices, script exits with success message

### 3. Compliance Detail Processing
- Progress bar shows: "Processing Compliance Details (X/Y)"
- For each device, retrieves:
  - Compliance policy states
  - Setting states for failed policies
  - Error descriptions for failed settings

### 4. Export
- SaveFileDialog appears (always on top)
- Default filename: `NonCompliantDevices-Detailed-YYYYMMDD-HHMMSS.csv`
- Choose export location
- Script offers to open CSV file after export

### 5. Cleanup
- Disconnects from Microsoft Graph
- Clears variables from memory
- Garbage collection

## Output

### Success Output (With Non-Compliant Devices)
```
📦 Checking Microsoft Graph module...
🔐 Connecting to Microsoft Graph (SSO prompt)...
   Please select your account when prompted
✅ Connected as admin@contoso.com
🏢 Organization: Contoso Ltd

📱 Retrieving non-compliant devices...
   Found 15 non-compliant devices

🔍 Retrieving compliance details for each device...
   Processing: 15/15 (100%) - DESKTOP-ABC123

✅ Processed compliance details for 15 devices
📊 Total policy violations found: 23

💾 Exported to: C:\Users\...\NonCompliantDevices-Detailed-20251105-143022.csv

📊 Report Summary:
   Total Devices: 15
   Total Policy Violations: 23

Would you like to open the CSV file now? (y/n):
👋 Disconnected from Microsoft Graph
```

### Success Output (Zero Non-Compliant Devices)
```
📦 Checking Microsoft Graph module...
🔐 Connecting to Microsoft Graph (SSO prompt)...
   Please select your account when prompted
✅ Connected as admin@contoso.com
🏢 Organization: Contoso Ltd

📱 Retrieving non-compliant devices...
   Found 0 non-compliant devices
✨ No non-compliant devices found - tenant is fully compliant!
👋 Disconnected from Microsoft Graph
```

### CSV Example
```csv
DeviceName,UserPrincipalName,OperatingSystem,OSVersion,ComplianceState,PolicyName,PolicyState,FailedSettings,GracePeriodExpirationDateTime,LastReportedDateTime,Model,Manufacturer,SerialNumber,LastSyncDateTime,DeviceId
DESKTOP-ABC123,john@contoso.com,Windows,10.0.19045.3803,noncompliant,Corporate Windows Policy,nonCompliant,BitLockerEnabled: BitLocker is not enabled; PasswordRequired: Password complexity not met,2025-11-12T10:30:00Z,2025-11-05T14:22:15Z,Virtual Machine,Microsoft Corporation,1234-5678,2025-11-05T14:20:00Z,abc-123-def
LAPTOP-XYZ789,jane@contoso.com,Windows,10.0.22631.2715,noncompliant,Security Baseline,nonCompliant,AntivirusEnabled: Windows Defender disabled,2025-11-10T08:15:00Z,2025-11-05T09:10:30Z,Latitude 7420,Dell Inc.,ABCD-9876,2025-11-05T09:05:00Z,xyz-456-ghi
```

## Testing Steps

### 1. Pre-Test Validation
- Verify you have Intune Administrator or Global Reader role
- Confirm PowerShell 5.1+ is installed: `$PSVersionTable.PSVersion`
- Check Microsoft.Graph module: `Get-Module -ListAvailable Microsoft.Graph`

### 2. Test Execution
```powershell
.\Create-IntuneNonCompliantDevices.ps1
```

### 3. Validation Checks
- ✅ Script prompts for SSO login every time (no cached credentials)
- ✅ Displays tenant name after authentication
- ✅ Shows count of non-compliant devices found
- ✅ Progress indicator updates during processing
- ✅ SaveFileDialog appears on top of other windows
- ✅ CSV file is created at chosen location
- ✅ Excel/LibreOffice can open the CSV without errors
- ✅ Failed settings column contains detailed error descriptions
- ✅ One row per policy failure (not per device)
- ✅ Script disconnects cleanly

### 4. Test Cases
- **Test 1**: Run in tenant with 0 non-compliant devices → Should exit gracefully with success message
- **Test 2**: Run in tenant with 1-5 non-compliant devices → Verify all policy details captured
- **Test 3**: Run in tenant with 50+ devices → Verify performance and progress indicator
- **Test 4**: Cancel SaveFileDialog → Script should exit gracefully
- **Test 5**: Run script twice in succession → Should prompt for SSO both times (no cached auth)
- **Test 6**: Device failing multiple policies → Should create multiple rows in CSV

## Troubleshooting

### Common Issues

**Issue**: "Insufficient privileges to complete the operation"
- **Solution**: Verify you have Intune Administrator or Global Reader role
- **Check**: Azure AD → Roles and administrators → Search for your user

**Issue**: Script hangs after "Authentication complete" in browser
- **Solution**: Close PowerShell completely and open a new session
- **Alternative**: Wait 30 seconds - may be retrieving organization details

**Issue**: "The property 'Count' cannot be found on this object"
- **Solution**: Already fixed in v2.0 - upgrade to latest version
- **Cause**: Script now wraps result in `@()` array to ensure Count property exists

**Issue**: Progress bar shows but no compliance details retrieved
- **Solution**: Some devices may not have policy state information available
- **Check CSV**: Look for entries with "Unable to retrieve compliance details"

**Issue**: SaveFileDialog doesn't appear
- **Solution**: Check taskbar - dialog may be minimized
- **Alternative**: Script uses owner form with TopMost = true to prevent this

**Issue**: "Failed to get compliance details" warnings
- **Solution**: Normal for some devices - script continues processing others
- **Note**: These devices will appear in CSV with error information

**Issue**: Context information appears after disconnect
- **Solution**: Already fixed in v2.0 - added `| Out-Null` to Disconnect-MgGraph

## Version History

| Version | Date | Author | Changes |
|---------|------|--------|---------|
| 1.0.0 | Oct 30, 2025 | Dima Vasilenko | Initial release with basic non-compliant device export |
| 2.0.0 | Nov 5, 2025 | Dima Vasilenko | Added detailed compliance reasons, failed settings, policy names, grace period info, SSO forced authentication, progress indicator, improved error handling |

## Related Scripts
- `Change-PrimaryUser.ps1` - Change device primary user
- `Export-IntuneAppAssignments.ps1` - Export app assignments
- `GetNonOnboardedDefenderDevices.ps1` - List devices not onboarded to Defender

## Notes
- Script is multi-tenant compatible (forces SSO every run)
- No app registration or certificate required
- Safe for production use (read-only operations)
- Recommended to run weekly for compliance monitoring
- CSV can be imported into Power BI or Excel for dashboards
