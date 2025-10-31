# GOAL
Create a PowerShell script that lists all non-compliant Windows devices in Microsoft Intune, including the reason for non-compliance.

# REQUIREMENTS
- Use Microsoft.Graph PowerShell SDK.
- Authenticate to Microsoft Graph interactively.
- Query all devices from Intune with their compliance status.
- Filter to only include Windows devices where complianceState != "compliant".
- For each device, retrieve:
  - Device name
  - Primary user
  - Compliance state
  - Operating system
  - Last check-in date
  - Non-compliance reasons.
- Output the results in a readable table in the console.
- Export results to a CSV file (e.g. `NonCompliantDevices_<timestamp>.csv`).
- Include basic error handling and logging.
- Write clear, well-documented code that can be easily maintained.

# CONSTRAINTS
- DO NOT FETCH, SEARCH, OR REFERENCE ANY EXTERNAL DATA, CODE SAMPLES, OR DOCUMENTATION ONLINE.
- USE ONLY THE INFORMATION AND CONTEXT PROVIDED IN THIS MARKDOWN FILE.
- ASSUME THE USER ALREADY HAS THE MICROSOFT.GRAPH POWERSHELL SDK INSTALLED AND AUTHENTICATED.
- ALL LOGIC, SYNTAX, AND STRUCTURE MUST COME FROM THE CONTEXT IN THIS FILE ONLY.
- DO NOT INSERT EXAMPLES OR COMMENTS THAT ARE NOT BASED ON THE PROVIDED REQUIREMENTS.

# OUTPUT
Generate a ready-to-run PowerShell script (`.ps1`) that can be used to quickly identify non-compliant Windows devices and the reasons for their non-compliance, following the constraints above.
