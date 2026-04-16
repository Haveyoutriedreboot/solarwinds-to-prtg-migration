# -----------------------------
# SolarWinds → Inventory Export
# -----------------------------
# Requires: Install-Module -Name SwisPowerShell (run as admin once)
# Docs: https://github.com/solarwinds/OrionSDK/wiki/PowerShell
# -----------------------------

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SwHost,

    [Parameter(Mandatory = $false)]
    [PSCredential]$Credential = $null,

    [Parameter(Mandatory = $false)]
    [string]$OutputPath = $null
)

# ----- SETUP -----
Import-Module SwisPowerShell -ErrorAction Stop

# Resolve output path — default to script directory
if (-not $OutputPath) {
    $OutputPath = Join-Path $PSScriptRoot "solarwinds_nodes_for_prtg.csv"
}

# ----- CONNECTION -----
try {
    Write-Host "Connecting to SolarWinds Orion at '$SwHost'..." -ForegroundColor Cyan
    $swis = if ($Credential) {
        Connect-Swis -Hostname $SwHost -Credential $Credential
    } else {
        # -Trusted uses Windows auth; only works when running ON the Orion server
        Write-Warning "No credential provided — using -Trusted (Windows auth). Run this on the Orion server or pass -Credential."
        Connect-Swis -Hostname $SwHost -Trusted
    }
    Write-Host "Connected." -ForegroundColor Green
}
catch {
    Write-Error "Failed to connect to SolarWinds: $_"
    exit 1
}

# ----- QUERIES -----

# Nodes with key fields & selected custom properties
$nodesQuery = @"
SELECT
  n.NodeID,
  n.Caption,
  n.IPAddress,
  n.DNS,
  n.SysName,
  n.Vendor,
  n.MachineType,
  n.Description,
  n.ObjectSubType,
  n.SNMPVersion
FROM Orion.Nodes AS n
"@

# NOTE: SolarWinds SWQL may truncate results on very large deployments (10,000+ nodes).
# If you suspect truncation, consider paginating with TOP/OFFSET or splitting by Site/Location.
Write-Warning "If you have 10,000+ nodes, SWQL results may be truncated. Consider paginating the query."

try {
    Write-Host "Querying nodes..." -ForegroundColor Cyan
    $nodes = Get-SwisData $swis $nodesQuery
    Write-Host "Retrieved $($nodes.Count) nodes." -ForegroundColor Green
}
catch {
    Write-Error "Failed to retrieve nodes: $_"
    exit 1
}

# Pollers assigned per node (monitoring profile hints)
$pollersQuery = @"
SELECT
  p.NetObjectID AS NodeID,
  p.PollerType
FROM Orion.Pollers p
WHERE p.NetObjectType = 'N'
"@

try {
    Write-Host "Querying pollers..." -ForegroundColor Cyan
    $pollers = Get-SwisData $swis $pollersQuery |
        Group-Object NodeID -AsHashTable -AsString
    Write-Host "Retrieved poller assignments." -ForegroundColor Green
}
catch {
    Write-Warning "Could not retrieve pollers (non-fatal): $_"
    $pollers = @{}
}

# Custom properties — adjust CP names to match your environment
$customPropsQuery = @"
SELECT
  n.NodeID,
  n.CustomProperties.Site     AS Site,
  n.CustomProperties.Location AS Location
FROM Orion.Nodes AS n
"@

try {
    Write-Host "Querying custom properties..." -ForegroundColor Cyan
    $customProps = Get-SwisData $swis $customPropsQuery |
        Group-Object NodeID -AsHashTable -AsString
    Write-Host "Retrieved custom properties." -ForegroundColor Green
}
catch {
    Write-Warning "Could not retrieve custom properties (non-fatal): $_"
    $customProps = @{}
}

# SNMPv3 metadata — non-secret fields only (keys/passwords are protected by Orion)
$snmpv3Query = @"
SELECT NodeID, Username, AuthenticationMethod, PrivacyMethod
FROM Orion.SNMPv3Credentials
"@

try {
    Write-Host "Querying SNMPv3 credentials metadata..." -ForegroundColor Cyan
    $snmpv3 = Get-SwisData $swis $snmpv3Query |
        Group-Object NodeID -AsHashTable -AsString
    Write-Host "Retrieved SNMPv3 metadata." -ForegroundColor Green
}
catch {
    Write-Warning "Could not retrieve SNMPv3 metadata (non-fatal — may not be configured): $_"
    $snmpv3 = @{}
}

