$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PidFile = Join-Path (Join-Path $Root "state") "cron-ui-pids.json"
if (Test-Path -LiteralPath $PidFile) {
  try {
    $state = Get-Content -LiteralPath $PidFile -Raw | ConvertFrom-Json
    if ($state.pid) { Stop-Process -Id ([int]$state.pid) -Force -ErrorAction SilentlyContinue; Write-Host "Stopped cron UI PID from state: $($state.pid)" }
    if ($state.port) { Get-NetTCPConnection -LocalPort ([int]$state.port) -State Listen -ErrorAction SilentlyContinue | ForEach-Object { Stop-Process -Id $_.OwningProcess -Force -ErrorAction SilentlyContinue; Write-Host "Stopped cron UI listener PID=$($_.OwningProcess)" } }
  } catch { Write-Host "Failed to parse cron UI PID file: $($_.Exception.Message)" }
  Remove-Item -LiteralPath $PidFile -Force -ErrorAction SilentlyContinue; Write-Host "Removed cron UI PID file."
} else { Write-Host "No cron UI PID file." }
Write-Host "Cron UI stop requested."
