param(
    [Parameter(Mandatory, Position = 0)][string]$Target
)

. "$PSScriptRoot\RemotePc.Common.ps1"

Write-Host "Repairing mappings for $Target..."
& "$PSScriptRoot\remote-disconnect.ps1" $Target
& "$PSScriptRoot\remote-connect.ps1" $Target -Force
& "$PSScriptRoot\remote-status.ps1" $Target

Write-RemotePcLog -Action 'repair' -Message "target=$Target"
