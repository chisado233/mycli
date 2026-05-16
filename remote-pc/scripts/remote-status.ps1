param(
    [Parameter(Mandatory, Position = 0)][string]$Target
)

. "$PSScriptRoot\RemotePc.Common.ps1"

$config = Get-RemotePcConfig
$device = Get-RemotePcDevice -Config $config -Name $Target
$maps = Get-RemotePcDriveMaps -Config $config -TargetName $Target

Write-Host "Target: $Target"
Write-Host "WireGuard IP: $($device.wireguardIp)"

$pingOk = Test-Connection -ComputerName $device.wireguardIp -Count 1 -Quiet -ErrorAction SilentlyContinue
Write-Host ("Ping: {0}" -f ($(if ($pingOk) { 'OK' } else { 'FAIL' })))

$smbOk = Test-RemotePcTcpPort -TargetHost $device.wireguardIp -Port 445
Write-Host ("SMB 445: {0}" -f ($(if ($smbOk) { 'OK' } else { 'FAIL' })))

$sshOk = Test-RemotePcTcpPort -TargetHost $device.wireguardIp -Port 22
Write-Host ("SSH 22: {0}" -f ($(if ($sshOk) { 'OK' } else { 'FAIL/disabled' })))

Write-Host "Drive maps:"
foreach ($map in $maps) {
    $drive = Get-RemotePcDriveName -Map $map
    $unc = Get-RemotePcUncPath -Device $device -Map $map
    $exists = Test-Path $drive
    $readable = $false
    if ($exists) {
        try {
            Get-ChildItem $drive -ErrorAction Stop | Select-Object -First 1 | Out-Null
            $readable = $true
        } catch {
            $readable = $false
        }
    }
    Write-Host ("  {0} -> {1} | exists={2} readable={3}" -f $drive, $unc, $exists, $readable)
}

Write-RemotePcLog -Action 'status' -Message "target=$Target ping=$pingOk smb=$smbOk ssh=$sshOk"
