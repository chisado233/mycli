$ErrorActionPreference = "Continue"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$MyCliRoot = Split-Path -Parent (Split-Path -Parent $Root)
$WorkspaceConfigModule = Join-Path $MyCliRoot "common\workspace-config.ps1"
. $WorkspaceConfigModule
$WorkspaceConfig = Get-MyCliWorkspaceConfig -PackagePath 'workspace/ui'
$StateDir = [string]$WorkspaceConfig.paths.var
$PidFile = Join-Path $StateDir "workspace-ui-pids.json"

if (!(Test-Path -LiteralPath $PidFile)) {
  Write-Host "Workspace UI state: not started by detached launcher."
  return
}

$state = Get-Content -LiteralPath $PidFile -Raw | ConvertFrom-Json
$pidAlive = $false
if ($state.pid) {
  $pidAlive = [bool](Get-Process -Id ([int]$state.pid) -ErrorAction SilentlyContinue)
}

$healthOk = $false
$healthUrl = "http://127.0.0.1:$($state.port)/api/snapshot"
try {
  $response = Invoke-WebRequest -UseBasicParsing -Uri $healthUrl -TimeoutSec 3
  $healthOk = $response.StatusCode -eq 200
} catch {}

Write-Host "Workspace UI"
Write-Host "  URL: $($state.url)"
Write-Host "  PID: $($state.pid) alive=$pidAlive"
Write-Host "  Health: $healthUrl ok=$healthOk"
Write-Host "  StartedAt: $($state.startedAt)"
Write-Host "  Logs: $($state.logs.stdout) ; $($state.logs.stderr)"
