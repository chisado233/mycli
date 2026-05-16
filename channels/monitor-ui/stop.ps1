$ErrorActionPreference = "Continue"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateDir = Join-Path $Root "state"
$PidFile = Join-Path $StateDir "monitor-ui-pids.json"

if (Test-Path -LiteralPath $PidFile) {
  try {
    $state = Get-Content -LiteralPath $PidFile -Raw | ConvertFrom-Json
    if ($state.pid) {
      Stop-Process -Id ([int]$state.pid) -Force -ErrorAction SilentlyContinue
      Write-Host "Stopped monitor UI PID from state: $($state.pid)"
    }
    if ($state.port) {
      $listeners = Get-NetTCPConnection -LocalPort ([int]$state.port) -State Listen -ErrorAction SilentlyContinue
      foreach ($listener in $listeners) {
        Stop-Process -Id $listener.OwningProcess -Force -ErrorAction SilentlyContinue
        Write-Host "Stopped monitor UI listener PID=$($listener.OwningProcess)"
      }
    }
  } catch {
    Write-Host "Failed to parse monitor UI PID file: $($_.Exception.Message)"
  }

  Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue
  Write-Host "Removed monitor UI PID file."
} else {
  Write-Host "No monitor UI PID file."
}

Write-Host "Channel monitor UI stop requested."
