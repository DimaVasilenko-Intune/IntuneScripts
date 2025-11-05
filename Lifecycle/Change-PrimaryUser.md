# Change Primary User in Intune 🔄

## Purpose 🎯
This PowerShell script provides Intune administrators with an interactive way to change the Primary User assignment for devices managed in Microsoft Intune. It simplifies the process of updating primary user associations without requiring direct Azure Portal access.

## Requirements 📋

### System Requirements
- PowerShell 7.0 or higher
- Microsoft.Graph PowerShell SDK
- Windows 10/11 or Windows Server 2019/2022

### Permissions Required
- **Microsoft Graph Permissions**:
  - `DeviceManagementManagedDevices.ReadWrite.All`
  - `User.Read.All`
  - `Directory.Read.All`

### Authentication
- Modern authentication (interactive login)
- Support for multi-tenant access
- No app registration required

## Constraints and Limitations ⚠️
- Only works with devices already enrolled in Intune
- One primary user per device
- Cannot modify devices in error state
- No external data lookups
- Uses only Microsoft Graph API calls
- No batch operations (one device at a time)

## Process Flow 🔄

### 1. Initialization
- Verify PowerShell version
- Check for required modules
- Initialize Microsoft Graph connection
- Validate permissions

### 2. Device Selection
- Accept device identifier (name or ID)
- Verify device exists in Intune
- Display current device information
- Show current primary user (if any)

### 3. User Selection
- Accept new user UPN or ID
- Validate user exists in Azure AD
- Display user information for confirmation

### 4. Primary User Change
- Remove existing primary user (if present)
- Assign new primary user
- Verify assignment was successful
- Update device attributes

### 5. Cleanup
- Disconnect from Microsoft Graph
- Clear sensitive variables
- Display success/failure message

## Expected Output 📝

### Success Messages
```
✅ Connected to Microsoft Graph
📱 Device Found: [DeviceName]
👤 Current Primary User: [CurrentUserUPN]
👥 New Primary User Selected: [NewUserUPN]
✔️ Primary User Successfully Changed
```

### Error Messages
```
❌ Device not found
❌ User not found
❌ Insufficient permissions
❌ Assignment failed
```

## Testing Instructions 🧪

### Pre-requisites Testing
1. Run script with incorrect PowerShell version
2. Run without required modules
3. Run without proper permissions

### Functional Testing
1. Change primary user on:
   - Windows device
   - iOS/iPadOS device
   - Android device
2. Try invalid device names
3. Try invalid user UPNs
4. Change to same primary user
5. Remove primary user entirely

### Error Handling Testing
1. Test with network disconnection
2. Test with invalid permissions
3. Test with non-existent devices
4. Test with non-existent users

## Version History 📚

### Version 1.0.0 (October 30, 2025)
- Initial release
- Basic primary user change functionality
- Interactive device and user selection
- Author: Dima Vasilenko

### Version 1.1.0 (October 30, 2025)
- Added error handling
- Improved user feedback
- Added validation checks
- Author: Dima Vasilenko

## Support 💬
For issues and feature requests, please contact:
- Author: Dima Vasilenko
- Organization: Crayon Group
- Last Updated: October 30, 2025
