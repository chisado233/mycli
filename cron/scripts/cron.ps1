[CmdletBinding()]
param(
  [Parameter(ValueFromRemainingArguments = $true)]
  [string[]]$InputArgs
)

if ($null -eq $InputArgs) { $InputArgs = @() }
else { $InputArgs = @($InputArgs) }

$ErrorActionPreference = 'Stop'
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$PackageRoot = Split-Path -Parent (Split-Path -Parent $PSCommandPath)
$TaskRoot = Join-Path $PackageRoot 'tasks'
$PersistentRoot = Join-Path $TaskRoot 'persistent'
$TempRoot = Join-Path $TaskRoot 'temp'
$SchedulerTaskPath = '\mycli\cron\'
$RunnerPath = $PSCommandPath
$WorkspaceRoot = 'D:\agent_workspace'

function Show-Usage {
@"
mycli cron

Usage:
  cron task-list [--json]
  cron add-command <id> (--once <datetime> | --every <delay> | --daily <HH:mm> | --weekly <days> <HH:mm>) [--persistent|--temp] [--missed skip|catch-up] [--random-delay <delay>] -- <command...>
  cron add-script <id> (--once <datetime> | --every <delay> | --daily <HH:mm> | --weekly <days> <HH:mm>) [--persistent|--temp] --script <path> [--copy-script] [-- <script args...>]
  cron show <id>
  cron logs <id> [--last <n>]
  cron run <id>
  cron enable <id>
  cron disable <id>
  cron delete <id>
  cron status

Schedule forms:
  --once "2026-05-16 18:30"     one-time task, defaults to temp
  --every 30m                   repeated interval
  --daily 09:00                 daily schedule
  --weekly Mon,Wed,Fri 09:00    weekly schedule

Missed-run policy:
  --missed skip                 default; do not compensate missed starts
  --missed catch-up             use StartWhenAvailable
  --random-delay 30m            spread runs to avoid boot-time pileups

State:
  persistent: $PersistentRoot
  temp:       $TempRoot
  scheduler:  $SchedulerTaskPath
"@
}

function Ensure-Roots {
  foreach ($path in @($TaskRoot, $PersistentRoot, $TempRoot)) {
    if (-not (Test-Path -LiteralPath $path -PathType Container)) {
      New-Item -ItemType Directory -Path $path -Force | Out-Null
    }
  }
}

function Test-ValidId { param([string]$Id) return ($Id -match '^[A-Za-z0-9_.-]+$') }

function ConvertTo-SafeTaskName {
  param([string]$Id)
  $safe = ($Id.ToLowerInvariant() -replace '[^a-z0-9_.-]+', '-')
  $safe = $safe.Trim('-')
  if ([string]::IsNullOrWhiteSpace($safe)) { $safe = 'task' }
  if ($safe.Length -gt 80) { $safe = $safe.Substring(0, 80).Trim('-') }
  return "mycli-cron-$safe"
}

function ConvertTo-HashtableDeep {
  param([object]$InputObject)
  if ($null -eq $InputObject) { return $null }
  if ($InputObject -is [string] -or $InputObject -is [char] -or $InputObject -is [bool] -or $InputObject -is [byte] -or $InputObject -is [int] -or $InputObject -is [long] -or $InputObject -is [double] -or $InputObject -is [decimal] -or $InputObject -is [datetime]) { return $InputObject }
  if ($InputObject -is [System.Collections.IDictionary]) {
    $result = @{}
    foreach ($key in $InputObject.Keys) { $result[[string]$key] = ConvertTo-HashtableDeep -InputObject $InputObject[$key] }
    return $result
  }
  if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
    $items = @()
    foreach ($item in $InputObject) { $items += ,(ConvertTo-HashtableDeep -InputObject $item) }
    return $items
  }
  $properties = @($InputObject.PSObject.Properties)
  if ($properties.Count -gt 0) {
    $result = @{}
    foreach ($prop in $properties) { $result[$prop.Name] = ConvertTo-HashtableDeep -InputObject $prop.Value }
    return $result
  }
  return $InputObject
}

