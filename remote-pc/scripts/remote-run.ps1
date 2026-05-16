param(
    [Parameter(Mandatory, Position = 0)][string]$Target,
    [Parameter(Mandatory, Position = 1)][string]$Command,
    [int]$TimeoutSeconds = 120
)

. "$PSScriptRoot\RemotePc.Common.ps1"

$config = Get-RemotePcConfig
$device = Get-RemotePcDevice -Config $config -Name $Target

$sshOk = Test-RemotePcTcpPort -TargetHost $device.wireguardIp -Port 22
if (-not $sshOk) {
    throw "SSH port 22 is not reachable on $($device.wireguardIp). Configure Windows OpenSSH Server or use another remoting method."
}

$sshUser = if ([string]::IsNullOrWhiteSpace($device.sshUser)) { $device.smbUser } else { $device.sshUser }
if ([string]::IsNullOrWhiteSpace($sshUser)) {
    throw "No sshUser configured for $Target."
}

$keyPath = $null
if (-not [string]::IsNullOrWhiteSpace($device.sshKeyPath)) {
    $candidate = Resolve-RemotePcPath -Path $device.sshKeyPath
    if (Test-Path $candidate) {
        $keyPath = $candidate
    }
}

$encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($Command))
$remote = "powershell -NoProfile -ExecutionPolicy Bypass -EncodedCommand $encoded"

$sshArgs = @('-o', 'StrictHostKeyChecking=accept-new', '-o', "ConnectTimeout=$TimeoutSeconds")
if ($keyPath) {
    $sshArgs += @('-i', $keyPath)
}
$sshArgs += ("$sshUser@$($device.wireguardIp)")
$sshArgs += $remote

Write-RemotePcLog -Action 'run' -Message "target=$Target commandLength=$($Command.Length)"
& ssh @sshArgs
exit $LASTEXITCODE
