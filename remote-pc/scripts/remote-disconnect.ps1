param(
    [Parameter(Mandatory, Position = 0)][string]$Target
)

. "$PSScriptRoot\RemotePc.Common.ps1"

$config = Get-RemotePcConfig
$null = Get-RemotePcDevice -Config $config -Name $Target
$maps = Get-RemotePcDriveMaps -Config $config -TargetName $Target

foreach ($map in $maps) {
    $drive = Get-RemotePcDriveName -Map $map
    if (Test-Path $drive) {
        Write-Host "Removing $drive"
        & net use $drive /delete /y
    } else {
        Write-Host "Not mapped: $drive"
    }
}

Write-RemotePcLog -Action 'disconnect' -Message "target=$Target"
