# Get-DeviceRiskScore.ps1

## Overview
Calculates comprehensive risk scores for Intune-managed devices based on multiple security and compliance factors, including real-time Microsoft Defender for Endpoint (ATP) data from Intune's Defender Agents report.

## Features
- **Multi-factor Risk Assessment**
  - Compliance state (30% weight)
  - Last sync date (20% weight)
  - OS version currency (15% weight)
  - Encryption status (20% weight)
  - Microsoft Defender for Endpoint health (15% weight)

- **Real-time ATP Integration via Intune Reports**
  - Onboarding status verification (Onboarded/Not Onboarded)
  - Defender sensor status (Sense running/not running)
  - Real-time protection monitoring
  - Tamper protection status
  - Product status (Healthy, Scan Overdue, Reboot Required, etc.)
  - Malware protection enabled check
  - Automatic correlation between Intune devices and Defender data

- **Risk Categorization**
  - Critical (76-100 points)
  - High (51-75 points)
  - Medium (26-50 points)
  - Low (0-25 points)

- **Actionable Recommendations**
  - Specific remediation guidance for each risk factor
  - Prioritized action items for high-risk devices

- **Comprehensive Reporting**
  - CSV export with all risk factors and ATP details
  - Summary statistics by risk level
  - Average risk score calculation

## Requirements
- PowerShell 7.0 or higher
- Microsoft Graph PowerShell modules:
  - Microsoft.Graph.Authentication
  - Microsoft.Graph.DeviceManagement
- Required Graph API permissions (delegated):
  - DeviceManagementManagedDevices.Read.All
  - DeviceManagementConfiguration.Read.All
  - Directory.Read.All
- Azure AD roles (one of):
  - Intune Administrator
  - Security Administrator
  - Security Reader
  - Global Reader

## Important Notes
- **100% Read-Only**: Script uses only read permissions and cannot modify any settings
- **No App Registration Required**: Uses delegated authentication with interactive SSO
- **Works Without Defender for Endpoint**: Script continues gracefully if ATP is not configured

## Usage
```powershell
.\Get-DeviceRiskScore.ps1
```

The script will:
1. Connect to Microsoft Graph with SSO authentication
2. Retrieve all Intune-managed devices
3. Retrieve Microsoft Defender for Endpoint data
4. Calculate risk scores for each device
5. Display summary statistics
6. Prompt to export results to CSV

## Output Format
The CSV report includes:
- Device identification (name, user, model, serial number)
- Operating system details and version status
- Compliance and sync information
- Encryption status
- **Defender ATP Status** (overall status summary)
- **Defender ATP Onboarding** (Onboarded/Not Onboarded/N/A)
- **Defender ATP Sense Running** (Running/Not Running/N/A)
- **Defender ATP Real-Time Protection** (Enabled/Disabled/N/A)
- **Defender ATP Tamper Protection** (Enabled/Disabled/N/A)
- **Defender ATP Product Status** (Healthy/Scan Overdue/Reboot Required/etc.)
- Overall risk score (0-100)
- Risk level categorization
- Specific recommendations for remediation

## Risk Scoring Logic

### Compliance State (30 points max)
- Non-compliant: 30 points
- Error: 25 points
- Conflict: 20 points
- Unknown: 15 points
- Compliant: 0 points

### Last Sync Date (20 points max)
- Never synced: 20 points
- >30 days: 20 points
- 15-30 days: 15 points
- 8-14 days: 10 points
- 4-7 days: 5 points
- <3 days: 0 points

### OS Version (15 points max)
- Critical outdated: 15 points
- Outdated: 10 points
- Older supported: 5 points
- Current: 0 points

### Encryption Status (20 points max)
- Not encrypted: 20 points
- Unknown: 10 points
- Encrypted: 0 points

### Microsoft Defender for Endpoint (15 points max)
- **Windows devices not onboarded**: 15 points
- **Defender sensor not running**: 12 points
- **Real-time protection disabled**: 10 points
- **Tamper protection disabled**: 8 points
- **Product not protecting device**: 15 points
- **Reboot required**: 7 points
- **Full scan overdue**: 6 points
- **Quick scan overdue**: 5 points
- **Healthy and protected**: 0 points
- **Non-Windows devices**: 0 points (N/A)

## Example Output
```
📊 Risk Assessment Summary:
   🔴 Critical Risk: 5 devices
   🟠 High Risk: 12 devices
   🟡 Medium Risk: 23 devices
   🟢 Low Risk: 160 devices
   
   Total Devices Assessed: 200
   Average Risk Score: 18.45 / 100

🛡️  Defender for Endpoint Summary:
   ✅ Onboarded: 185 devices
   ❌ Not Onboarded: 15 devices
```

## Notes
- Uses Intune's Defender Agents report API for ATP data (more reliable than Security API)
- ATP data is only applicable to Windows devices
- Non-Windows devices (iOS, Android) automatically receive 0 ATP risk points
- If ATP data cannot be retrieved, the script continues without ATP health information
- Devices are matched between Intune and ATP by device name and device ID
- The script uses modern authentication with interactive SSO
- No app registration or client secrets required
- 100% read-only operations - cannot modify any settings

## Version History
- **1.1.0** (November 6, 2025)
  - Changed ATP data source to use Intune Defender Agents report API
  - Improved reliability of ATP data retrieval
  - Added detailed Defender status fields (Sense running, RTP, Tamper Protection, Product Status)
  - Enhanced risk scoring based on specific Defender protection states
  - Removed dependency on Microsoft.Graph.Security module
  - Simplified permissions (no longer requires SecurityEvents.Read.All)
- **1.0.0** (November 6, 2025)
  - Initial release with multi-factor risk assessment
  - Microsoft Defender for Endpoint integration
  - Automated recommendations engine