function Read-JsonFile {
  param([string]$Path)
  return ConvertTo-HashtableDeep -InputObject ((Get-Content -LiteralPath $Path -Raw -Encoding UTF8) | ConvertFrom-Json)
}

function Write-JsonFile {
  param([string]$Path, [object]$Value)
  $Value | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding UTF8
}

function ConvertFrom-DelayText {
  param([string]$Value)
  if ([string]::IsNullOrWhiteSpace($Value)) { throw 'Delay value cannot be empty.' }
  if ($Value -match '^\s*(?<number>\d+)\s*(?<unit>s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)?\s*$') {
    $number = [int]$matches['number']
    $unit = if ($matches.ContainsKey('unit') -and -not [string]::IsNullOrWhiteSpace($matches['unit'])) { [string]$matches['unit'] } else { 'm' }
    switch -Regex ($unit.ToLowerInvariant()) {
      '^(s|sec|secs|second|seconds)$' { return (New-TimeSpan -Seconds $number) }
      '^(m|min|mins|minute|minutes)$' { return (New-TimeSpan -Minutes $number) }
      '^(h|hr|hrs|hour|hours)$' { return (New-TimeSpan -Hours $number) }
      '^(d|day|days)$' { return (New-TimeSpan -Days $number) }
    }
  }
  throw "Invalid delay '$Value'. Examples: 30m, 2h, 1d."
}

function ConvertTo-TimeOfDay {
  param([string]$Value)
  $parsed = [DateTime]::MinValue
  foreach ($candidate in @($Value, "2000-01-01 $Value")) {
    if ([DateTime]::TryParse($candidate, [ref]$parsed)) { return $parsed }
  }
  throw "Invalid time '$Value'. Use HH:mm, for example 09:00."
}

function Split-Tokens {
  param([string[]]$Tokens)
  if ($null -eq $Tokens) { $Tokens = @() } else { $Tokens = @($Tokens) }
  $options = @{}
  $positionals = New-Object System.Collections.Generic.List[string]
  $passthrough = New-Object System.Collections.Generic.List[string]
  $afterDashDash = $false
  $i = 0
  while ($i -lt $Tokens.Count) {
    $token = [string]$Tokens[$i]
    if ($afterDashDash) { $passthrough.Add($token); $i++; continue }
    if ($token -eq '--') { $afterDashDash = $true; $i++; continue }
    if ($token.StartsWith('--')) {
      $name = $token.Substring(2)
      $valueOptions = @('once','every','daily','weekly','missed','random-delay','script','input','cwd')
      if ($name -in $valueOptions) {
        if (($i + 1) -ge $Tokens.Count) { throw "Option --$name requires a value." }
        if ($name -eq 'weekly') {
          if (($i + 2) -ge $Tokens.Count) { throw 'Option --weekly requires <days> <HH:mm>.' }
          $options[$name] = @([string]$Tokens[$i + 1], [string]$Tokens[$i + 2])
          $i += 3
          continue
        }
        $options[$name] = [string]$Tokens[$i + 1]
        $i += 2
        continue
      }
      $options[$name] = $true
      $i++
      continue
    }
    $positionals.Add($token)
    $i++
  }
  return @{ options = $options; positionals = @($positionals); passthrough = @($passthrough) }
}

function Get-TaskJsonPath { param([string]$Kind, [string]$Id) return (Join-Path (Join-Path $TaskRoot $Kind) (Join-Path $Id 'task.json')) }
function Get-TaskFolder { param([string]$Kind, [string]$Id) return (Join-Path (Join-Path $TaskRoot $Kind) $Id) }

function Find-TaskRecordPath {
  param([string]$Id)
  foreach ($kind in @('persistent','temp')) {
    $path = Get-TaskJsonPath -Kind $kind -Id $Id
    if (Test-Path -LiteralPath $path -PathType Leaf) { return $path }
  }
  return $null
}

