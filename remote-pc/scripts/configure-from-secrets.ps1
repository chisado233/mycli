param(
    [string]$SecretsPath,
    [ValidateSet('A', 'B')][string]$LocalDevice,
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ProjectRoot = Split-Path -Parent $PSScriptRoot

function Resolve-ProjectPath {
    param([Parameter(Mandatory)][string]$Path)
    if ([System.IO.Path]::IsPathRooted($Path)) { return [Environment]::ExpandEnvironmentVariables($Path) }
    return (Join-Path $ProjectRoot $Path)
}

function ConvertTo-PrettyJson {
    param([Parameter(Mandatory)]$Value)
    $Value | ConvertTo-Json -Depth 20
}

function Write-PrivateFile {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Content
    )
    $parent = Split-Path -Parent $Path
    if (-not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }
    if ((Test-Path -LiteralPath $Path) -and -not $Force) {
        Write-Host "Keeping existing private file: $Path"
        return
    }
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
    Write-Host "Wrote private file: $Path"
}

function Get-PropertyValue {
    param($Object, [Parameter(Mandatory)][string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    return $Default
}

if ([string]::IsNullOrWhiteSpace($SecretsPath)) {
    $SecretsPath = Join-Path $ProjectRoot 'config\secrets.local.json'
}
$SecretsPath = Resolve-ProjectPath -Path $SecretsPath
if (-not (Test-Path -LiteralPath $SecretsPath)) {
    throw "Missing secrets JSON: $SecretsPath. Copy config\secrets.local.example.json to config\secrets.local.json and fill it first."
}

$secrets = Get-Content -LiteralPath $SecretsPath -Raw | ConvertFrom-Json
if ([string]::IsNullOrWhiteSpace($LocalDevice)) {
    $LocalDevice = Get-PropertyValue -Object $secrets -Name 'localDevice' -Default 'A'
}
$LocalDevice = $LocalDevice.ToUpperInvariant()
if ($LocalDevice -notin @('A', 'B')) { throw "LocalDevice must be A or B, got: $LocalDevice" }

$server = $secrets.network.server
$devices = $secrets.devices
$local = $devices.$LocalDevice
if ($null -eq $local) { throw "secrets.devices.$LocalDevice is missing." }

$devicesConfig = [ordered]@{
    network = [ordered]@{
        cidr = $secrets.network.cidr
        server = [ordered]@{
            name = $server.name
            publicIp = $server.publicIp
            wireguardIp = $server.wireguardIp
            wireguardPort = [int]$server.wireguardPort
        }
    }
    localDevice = $LocalDevice
    devices = [ordered]@{}
}

foreach ($name in @('A', 'B')) {
    $device = $devices.$name
    if ($null -eq $device) { continue }
    $devicesConfig.devices[$name] = [ordered]@{
        name = $device.name
        os = $device.os
        wireguardIp = $device.wireguardIp
        smbUser = $device.smbUser
        sshUser = $device.sshUser
        sshKeyPath = $device.sshKeyPath
        remoteShell = $device.remoteShell
    }
}

$mapsObject = [ordered]@{ maps = [ordered]@{} }
foreach ($mapProperty in $secrets.driveMaps.PSObject.Properties) {
    $mapsObject.maps[$mapProperty.Name] = @($mapProperty.Value)
}

Write-PrivateFile -Path (Join-Path $ProjectRoot 'config\devices.local.json') -Content (ConvertTo-PrettyJson -Value $devicesConfig)
Write-PrivateFile -Path (Join-Path $ProjectRoot 'config\drive-maps.local.json') -Content (ConvertTo-PrettyJson -Value $mapsObject)

$serverPublicKey = Get-PropertyValue -Object $server -Name 'publicKey'
if ([string]::IsNullOrWhiteSpace($serverPublicKey) -or $serverPublicKey -like '<*') {
    Write-Warning 'Server public key is missing or still a placeholder. WireGuard config was generated but must be completed before use.'
}
$privateKey = Get-PropertyValue -Object $local -Name 'wireguardPrivateKey'
if ([string]::IsNullOrWhiteSpace($privateKey) -or $privateKey -like '<*') {
    Write-Warning "$LocalDevice WireGuard private key is missing or still a placeholder. WireGuard config was generated but must be completed before use."
}
$address = Get-PropertyValue -Object $local -Name 'wireguardAddress' -Default "$($local.wireguardIp)/32"
$endpoint = "{0}:{1}" -f $server.publicIp, $server.wireguardPort
$wgConfig = @"
[Interface]
# $LocalDevice computer / generated from config/secrets.local.json
Address = $address
PrivateKey = $privateKey
DNS = 223.5.5.5

[Peer]
PublicKey = $serverPublicKey
Endpoint = $endpoint
AllowedIPs = $($secrets.network.cidr)
PersistentKeepalive = 25
"@
$clientConfigName = ('client-{0}.local.conf' -f $LocalDevice.ToLowerInvariant())
Write-PrivateFile -Path (Join-Path $ProjectRoot "wireguard\$clientConfigName") -Content $wgConfig.TrimEnd()

foreach ($name in @('A', 'B')) {
    $device = $devices.$name
    if ($null -eq $device) { continue }
    $privateKeyText = Get-PropertyValue -Object $device -Name 'sshPrivateKey'
    if (-not [string]::IsNullOrWhiteSpace($privateKeyText)) {
        $keyPathValue = Get-PropertyValue -Object $device -Name 'sshKeyPath'
        if (-not [string]::IsNullOrWhiteSpace($keyPathValue)) {
            Write-PrivateFile -Path ([Environment]::ExpandEnvironmentVariables($keyPathValue)) -Content $privateKeyText.TrimEnd()
        }
    }
}

$relayPrivateKey = Get-PropertyValue -Object $secrets.relay -Name 'sshPrivateKey'
if (-not [string]::IsNullOrWhiteSpace($relayPrivateKey)) {
    $relayKeyPath = Get-PropertyValue -Object $secrets.relay -Name 'sshPrivateKeyPath'
    if (-not [string]::IsNullOrWhiteSpace($relayKeyPath)) {
        Write-PrivateFile -Path ([Environment]::ExpandEnvironmentVariables($relayKeyPath)) -Content $relayPrivateKey.TrimEnd()
    }
}

$commandHost = Get-PropertyValue -Object $secrets.commandServer -Name 'host' -Default 'auto'
if ([string]::IsNullOrWhiteSpace($commandHost) -or $commandHost -eq 'auto') {
    $commandHost = $local.wireguardIp
}
$envLines = @(
    "REMOTE_PC_RELAY_HOST=$($secrets.relay.host)",
    "REMOTE_PC_RELAY_USER=$($secrets.relay.sshUser)",
    "REMOTE_PC_RELAY_KEY=$([Environment]::ExpandEnvironmentVariables($secrets.relay.sshPrivateKeyPath))",
    "REMOTE_PC_RELAY_PLINK=$([Environment]::ExpandEnvironmentVariables($secrets.relay.plinkPath))",
    "REMOTE_PC_RELAY_HOSTKEY=$($secrets.relay.hostKey)",
    "REMOTE_PC_COMMAND_HOST=$commandHost",
    "REMOTE_PC_COMMAND_PORT=$($secrets.commandServer.port)",
    "REMOTE_PC_COMMAND_ALLOWED_CLIENT=$($secrets.commandServer.allowedClient)",
    "REMOTE_PC_COMMAND_CWD=$($secrets.commandServer.cwd)",
    "REMOTE_PC_COMMAND_TIMEOUT=$($secrets.commandServer.timeoutSeconds)",
    "REMOTE_PC_COMMAND_TOKEN=$($secrets.commandServer.token)"
)
Write-PrivateFile -Path (Join-Path $ProjectRoot 'config\relay.env.local') -Content ($envLines -join [Environment]::NewLine)

Write-Host ''
Write-Host 'Generated local runtime config from secrets JSON.'
[pscustomobject]@{
    LocalDevice = $LocalDevice
    DevicesConfig = Join-Path $ProjectRoot 'config\devices.local.json'
    DriveMapsConfig = Join-Path $ProjectRoot 'config\drive-maps.local.json'
    WireGuardConfig = Join-Path $ProjectRoot "wireguard\$clientConfigName"
    RelayEnv = Join-Path $ProjectRoot 'config\relay.env.local'
} | Format-List
