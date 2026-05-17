$ErrorActionPreference = "Continue"

if ($args -contains '--help' -or $args -contains '-h' -or $args -contains 'help') {
@'
mycli workspace ui open [port]

Start Workspace UI and open it in Edge/default browser.
Default port: 46000.
'@
exit 0
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$Port = if ($args.Count -gt 0 -and $args[0]) { [string]$args[0] } else { "46000" }
$Url = "http://127.0.0.1:$Port"
$StartScript = Join-Path $Root "start.ps1"

& $StartScript $Port

$ready = $false
for ($i = 0; $i -lt 20; $i++) {
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri "$Url/api/snapshot" -TimeoutSec 2
    if ($response.StatusCode -eq 200) {
      $ready = $true
      break
    }
  } catch {}
  Start-Sleep -Milliseconds 500
}

if ($ready) {
  try {
    Start-Process -FilePath "msedge.exe" -ArgumentList @($Url) | Out-Null
    Write-Host "Opened Edge: $Url"
  } catch {
    Start-Process $Url | Out-Null
    Write-Host "Opened browser: $Url"
  }
} else {
  Write-Host "Workspace UI was started, but did not become ready before browser open timeout: $Url"
}
