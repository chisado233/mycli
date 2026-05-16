[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$script:PackageRoot = Split-Path -Parent $PSScriptRoot
$script:StateRoot = Join-Path $script:PackageRoot "state\sessions"
$script:BrokerScriptPath = Join-Path $PSScriptRoot "broker.ps1"
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:Utf8WithBom = [System.Text.UTF8Encoding]::new($true)

function Write-ToolError {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-Utf8Text {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
}

function Write-Utf8Text {
    param(
        [string]$Path,
        [string]$Content,
        [bool]$EmitBom = $true
    )

    $encoding = if ($EmitBom) { $script:Utf8WithBom } else { $script:Utf8NoBom }
    [System.IO.File]::WriteAllText($Path, $Content, $encoding)
}

function Read-JsonFile {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        return $null
    }

    try {
        return (Read-Utf8Text -Path $Path) | ConvertFrom-Json -Depth 20
    } catch {
        Write-ToolError "Failed to parse JSON file '$Path'. $($_.Exception.Message)"
    }
}

function Write-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 20
    Write-Utf8Text -Path $Path -Content $json
}

function Get-OptionBundle {
    param([string[]]$Tokens)

    $tokenList = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Tokens)) {
        if ($null -ne $item) {
            $tokenList.Add([string]$item)
        }
    }

    $options = @{}
    $positionals = New-Object System.Collections.Generic.List[string]
    $i = 0
    while ($i -lt $tokenList.Count) {
        $token = $tokenList[$i]
        if ($token.StartsWith("--")) {
            $name = $token.Substring(2)
            if (($i + 1) -lt $tokenList.Count -and -not $tokenList[$i + 1].StartsWith("--")) {
                $options[$name] = $tokenList[$i + 1]
                $i += 2
                continue
            }

            $options[$name] = $true
            $i += 1
            continue
        }

        $positionals.Add($token)
        $i += 1
    }

    return @{ Options = $options; Positionals = [string[]]$positionals }
}

function Get-StateRoot {
    Ensure-Directory -Path $script:StateRoot
    return $script:StateRoot
}