function Get-TaskRecord {
  param([string]$Id)
  $path = Find-TaskRecordPath -Id $Id
  if ([string]::IsNullOrWhiteSpace($path)) { throw "Cron task not found: $Id" }
  $record = Read-JsonFile -Path $path
  $record['__path'] = $path
  $record['__folder'] = Split-Path -Parent $path
  return $record
}

function Save-TaskRecord {
  param([hashtable]$Record)
  $path = if ($Record.ContainsKey('__path')) { [string]$Record['__path'] } else { Get-TaskJsonPath -Kind ([string]$Record['kind']) -Id ([string]$Record['id']) }
  $copy = @{}
  foreach ($key in $Record.Keys) { if (-not ([string]$key).StartsWith('__')) { $copy[$key] = $Record[$key] } }
  $copy['updatedAt'] = (Get-Date).ToString('o')
  Write-JsonFile -Path $path -Value $copy
}

function ConvertTo-TaskArgumentString {
  param([string[]]$Arguments)
  return (@($Arguments) | ForEach-Object {
    $value = [string]$_
    if ($value -match '[\s"]') { '"' + ($value -replace '(\\*)"', '$1$1\"') + '"' } else { $value }
  }) -join ' '
}

function New-TriggerFromSchedule {
  param([hashtable]$Options)
  $randomDelay = $null
  if ($Options.ContainsKey('random-delay')) { $randomDelay = ConvertFrom-DelayText -Value ([string]$Options['random-delay']) }
  $count = 0
  foreach ($key in @('once','every','daily','weekly')) { if ($Options.ContainsKey($key)) { $count++ } }
  if ($count -ne 1) { throw 'Exactly one schedule form is required: --once, --every, --daily, or --weekly.' }
  if ($Options.ContainsKey('once')) {
    $at = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$Options['once'], [ref]$at)) { throw "Invalid --once datetime '$($Options['once'])'." }
    if ($null -ne $randomDelay) { return New-ScheduledTaskTrigger -Once -At $at -RandomDelay $randomDelay }
    return New-ScheduledTaskTrigger -Once -At $at
  }
  if ($Options.ContainsKey('every')) {
    $interval = ConvertFrom-DelayText -Value ([string]$Options['every'])
    $at = (Get-Date).AddMinutes(1)
    if ($null -ne $randomDelay) { return New-ScheduledTaskTrigger -Once -At $at -RepetitionInterval $interval -RandomDelay $randomDelay }
    return New-ScheduledTaskTrigger -Once -At $at -RepetitionInterval $interval
  }
  if ($Options.ContainsKey('daily')) {
    $at = ConvertTo-TimeOfDay -Value ([string]$Options['daily'])
    if ($null -ne $randomDelay) { return New-ScheduledTaskTrigger -Daily -At $at -RandomDelay $randomDelay }
    return New-ScheduledTaskTrigger -Daily -At $at
  }
  if ($Options.ContainsKey('weekly')) {
    $weekly = @($Options['weekly'])
    $days = @(([string]$weekly[0]).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    $at = ConvertTo-TimeOfDay -Value ([string]$weekly[1])
    if ($null -ne $randomDelay) { return New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At $at -RandomDelay $randomDelay }
    return New-ScheduledTaskTrigger -Weekly -DaysOfWeek $days -At $at
  }
}

function Get-ScheduleDescriptor {
  param([hashtable]$Options)
  foreach ($key in @('once','every','daily')) { if ($Options.ContainsKey($key)) { return @{ type = $key; value = [string]$Options[$key] } } }
  if ($Options.ContainsKey('weekly')) { $weekly = @($Options['weekly']); return @{ type = 'weekly'; days = [string]$weekly[0]; time = [string]$weekly[1] } }
  throw 'Schedule missing.'
}