# ----- MONITORING PROFILE HELPER -----
# Maps SolarWinds pollers to a high-level monitoring method + PRTG sensor starter hints
function Get-MonitoringProfile {
    param(
        [string[]]$PollerTypes  = @(),
        [string]  $ObjectSubType,
        [int]     $SnmpVersion
    )

    $hints = [System.Collections.Generic.List[string]]::new()

    if ($PollerTypes -match 'N\.Status\.ICMP\.Native' -or
        $PollerTypes -match 'N\.ResponseTime\.ICMP\.Native') {
        $hints.Add("Ping")
    }
    if ($PollerTypes -match 'SNMP') {
        $hints.Add("SNMP Generic/Traffic/CPU/Memory")
    }
    if ($PollerTypes -match 'N\.Cpu\.SNMP' -or $PollerTypes -match 'N\.Memory\.SNMP') {
        $hints.Add("SNMP CPU/Memory (vendor-specific possible)")
    }
    if ($ObjectSubType -eq 'WMI') {
        $hints.Add("WMI Windows (CPU/Memory/Disk/Services)")
    }
    if ($ObjectSubType -eq 'Agent') {
        $hints.Add("Agent-based in SolarWinds (map to WMI/SNMP/Script in PRTG)")
    }

    $method = switch ($ObjectSubType) {
        'SNMP'  { if ($SnmpVersion -eq 3) { 'SNMPv3' } else { 'SNMPv2c' } }
        'WMI'   { 'WMI' }
        'Agent' { 'Agent' }
        'ICMP'  { 'ICMP' }
        default { $ObjectSubType }
    }

    [PSCustomObject]@{
        Method      = $method
        SensorHints = ($hints | Select-Object -Unique) -join '; '
    }
}

# ----- BUILD EXPORT ROWS -----
Write-Host "Building export rows..." -ForegroundColor Cyan

$export = foreach ($n in $nodes) {

    # Resolve pollers for this node
    $pl = @()
    if ($pollers.ContainsKey([string]$n.NodeID)) {
        $pl = @($pollers[[string]$n.NodeID]) | ForEach-Object { $_.PollerType }
    }

    $profile = Get-MonitoringProfile `
        -PollerTypes   $pl `
        -ObjectSubType $n.ObjectSubType `
        -SnmpVersion   $n.SNMPVersion

    # Resolve custom properties
    $cp = $null
    if ($customProps.ContainsKey([string]$n.NodeID)) {
        $cp = $customProps[[string]$n.NodeID] | Select-Object -First 1
    }

    # Resolve SNMPv3 metadata
    $v3 = $null
    if ($snmpv3.ContainsKey([string]$n.NodeID)) {
        $v3 = $snmpv3[[string]$n.NodeID] | Select-Object -First 1
    }

    # PS 5.1-compatible null-conditional (avoids ?. operator requiring PS 7+)
    [PSCustomObject]@{
        NodeID        = $n.NodeID
        Name          = $n.Caption
        IP            = $n.IPAddress
        DNS           = $n.DNS
        SysName       = $n.SysName
        Vendor        = $n.Vendor
        Model         = $n.MachineType
        Description   = $n.Description
        Site          = if ($cp)  { $cp.Site }                    else { $null }
        Location      = if ($cp)  { $cp.Location }                else { $null }
        PollingMethod = $profile.Method
        SensorHints   = $profile.SensorHints
        SNMPVersion   = $n.SNMPVersion
        SNMPv3User    = if ($v3)  { $v3.Username }                else { $null }
        SNMPv3Auth    = if ($v3)  { $v3.AuthenticationMethod }    else { $null }
        SNMPv3Priv    = if ($v3)  { $v3.PrivacyMethod }           else { $null }
    }
}

# ----- EXPORT -----
try {
    $export | Export-Csv -NoTypeInformation -Encoding UTF8 -Path $OutputPath
    Write-Host "Exported $($export.Count) nodes to: $OutputPath" -ForegroundColor Green
}
catch {
    Write-Error "Failed to write CSV: $_"
    exit 1
}
