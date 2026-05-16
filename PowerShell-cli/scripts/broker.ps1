[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$SessionId,
    [Parameter(Mandatory = $true)]
    [string]$SessionRoot,
    [Parameter(Mandatory = $true)]
    [string]$ShellPath,
    [Parameter(Mandatory = $false)]
    [string]$ShellPreference = "pwsh",
    [Parameter(Mandatory = $false)]
    [string]$InitialCwd,
    [Parameter(Mandatory = $false)]
    [int]$IdleTimeoutSec = 120,
    [Parameter(Mandatory = $false)]
    [bool]$RequestedAdmin = $false
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:Utf8WithBom = [System.Text.UTF8Encoding]::new($true)
$script:SessionRoot = $SessionRoot
$script:MetaPath = Join-Path $SessionRoot "meta.json"
$script:EventsPath = Join-Path $SessionRoot "events.jsonl"
$script:InboxPath = Join-Path $SessionRoot "inbox"
$script:HistoryPath = Join-Path $SessionRoot "history"
$script:StopPath = Join-Path $SessionRoot "stop.request"
$script:ReadyPath = Join-Path $SessionRoot "ready.flag"
$script:BrokerLogPath = Join-Path $SessionRoot "broker.runtime.log"
$script:Seq = 0
$script:PowerShell = $null

function Ensure-Directory { param([string]$Path) if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }
function Read-Utf8Text { param([string]$Path) return [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom) }
function Write-Utf8Text { param([string]$Path,[string]$Content,[bool]$EmitBom = $true) $enc = if ($EmitBom) { $script:Utf8WithBom } else { $script:Utf8NoBom }; [System.IO.File]::WriteAllText($Path, $Content, $enc) }
function Append-Utf8Line { param([string]$Path,[string]$Line) [System.IO.File]::AppendAllText($Path, $Line + [Environment]::NewLine, $script:Utf8NoBom) }
function Write-BrokerLog { param([string]$Message) Append-Utf8Line -Path $script:BrokerLogPath -Line (([DateTime]::UtcNow.ToString("o")) + " " + $Message) }

function Read-Meta {
    if (-not (Test-Path -LiteralPath $script:MetaPath)) { return $null }
    try { return (Read-Utf8Text -Path $script:MetaPath) | ConvertFrom-Json -Depth 20 } catch { return $null }
}

function Write-Meta {
    param([object]$Value)
    Write-Utf8Text -Path $script:MetaPath -Content ($Value | ConvertTo-Json -Depth 20)
}

function Test-IsAdministrator {
    try {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    } catch { return $false }
}

function Publish-Event {
    param([string]$Stream,[string]$Text,[string]$Kind = "output")
    $script:Seq += 1
    $event = [ordered]@{ seq = $script:Seq; time_utc = [DateTime]::UtcNow.ToString("o"); kind = $Kind; stream = $Stream; text = $Text }
    Append-Utf8Line -Path $script:EventsPath -Line ($event | ConvertTo-Json -Depth 10 -Compress)
    $meta = Read-Meta
    if ($null -ne $meta) {
        $meta.last_seq = $script:Seq
        $meta.updated_at_utc = [DateTime]::UtcNow.ToString("o")
        Write-Meta -Value $meta
    }
}

function Get-MetaDateTimeOrDefault {
    param([object]$Meta,[string]$Name,[datetime]$DefaultValue)
    if ($null -eq $Meta) { return $DefaultValue }
    $property = $Meta.PSObject.Properties[$Name]
    if ($null -eq $property -or [string]::IsNullOrWhiteSpace([string]$property.Value)) { return $DefaultValue }
    try { return [datetime]::Parse([string]$property.Value) } catch { return $DefaultValue }
}

function Set-MetaStatus {
    param([string]$Status)
    $meta = Read-Meta
    if ($null -eq $meta) { return }
    $meta.status = $Status
    $meta.broker_pid = $PID
    $meta.broker_is_admin = (Test-IsAdministrator)
    $meta.child_pid = $null
    $meta.transport = "powershell-runspace-broker"
    $meta.updated_at_utc = [DateTime]::UtcNow.ToString("o")
    Write-Meta -Value $meta
}

function Invoke-QueuedCommand {
    param([object]$Payload)

    $text = [string]$Payload.text
    Publish-Event -Stream "broker" -Kind "input" -Text $text
    $meta = Read-Meta
    if ($null -ne $meta) {
        $meta.last_command_id = [string]$Payload.command_id
        $meta.last_activity_utc = [DateTime]::UtcNow.ToString("o")
        $meta.updated_at_utc = [DateTime]::UtcNow.ToString("o")
        Write-Meta -Value $meta
    }

    try {
        $script:PowerShell.Commands.Clear()
        $script:PowerShell.Streams.ClearStreams()
        $null = $script:PowerShell.AddScript($text)
        $resultItems = @($script:PowerShell.Invoke())

        foreach ($errorRecord in @($script:PowerShell.Streams.Error)) {
            Publish-Event -Stream "stderr" -Kind "error" -Text ([string]$errorRecord)
        }
        foreach ($warningRecord in @($script:PowerShell.Streams.Warning)) {
            Publish-Event -Stream "stderr" -Kind "warning" -Text ([string]$warningRecord.Message)
        }
        foreach ($verboseRecord in @($script:PowerShell.Streams.Verbose)) {
            Publish-Event -Stream "stdout" -Kind "verbose" -Text ([string]$verboseRecord.Message)
        }
        foreach ($informationRecord in @($script:PowerShell.Streams.Information)) {
            Publish-Event -Stream "stdout" -Kind "information" -Text ([string]$informationRecord.MessageData)
        }

        foreach ($item in $resultItems) {
            $textOutput = ($item | Out-String).TrimEnd()
            if (-not [string]::IsNullOrWhiteSpace($textOutput)) {
                Publish-Event -Stream "stdout" -Kind "output" -Text $textOutput
            }
        }

        $meta = Read-Meta
        if ($null -ne $meta) {
            $lastExitCodeValue = $script:PowerShell.Runspace.SessionStateProxy.GetVariable("LASTEXITCODE")
            $meta.last_exit_code = $lastExitCodeValue
            $meta.last_activity_utc = [DateTime]::UtcNow.ToString("o")
            $meta.updated_at_utc = [DateTime]::UtcNow.ToString("o")
            Write-Meta -Value $meta
        }
    } catch {
        Publish-Event -Stream "stderr" -Kind "error" -Text ([string]$_.Exception.Message)
    }
}

Ensure-Directory -Path $script:SessionRoot
Ensure-Directory -Path $script:InboxPath
Ensure-Directory -Path $script:HistoryPath
if (-not (Test-Path -LiteralPath $script:EventsPath)) { Write-Utf8Text -Path $script:EventsPath -Content "" -EmitBom $false }
if (-not (Test-Path -LiteralPath $script:BrokerLogPath)) { Write-Utf8Text -Path $script:BrokerLogPath -Content "" -EmitBom $false }

if (-not [string]::IsNullOrWhiteSpace($InitialCwd) -and (Test-Path -LiteralPath $InitialCwd)) {
    Set-Location -LiteralPath $InitialCwd
}

$script:PowerShell = [powershell]::Create()
if (-not [string]::IsNullOrWhiteSpace($InitialCwd) -and (Test-Path -LiteralPath $InitialCwd)) {
    $escapedCwd = $InitialCwd.Replace("'", "''")
    $null = $script:PowerShell.AddScript("Set-Location -LiteralPath '$escapedCwd'")
    $null = $script:PowerShell.Invoke()
    $script:PowerShell.Commands.Clear()
    $script:PowerShell.Streams.ClearStreams()
}

$meta = Read-Meta
if ($null -ne $meta) {
    $meta.status = "running"
    $meta.broker_pid = $PID
    $meta.broker_is_admin = (Test-IsAdministrator)
    $meta.child_pid = $null
    $meta.shell_path = $ShellPath
    $meta.shell_preference = $ShellPreference
    $meta.requested_admin = $RequestedAdmin
    $meta.idle_timeout_sec = $IdleTimeoutSec
    $meta.last_activity_utc = [DateTime]::UtcNow.ToString("o")
    $meta.transport = "powershell-runspace-broker"
    $meta.updated_at_utc = [DateTime]::UtcNow.ToString("o")
    Write-Meta -Value $meta
}

[System.IO.File]::WriteAllText($script:ReadyPath, [DateTime]::UtcNow.ToString("o"), $script:Utf8NoBom)
Write-BrokerLog ("Broker ready. pid={0}; admin={1}; idle_timeout_sec={2}" -f $PID, (Test-IsAdministrator), $IdleTimeoutSec)

try {
    while ($true) {
        if (Test-Path -LiteralPath $script:StopPath) {
            Write-BrokerLog "Stop requested."
            break
        }

        $inboxItems = @(Get-ChildItem -LiteralPath $script:InboxPath -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object Name)
        foreach ($item in $inboxItems) {
            try {
                $payload = (Read-Utf8Text -Path $item.FullName) | ConvertFrom-Json -Depth 20
                Move-Item -LiteralPath $item.FullName -Destination (Join-Path $script:HistoryPath $item.Name) -Force
                Invoke-QueuedCommand -Payload $payload
            } catch {
                Publish-Event -Stream "broker" -Kind "error" -Text ("Failed to process inbox item '{0}': {1}" -f $item.Name, $_.Exception.Message)
                Remove-Item -LiteralPath $item.FullName -Force -ErrorAction SilentlyContinue
            }
        }

        $meta = Read-Meta
        $lastActivity = Get-MetaDateTimeOrDefault -Meta $meta -Name "last_activity_utc" -DefaultValue ([datetime]::UtcNow)
        if ($IdleTimeoutSec -gt 0 -and [datetime]::UtcNow -ge $lastActivity.AddSeconds($IdleTimeoutSec)) {
            Write-BrokerLog ("Idle timeout reached ({0}s)." -f $IdleTimeoutSec)
            break
        }

        Start-Sleep -Milliseconds 150
    }
} finally {
    Set-MetaStatus -Status "stopped"
    if ($null -ne $script:PowerShell) {
        try { $script:PowerShell.Dispose() } catch {}
    }
    Write-BrokerLog "Broker stopped."
}
