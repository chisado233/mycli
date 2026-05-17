param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$InputArgs
)

$ErrorActionPreference = 'Stop'

$PackageRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$WorkspaceConfigModule = Join-Path (Split-Path -Parent $PackageRoot) 'common\workspace-config.ps1'
. $WorkspaceConfigModule
$WorkspaceConfig = Get-MyCliWorkspaceConfig -PackagePath 'startup'
$StateRoot = [string]$WorkspaceConfig.paths.var
$LogRoot = [string]$WorkspaceConfig.paths.logs
$RegistryPath = Join-Path ([string]$WorkspaceConfig.paths.config) 'startup-commands.json'
$RunnerPath = Join-Path (Join-Path $PackageRoot 'scripts') 'startup.ps1'
$TaskPath = '\mycli\startup\'
$TaskName = 'RunRegisteredCommands'

function Show-Usage {
  @"
mycli startup

Usage:
  startup --help
  startup list [--json]
  startup add <id> <command...>
  startup remove <id>
  startup enable <id>
  startup disable <id>
  startup install
  startup uninstall
  startup run
  startup status [--json]

State:
  registry: $RegistryPath
  logs:     $LogRoot
  task:     $TaskPath$TaskName

Notes:
  'add' stores the command and installs/updates the Windows AtLogOn scheduled task.
  'run' launches all enabled registered commands asynchronously and writes logs per command.
"@
}

