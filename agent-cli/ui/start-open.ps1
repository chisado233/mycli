$ErrorActionPreference = "Stop"
if ($args -contains "--help" -or $args -contains "-h" -or $args -contains "help") {
@"
agent-cli ui-open

Usage:
  mycli agent-cli ui-open [port]

Starts the local Agent CLI Terminal UI and opens it in Edge. Default port: 46030.
"@ | Write-Output
    return
}
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Port = if ($args.Count -gt 0 -and $args[0]) { [string]$args[0] } else { "46030" }
& (Join-Path $Root "start.ps1") $Port
$url = "http://127.0.0.1:$Port"
$edge = "C:\Program Files (x86)\Microsoft\Edge\Application\msedge.exe"
if (Test-Path -LiteralPath $edge) { Start-Process -FilePath $edge -ArgumentList @($url) | Out-Null } else { Start-Process $url | Out-Null }
