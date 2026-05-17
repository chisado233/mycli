Set-StrictMode -Version Latest

function Get-RemotePcProjectRoot {
    Split-Path -Parent $PSScriptRoot
}

function Get-RemotePcWorkspaceConfig {
    $root = Get-RemotePcProjectRoot
    $module = Join-Path (Split-Path -Parent $root) 'common\workspace-config.ps1'
    . $module
    Get-MyCliWorkspaceConfig -PackagePath 'remote-pc'
}

function Resolve-RemotePcPath {
    param([Parameter(Mandatory)][string]$Path)
    [Environment]::ExpandEnvironmentVariables($Path)
}

function Get-RemotePcConfig {
    $root = Get-RemotePcProjectRoot
    $workspaceConfig = Get-RemotePcWorkspaceConfig
    $configRoot = [string]$workspaceConfig.paths.config
    $devicesPath = Join-Path $configRoot 'devices.local.json'
    $mapsPath = Join-Path $configRoot 'drive-maps.local.json'

    if (-not (Test-Path $devicesPath)) {
        throw "Missing config: $devicesPath. Copy config\devices.example.json to devices.local.json first."
    }
    if (-not (Test-Path $mapsPath)) {
        throw "Missing config: $mapsPath. Copy config\drive-maps.example.json to drive-maps.local.json first."
    }

    [pscustomobject]@{
        Root = $root
        DevicesPath = $devicesPath
        MapsPath = $mapsPath
        Devices = Get-Content $devicesPath -Raw | ConvertFrom-Json
        DriveMaps = Get-Content $mapsPath -Raw | ConvertFrom-Json
    }
}

function Get-RemotePcDevice {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$Name
    )
    $device = $Config.Devices.devices.$Name
    if ($null -eq $device) {
        $known = ($Config.Devices.devices.PSObject.Properties.Name -join ', ')
        throw "Unknown device '$Name'. Known devices: $known"
    }
    $device
}

function Get-RemotePcLocalName {
    param([Parameter(Mandatory)]$Config)
    $name = $Config.Devices.localDevice
    if ([string]::IsNullOrWhiteSpace($name)) {
        throw "devices.local.json must set localDevice, e.g. 'A' or 'B'."
    }
    $name
}

function Get-RemotePcMapKey {
    param(
        [Parameter(Mandatory)][string]$LocalName,
        [Parameter(Mandatory)][string]$TargetName
    )
    "$LocalName->$TargetName"
}

function Get-RemotePcDriveMaps {
    param(
        [Parameter(Mandatory)]$Config,
        [Parameter(Mandatory)][string]$TargetName
    )
    $localName = Get-RemotePcLocalName -Config $Config
    $key = Get-RemotePcMapKey -LocalName $localName -TargetName $TargetName
    $maps = $Config.DriveMaps.maps.$key
    if ($null -eq $maps) {
        $known = ($Config.DriveMaps.maps.PSObject.Properties.Name -join ', ')
        throw "No drive map for '$key'. Known maps: $known"
    }
    @($maps)
}

function Write-RemotePcLog {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Message
    )
    $workspaceConfig = Get-RemotePcWorkspaceConfig
    $logDir = [string]$workspaceConfig.paths.logs
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }
    $logPath = Join-Path $logDir 'remote-pc.log'
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format o), $Action, $Message
    Add-Content -Path $logPath -Value $line -Encoding UTF8
}

function Test-RemotePcTcpPort {
    param(
        [Parameter(Mandatory)][string]$TargetHost,
        [Parameter(Mandatory)][int]$Port,
        [int]$TimeoutMs = 3000
    )
    try {
        $client = [System.Net.Sockets.TcpClient]::new()
        $async = $client.BeginConnect($TargetHost, $Port, $null, $null)
        if (-not $async.AsyncWaitHandle.WaitOne($TimeoutMs)) {
            $client.Close()
            return $false
        }
        $client.EndConnect($async)
        $client.Close()
        return $true
    } catch {
        return $false
    }
}

function Get-RemotePcUncPath {
    param(
        [Parameter(Mandatory)]$Device,
        [Parameter(Mandatory)]$Map
    )
    '\\{0}\{1}' -f $Device.wireguardIp, $Map.share
}

function Get-RemotePcDriveName {
    param([Parameter(Mandatory)]$Map)
    ($Map.localLetter.TrimEnd(':') + ':')
}