function Ensure-StateRoot {
  if (-not (Test-Path -LiteralPath $StateRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $StateRoot -Force | Out-Null
  }
  if (-not (Test-Path -LiteralPath $LogRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null
  }
}

function New-EmptyRegistry {
  [pscustomobject]@{
    version = 1
    updatedAt = (Get-Date).ToString('o')
    commands = @()
  }
}

function Read-Registry {
  Ensure-StateRoot
  if (-not (Test-Path -LiteralPath $RegistryPath -PathType Leaf)) {
    return New-EmptyRegistry
  }

  $raw = Get-Content -LiteralPath $RegistryPath -Raw -Encoding UTF8
  if ([string]::IsNullOrWhiteSpace($raw)) {
    return New-EmptyRegistry
  }

  $registry = $raw | ConvertFrom-Json
  if ($null -eq $registry.PSObject.Properties['commands']) {
    $registry | Add-Member -NotePropertyName commands -NotePropertyValue @()
  }
  if ($null -eq $registry.PSObject.Properties['version']) {
    $registry | Add-Member -NotePropertyName version -NotePropertyValue 1
  }
  return $registry
}

function Write-Registry {
  param([Parameter(Mandatory = $true)]$Registry)
  Ensure-StateRoot
  if ($null -eq $Registry.PSObject.Properties['updatedAt']) {
    $Registry | Add-Member -NotePropertyName updatedAt -NotePropertyValue ''
  }
  $Registry.updatedAt = (Get-Date).ToString('o')
  $Registry | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $RegistryPath -Encoding UTF8
}

function Get-CommandRecords {
  param([Parameter(Mandatory = $true)]$Registry)
  return @($Registry.commands)
}

function Test-ValidId {
  param([Parameter(Mandatory = $true)][string]$Id)
  return $Id -match '^[A-Za-z0-9_.-]+$'
}

function Get-TaskInfo {
  try {
    return Get-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -ErrorAction Stop
  } catch {
    return $null
  }
}

function Install-StartupTask {
  Ensure-StateRoot
  $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
  if ([string]::IsNullOrWhiteSpace($pwsh)) {
    $pwsh = (Get-Command powershell -ErrorAction Stop).Source
  }

  $argument = "-NoProfile -ExecutionPolicy Bypass -File `"$RunnerPath`" run"
  $action = New-ScheduledTaskAction -Execute $pwsh -Argument $argument -WorkingDirectory 'D:\agent_workspace'
  $trigger = New-ScheduledTaskTrigger -AtLogOn -User $env:USERNAME
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances Parallel -StartWhenAvailable

  Register-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description 'Run registered mycli startup commands at Windows sign-in.' -Force | Out-Null
  Write-Output "Installed scheduled task: $TaskPath$TaskName"
}

function Uninstall-StartupTask {
  $task = Get-TaskInfo
  if ($null -eq $task) {
    Write-Output "Scheduled task not installed: $TaskPath$TaskName"
    return
  }
  Unregister-ScheduledTask -TaskPath $TaskPath -TaskName $TaskName -Confirm:$false
  Write-Output "Uninstalled scheduled task: $TaskPath$TaskName"
}

function Write-Records {
  param(
    $Records,
    [Parameter(Mandatory = $true)][bool]$AsJson
  )

  $recordList = New-Object System.Collections.ArrayList
  if ($null -ne $Records) {
    foreach ($record in @($Records)) {
      if ($null -ne $record) {
        [void]$recordList.Add($record)
      }
    }
  }
  if ($AsJson) {
    $recordList | ConvertTo-Json -Depth 10
    return
  }
  if ($recordList.Count -eq 0) {
    Write-Output 'No startup commands registered.'
    return
  }
  $recordList | Select-Object id, enabled, command, updatedAt | Format-Table -AutoSize
}

function Add-StartupCommand {
  param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][string[]]$Command
  )

  if (-not (Test-ValidId -Id $Id)) {
    throw "Invalid id '$Id'. Use only letters, numbers, underscore, dash, and dot."
  }
  if ($Command.Count -eq 0) {
    throw 'add requires a command to register.'
  }

  $registry = Read-Registry
  $records = New-Object System.Collections.ArrayList
  foreach ($record in (Get-CommandRecords -Registry $registry)) {
    if ($record.id -ne $Id) {
      [void]$records.Add($record)
    }
  }

  $now = (Get-Date).ToString('o')
  [void]$records.Add([pscustomobject]@{
    id = $Id
    enabled = $true
    command = @($Command)
    createdAt = $now
    updatedAt = $now
  })

  $registry.commands = @($records)
  Write-Registry -Registry $registry
  Install-StartupTask
  Write-Output "Registered startup command: $Id"
}

function Remove-StartupCommand {
  param([Parameter(Mandatory = $true)][string]$Id)
  $registry = Read-Registry
  $records = @((Get-CommandRecords -Registry $registry) | Where-Object { $_.id -ne $Id })
  if ($records.Count -eq (Get-CommandRecords -Registry $registry).Count) {
    throw "Startup command not found: $Id"
  }
  $registry.commands = @($records)
  Write-Registry -Registry $registry
  Write-Output "Removed startup command: $Id"
}

function Set-StartupCommandEnabled {
  param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][bool]$Enabled
  )
  $registry = Read-Registry
  $found = $false
  foreach ($record in (Get-CommandRecords -Registry $registry)) {
    if ($record.id -eq $Id) {
      $record.enabled = $Enabled
      $record.updatedAt = (Get-Date).ToString('o')
      $found = $true
    }
  }
  if (-not $found) {
    throw "Startup command not found: $Id"
  }
  Write-Registry -Registry $registry
  $state = if ($Enabled) { 'Enabled' } else { 'Disabled' }
  Write-Output "$state startup command: $Id"
}

function Start-RegisteredCommands {
  Ensure-StateRoot
  $registry = Read-Registry
  $records = @((Get-CommandRecords -Registry $registry) | Where-Object { $_.enabled -eq $true })
  if ($records.Count -eq 0) {
    Write-Output 'No enabled startup commands to run.'
    return
  }

  foreach ($record in $records) {
    $commandParts = @($record.command)
    if ($commandParts.Count -eq 0) {
      Write-Warning "Skipping '$($record.id)': empty command."
      continue
    }

    $safeId = ($record.id -replace '[^A-Za-z0-9_.-]', '_')
    $timestamp = Get-Date -Format 'yyyyMMdd-HHmmss'
    $stdout = Join-Path $LogRoot "$timestamp-$safeId.out.log"
    $stderr = Join-Path $LogRoot "$timestamp-$safeId.err.log"
    $exe = $commandParts[0]
    $args = @()
    if ($commandParts.Count -gt 1) {
      $args = @($commandParts[1..($commandParts.Count - 1)])
    }

    try {
      $actualExe = $exe
      $actualArgs = @($args)
      if ($exe -match '\.ps1$') {
        $pwsh = (Get-Command pwsh -ErrorAction SilentlyContinue).Source
        if ([string]::IsNullOrWhiteSpace($pwsh)) {
          $pwsh = (Get-Command powershell -ErrorAction Stop).Source
        }
        $actualExe = $pwsh
        $actualArgs = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $exe) + @($args)
      }

      Start-Process -FilePath $actualExe -ArgumentList $actualArgs -WorkingDirectory 'D:\agent_workspace' -WindowStyle Hidden -RedirectStandardOutput $stdout -RedirectStandardError $stderr | Out-Null
      Write-Output "Started startup command '$($record.id)'. Logs: $stdout ; $stderr"
    } catch {
      $message = "Failed startup command '$($record.id)': $($_.Exception.Message)"
      $message | Set-Content -LiteralPath $stderr -Encoding UTF8
      Write-Warning $message
      continue
    }
  }
}

function Show-Status {
  param([Parameter(Mandatory = $true)][bool]$AsJson)
  $registry = Read-Registry
  $task = Get-TaskInfo
  $status = [pscustomobject]@{
    registryPath = $RegistryPath
    logRoot = $LogRoot
    commandCount = @($registry.commands).Count
    enabledCount = @($registry.commands | Where-Object { $_.enabled -eq $true }).Count
    scheduledTask = [pscustomobject]@{
      path = $TaskPath
      name = $TaskName
      installed = ($null -ne $task)
      state = if ($null -ne $task) { [string]$task.State } else { $null }
    }
  }

  if ($AsJson) {
    $status | ConvertTo-Json -Depth 10
    return
  }

  Write-Output "Registry: $($status.registryPath)"
  Write-Output "Logs: $($status.logRoot)"
  Write-Output "Commands: $($status.commandCount) total, $($status.enabledCount) enabled"
  Write-Output "Scheduled task: $TaskPath$TaskName"
  Write-Output "Installed: $($status.scheduledTask.installed)"
  if ($status.scheduledTask.installed) {
    Write-Output "State: $($status.scheduledTask.state)"
  }
}

$command = 'list'
$remaining = @()
if ($InputArgs -and $InputArgs.Count -gt 0) {
  $command = $InputArgs[0]
  if ($InputArgs.Count -gt 1) {
    $remaining = @($InputArgs[1..($InputArgs.Count - 1)])
  }
}

$asJson = $remaining -contains '--json'
$remaining = @($remaining | Where-Object { $_ -ne '--json' })

switch ($command) {
  { $_ -in @('--help', '-h', 'help') } {
    Show-Usage
    exit 0
  }
  'list' {
    $registry = Read-Registry
    Write-Records -Records (Get-CommandRecords -Registry $registry) -AsJson $asJson
    exit 0
  }
  'add' {
    if ($remaining.Count -lt 2) {
      throw 'add requires <id> <command...>.'
    }
    Add-StartupCommand -Id $remaining[0] -Command @($remaining[1..($remaining.Count - 1)])
    exit 0
  }
  'remove' {
    if ($remaining.Count -ne 1) { throw 'remove requires <id>.' }
    Remove-StartupCommand -Id $remaining[0]
    exit 0
  }
  'enable' {
    if ($remaining.Count -ne 1) { throw 'enable requires <id>.' }
    Set-StartupCommandEnabled -Id $remaining[0] -Enabled $true
    exit 0
  }
  'disable' {
    if ($remaining.Count -ne 1) { throw 'disable requires <id>.' }
    Set-StartupCommandEnabled -Id $remaining[0] -Enabled $false
    exit 0
  }
  'install' {
    Install-StartupTask
    exit 0
  }
  'uninstall' {
    Uninstall-StartupTask
    exit 0
  }
  'run' {
    Start-RegisteredCommands
    exit 0
  }
  'status' {
    Show-Status -AsJson $asJson
    exit 0
  }
  default {
    Write-Error "Unknown command: $command"
    Show-Usage
    exit 1
  }
}
