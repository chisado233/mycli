if ($args -contains "--help" -or $args -contains "-h" -or $args -contains "help") {
@"
agent-cli ui-status

Usage:
  mycli agent-cli ui-status

Shows the detached Agent CLI Terminal UI pid file and health check.
"@ | Write-Output
    return
}
$WorkspaceConfigPath = "D:\agent_workspace\config\mycli\agent-cli\workspace-config.json"
$WorkspaceConfig = Get-Content -LiteralPath $WorkspaceConfigPath -Raw | ConvertFrom-Json
$StateDir = Join-Path ([string]$WorkspaceConfig.paths.var) "ui"
$PidFile = Join-Path $StateDir "agent-cli-ui-pids.json"
if (Test-Path -LiteralPath $PidFile) { Get-Content -LiteralPath $PidFile -Raw | Write-Output } else { Write-Output "No Agent CLI UI pid file found." }
try { Invoke-WebRequest -UseBasicParsing -Uri "http://127.0.0.1:46030/api/snapshot" -TimeoutSec 3 | Select-Object StatusCode,Content | Format-List } catch { Write-Output "Health check failed: $($_.Exception.Message)" }
