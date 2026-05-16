$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PidFile = Join-Path $Root "state\chat-soft-pids.json"
$LocalAgentUrl = "http://127.0.0.1:45888"
$ServerBaseUrl = "http://39.106.125.149:3000"

function Show-Http($Name, $Uri) {
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 5
    Write-Host "$Name OK $($response.StatusCode): $($response.Content)"
  } catch {
    Write-Host "$Name FAILED: $($_.Exception.Message)"
  }
}

Write-Host "== PID file =="
if (Test-Path -LiteralPath $PidFile) { Get-Content -LiteralPath $PidFile -Raw } else { Write-Host "No PID file" }

Write-Host "== Local listener =="
$listeners = Get-NetTCPConnection -LocalPort 45888 -State Listen -ErrorAction SilentlyContinue
if ($listeners) {
  $listeners | Select-Object LocalAddress, LocalPort, OwningProcess | Format-Table -AutoSize
  foreach ($listener in $listeners) {
    Get-Process -Id $listener.OwningProcess -ErrorAction SilentlyContinue | Select-Object Id, ProcessName, StartTime, Path | Format-Table -AutoSize
  }
} else {
  Write-Host "No process listening on 127.0.0.1:45888"
}

Write-Host "== Web checks =="
Show-Http "Cloud server /health" "$ServerBaseUrl/health"
Show-Http "Local agent /health" "$LocalAgentUrl/health"
Show-Http "Local opencode agents" "$LocalAgentUrl/api/v1/opencode-agents"

Write-Host "== Log tail =="
$out = Join-Path $Root "logs\local-agent.detached.out.log"
$err = Join-Path $Root "logs\local-agent.detached.err.log"
Write-Host "-- stdout --"
if (Test-Path -LiteralPath $out) { Get-Content -LiteralPath $out -Tail 40 } else { Write-Host "No stdout log" }
Write-Host "-- stderr --"
if (Test-Path -LiteralPath $err) { Get-Content -LiteralPath $err -Tail 40 } else { Write-Host "No stderr log" }
