$ErrorActionPreference = "Stop"
if ($args -contains "--help" -or $args -contains "-h" -or $args -contains "help") {
@"
agent-cli ui-stop

Usage:
  mycli agent-cli ui-stop

Stops the detached Agent CLI Terminal UI.
"@ | Write-Output
    return
}
$WorkspaceConfigPath = "D:\agent_workspace\config\mycli\agent-cli\workspace-config.json"
$WorkspaceConfig = Get-Content -LiteralPath $WorkspaceConfigPath -Raw | ConvertFrom-Json
$StateDir = Join-Path ([string]$WorkspaceConfig.paths.var) "ui"
$PidFile = Join-Path $StateDir "agent-cli-ui-pids.json"
$pids = @()
if (Test-Path -LiteralPath $PidFile) { try { $state = Get-Content -LiteralPath $PidFile -Raw | ConvertFrom-Json; if ($state.pid) { $pids += [int]$state.pid } } catch {} }
$listeners = Get-NetTCPConnection -LocalPort 46030 -State Listen -ErrorAction SilentlyContinue | Select-Object -ExpandProperty OwningProcess -Unique
$pids += @($listeners)
$pids = @($pids | Where-Object { $_ } | Select-Object -Unique)
if (-not $pids -or $pids.Count -eq 0) { Write-Host "Agent CLI UI is not running."; return }
foreach ($pidValue in $pids) { try { Stop-Process -Id $pidValue -Force -ErrorAction Stop; Write-Host "Stopped Agent CLI UI PID=$pidValue" } catch { Write-Host "Failed to stop PID=$pidValue : $($_.Exception.Message)" } }
if (Test-Path -LiteralPath $PidFile) { Remove-Item -LiteralPath $PidFile -Force }
