$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$WorkspaceConfigModule = Join-Path (Split-Path -Parent (Split-Path -Parent $Root)) "common\workspace-config.ps1"
. $WorkspaceConfigModule
$WorkspaceConfig = Get-MyCliWorkspaceConfig -PackagePath 'channels/monitor-ui'
$Port = if ($args.Count -gt 0 -and $args[0]) { [string]$args[0] } else { "45990" }
$LogDir = [string]$WorkspaceConfig.paths.logs
$StateDir = [string]$WorkspaceConfig.paths.var
$OutLog = Join-Path $LogDir "monitor-ui.out.log"
$ErrLog = Join-Path $LogDir "monitor-ui.err.log"
$PidFile = Join-Path $StateDir "monitor-ui-pids.json"

New-Item -ItemType Directory -Force -Path $LogDir, $StateDir | Out-Null

function Test-HttpOk($Uri) {
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 3
    return @{ ok = $true; status = $response.StatusCode }
  } catch {
    return @{ ok = $false; error = $_.Exception.Message }
  }
}

function Get-PortListenerPid($PortValue) {
  Get-NetTCPConnection -LocalPort ([int]$PortValue) -State Listen -ErrorAction SilentlyContinue |
    Select-Object -ExpandProperty OwningProcess -Unique -First 1
}

$healthUrl = "http://127.0.0.1:$Port/api/snapshot"
$existing = Test-HttpOk $healthUrl
if ($existing.ok) {
  $pidValue = Get-PortListenerPid $Port
  Write-Host "Channel monitor UI already running: http://127.0.0.1:$Port PID=$pidValue"
  return
}

$process = Start-Process -FilePath "node.exe" `
  -ArgumentList @("server.js", $Port) `
  -WorkingDirectory $Root `
  -RedirectStandardOutput $OutLog `
  -RedirectStandardError $ErrLog `
  -WindowStyle Hidden `
  -PassThru

Start-Sleep -Milliseconds 800
$health = Test-HttpOk $healthUrl

@{
  startedAt = (Get-Date).ToString("o")
  root = $Root
  port = $Port
  pid = $process.Id
  url = "http://127.0.0.1:$Port"
  logs = @{
    stdout = $OutLog
    stderr = $ErrLog
  }
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $PidFile -Encoding UTF8

if ($health.ok) {
  Write-Host "Channel monitor UI started detached: http://127.0.0.1:$Port PID=$($process.Id)"
} else {
  Write-Host "Channel monitor UI start requested, but health check failed: $($health.error)"
  Write-Host "PID=$($process.Id) Logs: $OutLog ; $ErrLog"
}