function Register-CronScheduledTask {
  param([hashtable]$Record, [hashtable]$Options)
  $runnerArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$RunnerPath,'_run-task',[string]$Record['id'])
  $action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument (ConvertTo-TaskArgumentString -Arguments $runnerArgs) -WorkingDirectory $WorkspaceRoot
  $trigger = New-TriggerFromSchedule -Options $Options
  $missed = if ($Options.ContainsKey('missed')) { [string]$Options['missed'] } else { 'skip' }
  if ($missed -notin @('skip','catch-up')) { throw "Invalid --missed '$missed'. Use skip or catch-up." }
  $settingsArgs = @{ AllowStartIfOnBatteries = $true; DontStopIfGoingOnBatteries = $true; MultipleInstances = 'IgnoreNew'; ExecutionTimeLimit = [TimeSpan]::Zero }
  if ($missed -eq 'catch-up') { $settingsArgs['StartWhenAvailable'] = $true }
  $settings = New-ScheduledTaskSettingsSet @settingsArgs
  Register-ScheduledTask -TaskName ([string]$Record['taskName']) -TaskPath $SchedulerTaskPath -Action $action -Trigger $trigger -Settings $settings -Description "mycli cron task $($Record['id'])" -Force | Out-Null
}

function Add-CronTask {
  param([string]$Mode, [string[]]$Tokens)
  if ($null -eq $Tokens) { $Tokens = @() } else { $Tokens = @($Tokens) }
  Ensure-Roots
  if ($Tokens.Count -lt 1) { throw "Usage: cron $Mode <id> [schedule options] -- ..." }
  $id = [string]$Tokens[0]
  if (-not (Test-ValidId -Id $id)) { throw "Invalid id '$id'. Use only letters, numbers, underscore, dash, and dot." }
  if (Find-TaskRecordPath -Id $id) { throw "Cron task already exists: $id" }
  $parsed = Split-Tokens -Tokens @(if ($Tokens.Count -gt 1) { $Tokens[1..($Tokens.Count - 1)] } else { @() })
  $options = $parsed['options']
  $passthrough = @($parsed['passthrough'])
  $schedule = Get-ScheduleDescriptor -Options $options
  $kind = if ($options.ContainsKey('temp')) { 'temp' } elseif ($options.ContainsKey('persistent')) { 'persistent' } elseif ([string]$schedule['type'] -eq 'once') { 'temp' } else { 'persistent' }
  $folder = Get-TaskFolder -Kind $kind -Id $id
  New-Item -ItemType Directory -Path (Join-Path $folder 'runs') -Force | Out-Null
  New-Item -ItemType Directory -Path (Join-Path $folder 'scripts') -Force | Out-Null
  $now = (Get-Date).ToString('o')
  $runSpec = @{}
  if ($Mode -eq 'add-command') {
    $commandTokens = if ($passthrough.Count -gt 0) { @($passthrough) } else { @($parsed['positionals']) }
    if ($commandTokens.Count -lt 1) { throw 'add-command requires -- <command...>.' }
    $runSpec = @{ type = 'command'; command = @($commandTokens); input = if ($options.ContainsKey('input')) { [string]$options['input'] } else { '' } }
  } else {
    if (-not $options.ContainsKey('script')) { throw 'add-script requires --script <path>.' }
    $scriptPath = [string]$options['script']
    if (-not (Test-Path -LiteralPath $scriptPath -PathType Leaf)) { throw "Script not found: $scriptPath" }
    $storedPath = $scriptPath
    if ($options.ContainsKey('copy-script')) {
      $target = Join-Path (Join-Path $folder 'scripts') (Split-Path -Leaf $scriptPath)
      Copy-Item -LiteralPath $scriptPath -Destination $target -Force
      $storedPath = $target
    }
    $runSpec = @{ type = 'script'; script = $storedPath; sourceScript = $scriptPath; args = @($passthrough); input = if ($options.ContainsKey('input')) { [string]$options['input'] } else { '' } }
  }
  $record = @{
    id = $id
    kind = $kind
    status = 'enabled'
    schedule = $schedule
    missed = if ($options.ContainsKey('missed')) { [string]$options['missed'] } else { 'skip' }
    randomDelay = if ($options.ContainsKey('random-delay')) { [string]$options['random-delay'] } else { '' }
    cwd = if ($options.ContainsKey('cwd')) { [string]$options['cwd'] } else { $WorkspaceRoot }
    run = $runSpec
    taskPath = $SchedulerTaskPath
    taskName = ConvertTo-SafeTaskName -Id $id
    createdAt = $now
    updatedAt = $now
    lastRunAt = ''
    lastExitCode = $null
  }
  Write-JsonFile -Path (Get-TaskJsonPath -Kind $kind -Id $id) -Value $record
  try { Register-CronScheduledTask -Record $record -Options $options } catch { Remove-Item -LiteralPath $folder -Recurse -Force -ErrorAction SilentlyContinue; throw }
  Write-Output "Registered cron task: $id"
  Write-Output "Kind: $kind"
  Write-Output "Task: $SchedulerTaskPath$($record['taskName'])"
}

