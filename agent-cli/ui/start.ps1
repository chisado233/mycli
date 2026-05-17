$ErrorActionPreference = "Stop"
if ($args -contains "--help" -or $args -contains "-h" -or $args -contains "help") {
@"
agent-cli ui

Usage:
  mycli agent-cli ui [port]

Starts the local Agent CLI Terminal UI in detached mode. Default port: 46030.
"@ | Write-Output
    return
}
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Port = if ($args.Count -gt 0 -and $args[0]) { [string]$args[0] } else { "46030" }
$WorkspaceConfigPath = "D:\agent_workspace\config\mycli\agent-cli\workspace-config.json"
$WorkspaceConfig = Get-Content -LiteralPath $WorkspaceConfigPath -Raw | ConvertFrom-Json
$LogDir = Join-Path ([string]$WorkspaceConfig.paths.logs) "ui"
$StateDir = Join-Path ([string]$WorkspaceConfig.paths.var) "ui"
$OutLog = Join-Path $LogDir "agent-cli-ui.out.log"
$ErrLog = Join-Path $LogDir "agent-cli-ui.err.log"
$PidFile = Join-Path $StateDir "agent-cli-ui-pids.json"
New-Item -ItemType Directory -Force -Path $LogDir, $StateDir | Out-Null
function Test-HttpOk($Uri) { try { $r = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 3; return @{ ok = $true; status = $r.StatusCode } } catch { return @{ ok = $false; error = $_.Exception.Message } } }
function Get-PortListenerPid($PortValue) { Get-NetTCPConnection -LocalPort ([int]$PortValue) -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique -First 1 }
$healthUrl = "http://127.0.0.1:$Port/api/snapshot"
$existing = Test-HttpOk $healthUrl
if ($existing.ok) { Write-Host "Agent CLI UI already running: http://127.0.0.1:$Port PID=$(Get-PortListenerPid $Port)"; return }
$process = Start-Process -FilePath "node.exe" -ArgumentList @("server.js", $Port) -WorkingDirectory $Root -RedirectStandardOutput $OutLog -RedirectStandardError $ErrLog -WindowStyle Hidden -PassThru
Start-Sleep -Milliseconds 900
$health = Test-HttpOk $healthUrl
@{ startedAt=(Get-Date).ToString("o"); root=$Root; port=$Port; pid=$process.Id; url="http://127.0.0.1:$Port"; logs=@{stdout=$OutLog;stderr=$ErrLog} } | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $PidFile -Encoding UTF8
if ($health.ok) { Write-Host "Agent CLI UI started detached: http://127.0.0.1:$Port PID=$($process.Id)" } else { Write-Host "Agent CLI UI start requested, but health check failed: $($health.error)"; Write-Host "PID=$($process.Id) Logs: $OutLog ; $ErrLog" }
