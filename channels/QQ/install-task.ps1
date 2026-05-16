$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $Root "logs"
$StateDir = Join-Path $Root "state"
New-Item -ItemType Directory -Force $LogDir, $StateDir | Out-Null
$Qq = if ($args.Count -ge 1 -and -not [string]::IsNullOrWhiteSpace([string]$args[0])) { [string]$args[0] } else { "3279329186" }
$TaskRoot = "\QQChannel"
$BridgeTask = "QQChannel-Bridge"
$NapcatTask = "QQChannel-NapCat"
$BridgePs = Join-Path $Root "task-bridge-runner.ps1"
$NapcatPs = Join-Path $Root "task-napcat-runner.ps1"
$StateFile = Join-Path $StateDir "qq-channel-task.json"
$bridgeContent = @"
`$Root = '$Root'
Set-Location `$Root
`$env:CI = 'true'
node.exe (Join-Path `$Root 'qq-bridge.js') *>> (Join-Path `$Root 'logs\bridge.task.log')
"@
Set-Content -Path $BridgePs -Value $bridgeContent -Encoding UTF8
$napcatContent = @"
`$Root = '$Root'
`$Qq = '$Qq'
Set-Location (Join-Path `$Root 'napcat')
cmd.exe /c launcher-user.bat `$Qq *>> (Join-Path `$Root 'logs\napcat.task.log')
"@
Set-Content -Path $NapcatPs -Value $napcatContent -Encoding UTF8
function Ensure-TaskFolder($Path) {
  $service = New-Object -ComObject Schedule.Service
  $service.Connect()
  $rootFolder = $service.GetFolder("\")
  try { $rootFolder.GetFolder($Path.Trim('\')) | Out-Null } catch { $rootFolder.CreateFolder($Path.Trim('\')) | Out-Null }
}
function Register-OneTask($TaskName, $ScriptPath) {
  $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ScriptPath`"" -WorkingDirectory $Root
  $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddYears(5)
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -ExecutionTimeLimit ([TimeSpan]::Zero) -MultipleInstances IgnoreNew -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
  $principal = New-ScheduledTaskPrincipal -UserId $env:USERNAME -LogonType Interactive -RunLevel Limited
  Register-ScheduledTask -TaskPath $TaskRoot -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Force | Out-Null
}
Ensure-TaskFolder $TaskRoot
Register-OneTask $BridgeTask $BridgePs
Register-OneTask $NapcatTask $NapcatPs
@{ mode='task-scheduler'; taskPath=$TaskRoot; bridgeTask=$BridgeTask; napcatTask=$NapcatTask; qq=$Qq; root=$Root; updatedAt=(Get-Date).ToString('o') } | ConvertTo-Json -Depth 4 | Set-Content -Path $StateFile -Encoding UTF8
Write-Host "Registered Task Scheduler tasks: $TaskRoot\$BridgeTask and $TaskRoot\$NapcatTask"