function Get-ScheduledTaskStateSafe {
  param([hashtable]$Record)
  try {
    $task = Get-ScheduledTask -TaskPath ([string]$Record['taskPath']) -TaskName ([string]$Record['taskName']) -ErrorAction Stop
    $info = Get-ScheduledTaskInfo -TaskPath ([string]$Record['taskPath']) -TaskName ([string]$Record['taskName']) -ErrorAction SilentlyContinue
    return @{ state = [string]$task.State; lastRunTime = if ($info) { [string]$info.LastRunTime } else { '' }; nextRunTime = if ($info) { [string]$info.NextRunTime } else { '' }; lastTaskResult = if ($info) { [string]$info.LastTaskResult } else { '' } }
  } catch { return @{ state = 'missing'; lastRunTime = ''; nextRunTime = ''; lastTaskResult = '' } }
}

function Get-AllTaskRecords {
  Ensure-Roots
  $records = @()
  foreach ($kind in @('persistent','temp')) {
    $root = Join-Path $TaskRoot $kind
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Recurse -Filter task.json -File -ErrorAction SilentlyContinue)) {
      try {
        $record = Read-JsonFile -Path $file.FullName
        $record['__path'] = $file.FullName
        $record['__folder'] = Split-Path -Parent $file.FullName
        $records += ,$record
      } catch { continue }
    }
  }
  return @($records | Sort-Object kind,id)
}

function Show-TaskList {
  param([bool]$AsJson)
  $items = @()
  foreach ($record in @(Get-AllTaskRecords)) {
    $state = Get-ScheduledTaskStateSafe -Record $record
    $items += ,[pscustomobject]@{
      id = [string]$record['id']; kind = [string]$record['kind']; status = [string]$record['status']; schedulerState = [string]$state['state']; schedule = ($record['schedule'] | ConvertTo-Json -Compress); nextRunTime = [string]$state['nextRunTime']; lastRunAt = [string]$record['lastRunAt']; lastExitCode = $record['lastExitCode']; commandType = [string]$record['run']['type']
    }
  }
  if ($AsJson) { $items | ConvertTo-Json -Depth 10; return }
  if ($items.Count -eq 0) { Write-Output 'No cron tasks registered.'; return }
  $items | Format-Table -AutoSize
}

function Set-CronTaskEnabled {
  param([string]$Id, [bool]$Enabled)
  $record = Get-TaskRecord -Id $Id
  if ($Enabled) { Enable-ScheduledTask -TaskPath ([string]$record['taskPath']) -TaskName ([string]$record['taskName']) | Out-Null; $record['status'] = 'enabled' }
  else { Disable-ScheduledTask -TaskPath ([string]$record['taskPath']) -TaskName ([string]$record['taskName']) | Out-Null; $record['status'] = 'disabled' }
  Save-TaskRecord -Record $record
  $label = if ($Enabled) { 'Enabled' } else { 'Disabled' }
  Write-Output "$label cron task: $Id"
}

