$ErrorActionPreference = "Continue"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PidFile = Join-Path $Root "state\chat-soft-pids.json"

Write-Host "Stopping Chat Soft local agent bridge only. Cloud server is not touched."

if (Test-Path -LiteralPath $PidFile) {
  try {
    $state = Get-Content -LiteralPath $PidFile -Raw | ConvertFrom-Json
    if ($state.localAgentPid) {
      Stop-Process -Id ([int]$state.localAgentPid) -Force -ErrorAction SilentlyContinue
      Write-Host "Stopped PID from state: $($state.localAgentPid)"
    }
  } catch {
    Write-Host "Failed to parse PID file: $($_.Exception.Message)"
  }
}

$listeners = Get-NetTCPConnection -LocalPort 45888 -State Listen -ErrorAction SilentlyContinue
foreach ($listener in $listeners) {
  Stop-Process -Id $listener.OwningProcess -Force -ErrorAction SilentlyContinue
  Write-Host "Stopped listener PID=$($listener.OwningProcess)"
}

Write-Host "Chat Soft local agent stop requested."
