$ErrorActionPreference = "Stop"

if ($args -contains '--help' -or $args -contains '-h' -or $args -contains 'help') {
  @'
mycli channels chat-soft start-detached

Start the bundled Chat Soft local agent in the background.

This command may install/build the bundled source and start a local service.
'@
  exit 0
}

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$ProjectRoot = Join-Path $Root "source"
$ServerBaseUrl = "http://39.106.125.149:3000"
$LocalAgentUrl = "http://127.0.0.1:45888"
$LogDir = Join-Path $Root "logs"
$StateDir = Join-Path $Root "state"
$PidFile = Join-Path $StateDir "chat-soft-pids.json"
$StdOut = Join-Path $LogDir "local-agent.detached.out.log"
$StdErr = Join-Path $LogDir "local-agent.detached.err.log"

New-Item -ItemType Directory -Force -Path $LogDir, $StateDir | Out-Null

function Test-HttpOk($Uri) {
  try {
    $response = Invoke-WebRequest -UseBasicParsing -Uri $Uri -TimeoutSec 5
    return @{ ok = $true; status = $response.StatusCode; body = $response.Content }
  } catch {
    return @{ ok = $false; error = $_.Exception.Message }
  }
}

function Get-LocalAgentListener() {
  Get-NetTCPConnection -LocalPort 45888 -State Listen -ErrorAction SilentlyContinue | Select-Object -First 1
}

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
  throw "Bundled Chat Soft source not found: $ProjectRoot"
}

$packageJson = Join-Path $ProjectRoot "package.json"
if (-not (Test-Path -LiteralPath $packageJson)) {
  throw "Bundled Chat Soft source is incomplete; package.json not found: $packageJson"
}

$nodeModules = Join-Path $ProjectRoot "node_modules"
if (-not (Test-Path -LiteralPath $nodeModules)) {
  Write-Host "node_modules not found in bundled source; running pnpm install..."
  $install = Start-Process -FilePath "pnpm.cmd" -ArgumentList @("install") -WorkingDirectory $ProjectRoot -Wait -PassThru -NoNewWindow
  if ($install.ExitCode -ne 0) {
    throw "pnpm install failed in bundled Chat Soft source; exit code $($install.ExitCode)"
  }
}

$agentJs = Join-Path $ProjectRoot "apps\desktop\dist-electron\agent.js"
if (-not (Test-Path -LiteralPath $agentJs)) {
  Write-Host "dist-electron/agent.js not found; building desktop package..."
  $build = Start-Process -FilePath "pnpm.cmd" -ArgumentList @("--filter", "@chat-soft/desktop", "build") -WorkingDirectory $ProjectRoot -Wait -PassThru -NoNewWindow
  if ($build.ExitCode -ne 0) {
    throw "Failed to build @chat-soft/desktop; exit code $($build.ExitCode)"
  }
}

$existingHealth = Test-HttpOk "$LocalAgentUrl/health"
if ($existingHealth.ok) {
  $listener = Get-LocalAgentListener
  Write-Host "Chat Soft local agent is already running."
  if ($listener) { Write-Host "Local agent PID=$($listener.OwningProcess) URL=$LocalAgentUrl" }
} else {
  $env:CHAT_SOFT_SERVER_BASE_URL = $ServerBaseUrl
  $env:CHAT_SOFT_AGENT_CLI_PATH = "D:\agent_workspace\capability-library\mycli\mycli.ps1"
  $env:CHAT_SOFT_AGENT_CLI_AGENT = "opencode/private-assistant"
  $env:CHAT_SOFT_AGENT_CLI_CWD = "D:\agent_workspace"

  $process = Start-Process -FilePath "cmd.exe" `
    -ArgumentList @("/c", "start_opencode_agent.cmd") `
    -WorkingDirectory $ProjectRoot `
    -RedirectStandardOutput $StdOut `
    -RedirectStandardError $StdErr `
    -WindowStyle Hidden `
    -PassThru

  Write-Host "Started Chat Soft local agent launcher PID=$($process.Id)"
}

$health = $null
for ($i = 0; $i -lt 20; $i++) {
  Start-Sleep -Milliseconds 500
  $health = Test-HttpOk "$LocalAgentUrl/health"
  if ($health.ok) { break }
}

$listenerAfter = Get-LocalAgentListener
$remoteHealth = Test-HttpOk "$ServerBaseUrl/health"

@{
  startedAt = (Get-Date).ToString("o")
  packageRoot = $Root
  projectRoot = $ProjectRoot
  serverBaseUrl = $ServerBaseUrl
  localAgentUrl = $LocalAgentUrl
  localAgentPid = if ($listenerAfter) { $listenerAfter.OwningProcess } else { $null }
  logs = @{
    stdout = $StdOut
    stderr = $StdErr
  }
} | ConvertTo-Json -Depth 5 | Set-Content -LiteralPath $PidFile -Encoding UTF8

Write-Host "== Chat Soft detached start result =="
Write-Host "Cloud server health: $(if ($remoteHealth.ok) { $remoteHealth.body } else { 'FAILED: ' + $remoteHealth.error })"
Write-Host "Local agent health: $(if ($health.ok) { $health.body } else { 'FAILED: ' + $health.error })"
if ($listenerAfter) { Write-Host "Local agent listening: 127.0.0.1:45888 PID=$($listenerAfter.OwningProcess)" }
Write-Host "PID file: $PidFile"
Write-Host "Logs: $StdOut ; $StdErr"