function Delete-CronTask {
  param([string]$Id)
  $record = Get-TaskRecord -Id $Id
  try { Unregister-ScheduledTask -TaskPath ([string]$record['taskPath']) -TaskName ([string]$record['taskName']) -Confirm:$false -ErrorAction Stop } catch { Write-Output "Scheduled task already missing: $($record['taskPath'])$($record['taskName'])" }
  Remove-Item -LiteralPath ([string]$record['__folder']) -Recurse -Force
  Write-Output "Deleted cron task: $Id"
}

function Invoke-CronTask {
  param([string]$Id, [bool]$FromScheduler)
  $record = Get-TaskRecord -Id $Id
  $folder = [string]$record['__folder']
  $runs = Join-Path $folder 'runs'
  if (-not (Test-Path -LiteralPath $runs -PathType Container)) { New-Item -ItemType Directory -Path $runs -Force | Out-Null }
  $runId = Get-Date -Format 'yyyyMMdd-HHmmss'
  $stdout = Join-Path $runs "$runId.out.log"
  $stderr = Join-Path $runs "$runId.err.log"
  $metaPath = Join-Path $runs "$runId.meta.json"
  $started = Get-Date
  $exitCode = 0
  try {
    $run = $record['run']
    if ([string]$run['type'] -eq 'command') {
      $parts = @($run['command'])
      if ($parts.Count -lt 1) { throw 'Empty command.' }
      $exe = [string]$parts[0]
      $args = if ($parts.Count -gt 1) { @($parts[1..($parts.Count - 1)]) } else { @() }
      $actualExe = $exe
      $actualArgs = @($args)
      if ($exe -match '\.ps1$') { $actualExe = 'powershell.exe'; $actualArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$exe) + @($args) }
      $p = Start-Process -FilePath $actualExe -ArgumentList $actualArgs -WorkingDirectory ([string]$record['cwd']) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
      $exitCode = $p.ExitCode
    } else {
      $script = [string]$run['script']
      $args = @($run['args'])
      $actualExe = $script
      $actualArgs = @($args)
      if ($script -match '\.ps1$') { $actualExe = 'powershell.exe'; $actualArgs = @('-NoProfile','-ExecutionPolicy','Bypass','-File',$script) + @($args) }
      $p = Start-Process -FilePath $actualExe -ArgumentList $actualArgs -WorkingDirectory ([string]$record['cwd']) -NoNewWindow -Wait -PassThru -RedirectStandardOutput $stdout -RedirectStandardError $stderr
      $exitCode = $p.ExitCode
    }
  } catch {
    $exitCode = 1
    $_.Exception.Message | Set-Content -LiteralPath $stderr -Encoding UTF8
  }
  $finished = Get-Date
  $meta = @{ runId = $runId; taskId = $Id; startedAt = $started.ToString('o'); finishedAt = $finished.ToString('o'); exitCode = $exitCode; stdout = $stdout; stderr = $stderr; fromScheduler = $FromScheduler }
  Write-JsonFile -Path $metaPath -Value $meta
  $record['lastRunAt'] = $finished.ToString('o')
  $record['lastExitCode'] = $exitCode
  if ([string]$record['kind'] -eq 'temp' -and $FromScheduler) {
    try { Unregister-ScheduledTask -TaskPath ([string]$record['taskPath']) -TaskName ([string]$record['taskName']) -Confirm:$false -ErrorAction SilentlyContinue } catch {}
    $record['status'] = 'completed'
  }
  Save-TaskRecord -Record $record
  Write-Output "Cron task run completed: $Id exit=$exitCode"
  if ($exitCode -ne 0) { exit $exitCode }
}

function Show-CronTask {
  param([string]$Id)
  $record = Get-TaskRecord -Id $Id
  $state = Get-ScheduledTaskStateSafe -Record $record
  $record['scheduler'] = $state
  $record | ConvertTo-Json -Depth 20
}