function New-SessionId {
    return "ps_{0}_{1}" -f ([DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")), ([Guid]::NewGuid().ToString("N").Substring(0, 6))
}

function Get-SessionRoot {
    param([string]$SessionId)
    return Join-Path (Get-StateRoot) $SessionId
}

function Get-SessionFileSet {
    param([string]$SessionId)
    $root = Get-SessionRoot -SessionId $SessionId
    return [ordered]@{
        root = $root
        meta = Join-Path $root "meta.json"
        events = Join-Path $root "events.jsonl"
        inbox = Join-Path $root "inbox"
        history = Join-Path $root "history"
        stop = Join-Path $root "stop.request"
        ready = Join-Path $root "ready.flag"
        launchLog = Join-Path $root "broker.launch.log"
        launchErrorLog = Join-Path $root "broker.launch.stderr.log"
        brokerLog = Join-Path $root "broker.runtime.log"
    }
}

function Ensure-SessionLayout {
    param([string]$SessionId)
    $files = Get-SessionFileSet -SessionId $SessionId
    Ensure-Directory -Path $files.root
    Ensure-Directory -Path $files.inbox
    Ensure-Directory -Path $files.history
    if (-not (Test-Path -LiteralPath $files.events)) {
        Write-Utf8Text -Path $files.events -Content "" -EmitBom $false
    }
    return $files
}

function Resolve-ShellExecutable {
    param([string]$Shell)
    $resolvedName = if ([string]::IsNullOrWhiteSpace($Shell)) { "pwsh" } else { $Shell }
    $command = Get-Command $resolvedName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($null -eq $command) {
        Write-ToolError "Unable to resolve shell executable '$resolvedName'."
    }
    return $command.Source
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch {
        return $false
    }
}

function Wait-ForReady {
    param([string]$SessionId, [int]$TimeoutMs = 8000)
    $files = Get-SessionFileSet -SessionId $SessionId
    $deadline = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
    while ([DateTime]::UtcNow -lt $deadline) {
        if (Test-Path -LiteralPath $files.ready) {
            return $true
        }
        Start-Sleep -Milliseconds 200
    }
    return (Test-Path -LiteralPath $files.ready)
}

function ConvertTo-ArgumentString {
    param([string[]]$Arguments)

    $escaped = foreach ($arg in @($Arguments)) {
        if ($null -eq $arg) {
            '""'
            continue
        }

        if ($arg -notmatch '[\s"]') {
            $arg
            continue
        }

        '"' + (($arg -replace '(\\*)"', '$1$1\\"') -replace '(\\+)$', '$1$1') + '"'
    }

    return ($escaped -join ' ')
}

function Start-Session {
    param([string[]]$Tokens)

    $bundle = Get-OptionBundle -Tokens $Tokens
    $options = $bundle.Options
    $sessionId = if ($options.ContainsKey("session")) { [string]$options["session"] } else { New-SessionId }
    $files = Ensure-SessionLayout -SessionId $sessionId
    $cwd = if ($options.ContainsKey("cwd")) { [string]$options["cwd"] } else { (Get-Location).Path }
    $shellPreference = if ($options.ContainsKey("shell")) { [string]$options["shell"] } else { "pwsh" }
    $shellPath = Resolve-ShellExecutable -Shell $shellPreference
    $runAsAdmin = $options.ContainsKey("admin")
    $idleTimeoutSec = if ($options.ContainsKey("idle-timeout-sec")) { [int]$options["idle-timeout-sec"] } else { 120 }
    $waitReady = $options.ContainsKey("wait-ready")
    $initialMeta = [ordered]@{
        session_id = $sessionId
        status = "starting"
        requested_admin = $runAsAdmin
        broker_is_admin = $false
        shell_preference = $shellPreference
        shell_path = $shellPath
        cwd = $cwd
        created_at_utc = [DateTime]::UtcNow.ToString("o")
        updated_at_utc = [DateTime]::UtcNow.ToString("o")
        broker_pid = $null
        child_pid = $null
        last_seq = 0
        last_command_id = $null
        last_exit_code = $null
        idle_timeout_sec = $idleTimeoutSec
        last_activity_utc = [DateTime]::UtcNow.ToString("o")
        transport = "powershell-runspace-broker"
        broker_log_path = $files.brokerLog
        broker_launch_log_path = $files.launchLog
        broker_launch_error_log_path = $files.launchErrorLog
    }
    Write-JsonFile -Path $files.meta -Value $initialMeta

    $enginePath = (Get-Process -Id $PID).Path
    $argumentList = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $script:BrokerScriptPath,
        "-SessionId", $sessionId,
        "-SessionRoot", $files.root,
        "-ShellPath", $shellPath,
        "-ShellPreference", $shellPreference,
        "-InitialCwd", $cwd,
        "-IdleTimeoutSec", [string]$idleTimeoutSec,
        "-RequestedAdmin:$runAsAdmin"
    )
    $argumentString = ConvertTo-ArgumentString -Arguments $argumentList

    try {
        if ($runAsAdmin -and -not (Test-IsAdministrator)) {
            $process = Start-Process -FilePath $enginePath -ArgumentList $argumentString -WindowStyle Hidden -Verb RunAs -PassThru
        } else {
            $process = Start-Process -FilePath $enginePath -ArgumentList $argumentString -WindowStyle Hidden -PassThru
        }
    } catch {
        Write-ToolError "Failed to start broker process. $($_.Exception.Message)"
    }

    Start-Sleep -Milliseconds 300
    $meta = Read-JsonFile -Path $files.meta
    if ($null -ne $meta) {
        $meta.broker_pid = $process.Id
        $meta.updated_at_utc = [DateTime]::UtcNow.ToString("o")
        if ((Test-Path -LiteralPath $files.ready) -and [string]$meta.status -eq "starting") {
            $meta.status = "running"
        }
        Write-JsonFile -Path $files.meta -Value $meta
    }

    ([ordered]@{
        session_id = $sessionId
        ready = if ($waitReady) { Wait-ForReady -SessionId $sessionId } else { $false }
        detached = $true
        requested_admin = $runAsAdmin
        idle_timeout_sec = $idleTimeoutSec
        cwd = $cwd
        shell = $shellPath
        session_root = $files.root
    } | ConvertTo-Json -Depth 10) | Write-Output
}

function Send-SessionInput {
    param([string[]]$Tokens)

    $bundle = Get-OptionBundle -Tokens $Tokens
    $positionals = $bundle.Positionals
    $options = $bundle.Options
    if ($positionals.Count -lt 1) {
        Write-ToolError "Usage: mycli PowerShell-cli send <session-id> --text <command>"
    }

    $sessionId = [string]$positionals[0]
    $files = Get-SessionFileSet -SessionId $sessionId
    if (-not (Test-Path -LiteralPath $files.meta)) {
        Write-ToolError "Unknown session '$sessionId'."
    }

    $text = if ($options.ContainsKey("text")) { [string]$options["text"] } elseif ($positionals.Count -gt 1) { ($positionals[1..($positionals.Count - 1)] -join " ") } else { Write-ToolError "Usage: mycli PowerShell-cli send <session-id> --text <command>" }
    $commandId = "cmd_{0}_{1}" -f ([DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")), ([Guid]::NewGuid().ToString("N").Substring(0, 6))
    $payload = [ordered]@{ command_id = $commandId; session_id = $sessionId; text = $text; created_at_utc = [DateTime]::UtcNow.ToString("o") }
    $path = Join-Path $files.inbox ("{0}.json" -f $commandId)
    Write-JsonFile -Path $path -Value $payload

    $meta = Read-JsonFile -Path $files.meta
    if ($null -ne $meta) {
        if ($meta.PSObject.Properties["status"] -and [string]$meta.status -ne "running" -and -not (Test-Path -LiteralPath $files.ready)) {
            Write-ToolError "Session '$sessionId' is not running. Current status: $($meta.status)."
        }
        $meta.last_command_id = $commandId
        $meta.last_activity_utc = [DateTime]::UtcNow.ToString("o")
        $meta.updated_at_utc = [DateTime]::UtcNow.ToString("o")
        Write-JsonFile -Path $files.meta -Value $meta
    }

    ([ordered]@{ session_id = $sessionId; command_id = $commandId; queued = $true; text = $text } | ConvertTo-Json -Depth 10) | Write-Output
}

function Read-EventLines {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { return @() }
    $content = Read-Utf8Text -Path $Path
    if ([string]::IsNullOrEmpty($content)) { return @() }
    return @($content -split "`r?`n" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
}

function Read-SessionOutput {
    param([string[]]$Tokens)

    $bundle = Get-OptionBundle -Tokens $Tokens
    $positionals = $bundle.Positionals
    $options = $bundle.Options
    if ($positionals.Count -lt 1) {
        Write-ToolError "Usage: mycli PowerShell-cli read <session-id> [--after <seq>] [--wait-ms <ms>] [--limit <n>] [--raw]"
    }

    $sessionId = [string]$positionals[0]
    $files = Get-SessionFileSet -SessionId $sessionId
    $after = if ($options.ContainsKey("after")) { [int]$options["after"] } else { 0 }
    $waitMs = if ($options.ContainsKey("wait-ms")) { [int]$options["wait-ms"] } else { 0 }
    $limit = if ($options.ContainsKey("limit")) { [int]$options["limit"] } else { 200 }
    $raw = $options.ContainsKey("raw")
    $deadline = [DateTime]::UtcNow.AddMilliseconds($waitMs)

    $selected = @()
    do {
        $lines = Read-EventLines -Path $files.events
        $events = @($lines | ForEach-Object { try { $_ | ConvertFrom-Json -Depth 20 } catch { $null } } | Where-Object { $null -ne $_ -and [int]$_.seq -gt $after })
        if ($events.Count -gt 0 -or $waitMs -le 0) {
            $selected = $events
            break
        }
        Start-Sleep -Milliseconds 200
    } while ([DateTime]::UtcNow -lt $deadline)

    if ($limit -gt 0 -and $selected.Count -gt $limit) {
        $selected = @($selected | Select-Object -First $limit)
    }

    if ($raw) {
        foreach ($event in $selected) {
            if ($null -ne $event.text) {
                Write-Output ([string]$event.text)
            }
        }
        return
    }

    ([ordered]@{ session_id = $sessionId; after = $after; count = $selected.Count; events = @($selected) } | ConvertTo-Json -Depth 20) | Write-Output
}

function Get-SessionStatus {
    param([string[]]$Tokens)
    if ($Tokens.Count -lt 1) { Write-ToolError "Usage: mycli PowerShell-cli status <session-id>" }
    $sessionId = [string]$Tokens[0]
    $files = Get-SessionFileSet -SessionId $sessionId
    $meta = Read-JsonFile -Path $files.meta
    if ($null -eq $meta) { Write-ToolError "Unknown session '$sessionId'." }
    $meta | ConvertTo-Json -Depth 20 | Write-Output
}

function Get-SessionList {
    Ensure-Directory -Path (Get-StateRoot)
    $items = @()
    foreach ($dir in @(Get-ChildItem -LiteralPath (Get-StateRoot) -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $meta = Read-JsonFile -Path (Join-Path $dir.FullName "meta.json")
        if ($null -ne $meta) { $items += ,$meta }
    }
    $items | ConvertTo-Json -Depth 20 | Write-Output
}

function Test-ProcessAlive {
    param([object]$PidValue)
    if ($null -eq $PidValue) { return $false }
    $pidInt = 0
    if (-not [int]::TryParse([string]$PidValue, [ref]$pidInt)) { return $false }
    return $null -ne (Get-Process -Id $pidInt -ErrorAction SilentlyContinue)
}

function Stop-Session {
    param([string[]]$Tokens)
    if ($Tokens.Count -lt 1) { Write-ToolError "Usage: mycli PowerShell-cli stop <session-id>" }
    $sessionId = [string]$Tokens[0]
    $files = Get-SessionFileSet -SessionId $sessionId
    $meta = Read-JsonFile -Path $files.meta
    if ($null -eq $meta) { Write-ToolError "Unknown session '$sessionId'." }
    Write-Utf8Text -Path $files.stop -Content ([DateTime]::UtcNow.ToString("o")) -EmitBom $false
    Start-Sleep -Milliseconds 800

    if ($null -ne $meta.child_pid) {
        $child = Get-Process -Id ([int]$meta.child_pid) -ErrorAction SilentlyContinue
        if ($null -ne $child -and -not $child.HasExited) {
            Stop-Process -Id $child.Id -Force -ErrorAction SilentlyContinue
        }
    }

    if ($null -ne $meta.broker_pid) {
        $broker = Get-Process -Id ([int]$meta.broker_pid) -ErrorAction SilentlyContinue
        if ($null -ne $broker -and -not $broker.HasExited) {
            Stop-Process -Id $broker.Id -Force -ErrorAction SilentlyContinue
        }
    }
    $updatedMeta = Read-JsonFile -Path $files.meta
    if ($null -ne $updatedMeta) { $updatedMeta | ConvertTo-Json -Depth 20 | Write-Output } else { ([ordered]@{ session_id = $sessionId; stopped = $true } | ConvertTo-Json -Depth 10) | Write-Output }
}

function Invoke-Cleanup {
    param([string[]]$Tokens)

    $bundle = Get-OptionBundle -Tokens $Tokens
    $stopAll = $bundle.Options.ContainsKey("all")
    $results = @()
    Ensure-Directory -Path (Get-StateRoot)

    foreach ($dir in @(Get-ChildItem -LiteralPath (Get-StateRoot) -Directory -ErrorAction SilentlyContinue | Sort-Object Name)) {
        $metaPath = Join-Path $dir.FullName "meta.json"
        $meta = Read-JsonFile -Path $metaPath
        if ($null -eq $meta) { continue }

        $sessionId = [string]$meta.session_id
        $brokerAlive = Test-ProcessAlive -PidValue $meta.broker_pid
        $childAlive = Test-ProcessAlive -PidValue $meta.child_pid
        $action = "none"

        if ($stopAll -and ($brokerAlive -or $childAlive)) {
            $files = Get-SessionFileSet -SessionId $sessionId
            Write-Utf8Text -Path $files.stop -Content ([DateTime]::UtcNow.ToString("o")) -EmitBom $false
            Start-Sleep -Milliseconds 300
            if ($childAlive) { Stop-Process -Id ([int]$meta.child_pid) -Force -ErrorAction SilentlyContinue }
            if ($brokerAlive) { Stop-Process -Id ([int]$meta.broker_pid) -Force -ErrorAction SilentlyContinue }
            $meta.status = "stopped"
            $meta.updated_at_utc = [DateTime]::UtcNow.ToString("o")
            Write-JsonFile -Path $metaPath -Value $meta
            $action = "stopped"
        } elseif (([string]$meta.status -in @("starting", "running")) -and -not $brokerAlive) {
            $meta.status = "stale-stopped"
            $meta.updated_at_utc = [DateTime]::UtcNow.ToString("o")
            Write-JsonFile -Path $metaPath -Value $meta
            $action = "marked-stale"
        }

        $results += ,[ordered]@{ session_id = $sessionId; broker_alive = $brokerAlive; child_alive = $childAlive; action = $action }
    }

    $results | ConvertTo-Json -Depth 20 | Write-Output
}

function Show-Help {
    @"
PowerShell-cli

Usage:
  mycli PowerShell-cli start [--admin] [--shell pwsh|powershell] [--cwd <path>] [--session <id>] [--idle-timeout-sec <seconds>]
  mycli PowerShell-cli send <session-id> --text <command>
  mycli PowerShell-cli read <session-id> [--after <seq>] [--wait-ms <ms>] [--limit <n>] [--raw]
  mycli PowerShell-cli status <session-id>
  mycli PowerShell-cli sessions
  mycli PowerShell-cli stop <session-id>
  mycli PowerShell-cli cleanup [--all]
"@ | Write-Output
}

function Get-TailTokens {
    param([string[]]$Tokens)
    if ($null -eq $Tokens -or $Tokens.Count -le 1) {
        return @()
    }
    return @($Tokens[1..($Tokens.Count - 1)])
}

if (-not $CommandArgs -or $CommandArgs.Count -eq 0) {
    Show-Help
    exit 0
}

switch ($CommandArgs[0]) {
    "start" { Start-Session -Tokens (Get-TailTokens -Tokens $CommandArgs); break }
    "send" { Send-SessionInput -Tokens (Get-TailTokens -Tokens $CommandArgs); break }
    "read" { Read-SessionOutput -Tokens (Get-TailTokens -Tokens $CommandArgs); break }
    "status" { Get-SessionStatus -Tokens (Get-TailTokens -Tokens $CommandArgs); break }
    "sessions" { Get-SessionList; break }
    "list" { Get-SessionList; break }
    "stop" { Stop-Session -Tokens (Get-TailTokens -Tokens $CommandArgs); break }
    "cleanup" { Invoke-Cleanup -Tokens (Get-TailTokens -Tokens $CommandArgs); break }
    default { Show-Help; exit 1 }
}
