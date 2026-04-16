# solarwinds-to-prtg-migration
PowerShell toolkit to export SolarWinds NPM nodes and import them into PRTG Network Monitor
SolarWinds → PRTG Migration Toolkit
PowerShell scripts to export monitored nodes from SolarWinds NPM and import them into PRTG Network Monitor — preserving device names, IPs, monitoring methods, SNMPv3 credentials metadata, and custom properties like Site and Location.
---
Overview
Migrating from SolarWinds to PRTG manually is tedious and error-prone. This toolkit automates the two main steps:
Export — queries your SolarWinds Orion server via SWQL and produces a structured CSV of all monitored nodes, including polling method, SNMP version, SNMPv3 credential metadata, and custom properties.
Import (coming soon) — reads the CSV and creates devices in PRTG via its HTTP API, pre-configured with the right sensors based on the polling method detected in SolarWinds.
---
Requirements
Requirement	Details
PowerShell	5.1 or later (7+ recommended)
SwisPowerShell module	`Install-Module -Name SwisPowerShell` (run as admin)
SolarWinds Orion	NPM with SWQL access
PRTG	Network Monitor with API access enabled
Permissions	Read access to Orion nodes, pollers, and credential tables
---
Scripts
`Export-SolarWindsNodes.ps1`
Connects to SolarWinds Orion and exports all monitored nodes to a CSV file.
Parameters
Parameter	Required	Description
`-SwHost` Yes	Hostname or FQDN of your Orion server
`-Credential`	 No	PSCredential for remote auth. Omit to use Windows auth (`-Trusted`) — only works on the Orion server itself
`-OutputPath`	 No	Full path for the output CSV. Defaults to the script's directory
Usage
```powershell
# Remote connection with credentials (recommended)
.\Export-SolarWindsNodes.ps1 -SwHost "orion.company.com" -Credential (Get-Credential)

# Running directly on the Orion server (Windows auth)
.\Export-SolarWindsNodes.ps1 -SwHost "localhost"

# Custom output path
.\Export-SolarWindsNodes.ps1 -SwHost "orion.company.com" -Credential (Get-Credential) -OutputPath "C:\Migration\nodes.csv"
```
Output CSV columns
Column	Description
`NodeID`	SolarWinds internal node ID
`Name`	Device caption/display name
`IP`	Primary IP address
`DNS`	DNS hostname
`SysName`	SNMP system name
`Vendor`	Detected vendor (Cisco, HP, etc.)
`Model`	Hardware model
`Description`	Node description
`Site`	Custom property: Site
`Location`	Custom property: Location
`PollingMethod`	`SNMPv2c`, `SNMPv3`, `WMI`, `ICMP`, or `Agent`
`SensorHints`	Suggested PRTG sensors based on SolarWinds pollers
`SNMPVersion`	SNMP version in use
`SNMPv3User`	SNMPv3 username (non-secret metadata only)
`SNMPv3Auth`	SNMPv3 authentication method (e.g. SHA)
`SNMPv3Priv`	SNMPv3 privacy/encryption method (e.g. AES)
> **Note:** SNMP community strings and SNMPv3 keys/passwords are **not** exported — SolarWinds protects these fields. You will need to re-enter credentials in PRTG.
---
`Import-NodesToPRTG.ps1` (coming soon)
Will read the CSV produced by the export script and create devices in PRTG via its REST API, including auto-suggested sensors based on the `PollingMethod` and `SensorHints` columns.
---
Getting Started
1. Install the SwisPowerShell module (one-time, run as Administrator):
```powershell
Install-Module -Name SwisPowerShell -Scope CurrentUser
```
2. Clone this repo:
```bash
git clone https://github.com/YOUR-USERNAME/solarwinds-to-prtg-migration.git
cd solarwinds-to-prtg-migration
```
3. Run the export:
```powershell
cd src
.\Export-SolarWindsNodes.ps1 -SwHost "orion.company.com" -Credential (Get-Credential)
```
4. Review the CSV before running the import — check that `PollingMethod` and `SensorHints` look correct for your environment.
---
Custom Properties
The export script pulls `Site` and `Location` custom properties by default. If your SolarWinds environment uses different custom property names, edit these lines in `Export-SolarWindsNodes.ps1`:
```powershell
n.CustomProperties.Site     AS Site,
n.CustomProperties.Location AS Location
```
Replace `Site` and `Location` with your actual custom property names.
---
Security Notes
Never commit the exported CSV — it contains your full network inventory. The `.gitignore` in this repo excludes `*.csv` files automatically.
SNMPv3 secrets are not exported — you must configure authentication keys and privacy keys manually in PRTG after import.
Run with least privilege — the export only needs read access to Orion. No write permissions required.
---
Contributing
Pull requests are welcome! If you add support for additional custom properties, new sensor mappings, or PRTG import functionality, please open a PR with a clear description of the changes.
---
License
MIT License — see LICENSE for details.