function Show-CronLogs {
  param([string[]]$Tokens)
  if ($null -eq $Tokens) { $Tokens = @() } else { $Tokens = @($Tokens) }
  if ($Tokens.Count -lt 1) { throw 'logs requires <id>.' }
  $id = [string]$Tokens[0]
  $last = 5
  $parsed = Split-Tokens -Tokens @(if ($Tokens.Count -gt 1) { $Tokens[1..($Tokens.Count - 1)] } else { @() })
  if ($parsed['options'].ContainsKey('last')) { $last = [int]$parsed['options']['last'] }
  $record = Get-TaskRecord -Id $id
  $runs = Join-Path ([string]$record['__folder']) 'runs'
  $metas = @(Get-ChildItem -LiteralPath $runs -Filter '*.meta.json' -File -ErrorAction SilentlyContinue | Sort-Object Name | Select-Object -Last $last)
  if ($metas.Count -eq 0) { Write-Output "No runs recorded for $id."; return }
  foreach ($file in $metas) {
    $meta = Read-JsonFile -Path $file.FullName
    Write-Output ("--- {0} exit={1} started={2} ---" -f [string]$meta['runId'], [string]$meta['exitCode'], [string]$meta['startedAt'])
    Write-Output ("stdout: {0}" -f [string]$meta['stdout'])
    Write-Output ("stderr: {0}" -f [string]$meta['stderr'])
  }
}

function Show-Status {
  $records = @(Get-AllTaskRecords)
  Write-Output "Persistent root: $PersistentRoot"
  Write-Output "Temp root: $TempRoot"
  Write-Output "Scheduler path: $SchedulerTaskPath"
  Write-Output ("Tasks: {0} persistent, {1} temp, {2} total" -f @($records | Where-Object { [string]$_['kind'] -eq 'persistent' }).Count, @($records | Where-Object { [string]$_['kind'] -eq 'temp' }).Count, $records.Count)
}

Ensure-Roots
$command = '--help'
[string[]]$remaining = @()
$argList = @($InputArgs)
if ($argList.Count -gt 0) {
  $command = [string]$argList[0]
}
if ($argList.Count -gt 1) {
  $remaining = [string[]]@($argList | Select-Object -Skip 1)
}

switch ($command) {
  { $_ -in @('--help','-h','help') } { Show-Usage; exit 0 }
  'task-list' { $asJson = $remaining -contains '--json'; Show-TaskList -AsJson $asJson; exit 0 }
  'list' { $asJson = $remaining -contains '--json'; Show-TaskList -AsJson $asJson; exit 0 }
  'add-command' { Add-CronTask -Mode 'add-command' -Tokens $remaining; exit 0 }
  'add-script' { Add-CronTask -Mode 'add-script' -Tokens $remaining; exit 0 }
  'enable' { if ($remaining.Count -ne 1) { throw 'enable requires <id>.' }; Set-CronTaskEnabled -Id $remaining[0] -Enabled $true; exit 0 }
  'disable' { if ($remaining.Count -ne 1) { throw 'disable requires <id>.' }; Set-CronTaskEnabled -Id $remaining[0] -Enabled $false; exit 0 }
  'delete' { if ($remaining.Count -ne 1) { throw 'delete requires <id>.' }; Delete-CronTask -Id $remaining[0]; exit 0 }
  'run' { if ($remaining.Count -ne 1) { throw 'run requires <id>.' }; Invoke-CronTask -Id $remaining[0] -FromScheduler:$false; exit 0 }
  '_run-task' { if ($remaining.Count -ne 1) { throw '_run-task requires <id>.' }; Invoke-CronTask -Id $remaining[0] -FromScheduler:$true; exit 0 }
  'show' { if ($remaining.Count -ne 1) { throw 'show requires <id>.' }; Show-CronTask -Id $remaining[0]; exit 0 }
  'logs' { Show-CronLogs -Tokens $remaining; exit 0 }
  'status' { Show-Status; exit 0 }
  default { throw "Unknown cron command: $command" }
}
