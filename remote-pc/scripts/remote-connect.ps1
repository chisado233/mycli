param(
    [Parameter(Mandatory, Position = 0)][string]$Target,
    [switch]$Force,
    [switch]$NoPersistent
)

. "$PSScriptRoot\RemotePc.Common.ps1"

$config = Get-RemotePcConfig
$device = Get-RemotePcDevice -Config $config -Name $Target
$maps = Get-RemotePcDriveMaps -Config $config -TargetName $Target

Write-Host "Connecting to $Target ($($device.wireguardIp))..."

$pingOk = Test-Connection -ComputerName $device.wireguardIp -Count 1 -Quiet -ErrorAction SilentlyContinue
$sshOk = Test-RemotePcTcpPort -TargetHost $device.wireguardIp -Port 22

Write-Host ("Ping: {0}" -f ($(if ($pingOk) { 'OK' } else { 'FAIL' })))

$smbOk = Test-RemotePcTcpPort -TargetHost $device.wireguardIp -Port 445
if (-not $smbOk) {
    if ($pingOk -or $sshOk) {
        throw "SMB port 445 is not reachable on $($device.wireguardIp). Host is partially reachable, but Windows file sharing is unavailable. Check firewall, admin shares, and antivirus interception."
    }
    throw "Target $Target is not reachable enough for SMB mapping at $($device.wireguardIp). Ping, SMB 445, and SSH 22 all failed. Check WireGuard first."
}

Write-Host ("SMB 445: {0}" -f ($(if ($smbOk) { 'OK' } else { 'FAIL' })))
Write-Host ("SSH 22: {0}" -f ($(if ($sshOk) { 'OK' } else { 'FAIL/disabled' })))

$persistent = if ($NoPersistent) { '/persistent:no' } else { '/persistent:yes' }
$mapped = @()

foreach ($map in $maps) {
    $drive = Get-RemotePcDriveName -Map $map
    $unc = Get-RemotePcUncPath -Device $device -Map $map
    $driveNoColon = $drive.TrimEnd(':')

    if (Test-Path $drive) {
        if ($Force) {
            Write-Host "Removing existing mapping $drive"
            & net use $drive /delete /y | Out-Null
        } else {
            Write-Host "Already exists: $drive. Use -Force to remap."
            $mapped += [pscustomobject]@{ Drive = $drive; UNC = $unc; Status = 'exists' }
            continue
        }
    }

    Write-Host "Mapping $drive -> $unc"
    $userArgs = @()
    if (-not [string]::IsNullOrWhiteSpace($device.smbUser)) {
        $userArgs = @("/user:$($device.smbUser)", '*')
    }

    & net use $drive $unc @userArgs $persistent
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to map $drive -> $unc. net use exit code: $LASTEXITCODE"
    }

    $mapped += [pscustomobject]@{ Drive = $drive; UNC = $unc; Status = 'mapped' }
}

Write-Host "Ready. You can use mapped drives directly:"
$mapped | ForEach-Object { Write-Host ("  {0} -> {1} ({2})" -f $_.Drive, $_.UNC, $_.Status) }

Write-RemotePcLog -Action 'connect' -Message "target=$Target maps=$($mapped.Count)"
