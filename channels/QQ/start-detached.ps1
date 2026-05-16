$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$LogDir = Join-Path $Root "logs"
$StateDir = Join-Path $Root "state"
New-Item -ItemType Directory -Force $LogDir, $StateDir | Out-Null

$PidFile = Join-Path $StateDir "qq-channel-pids.json"
$NapcatOut = Join-Path $LogDir "napcat.detached.out.log"
$NapcatErr = Join-Path $LogDir "napcat.detached.err.log"
$BridgeOut = Join-Path $LogDir "bridge.detached.out.log"
$BridgeErr = Join-Path $LogDir "bridge.detached.err.log"
$Qq = if ($args.Count -ge 1 -and -not [string]::IsNullOrWhiteSpace([string]$args[0])) { [string]$args[0] } else { "3279329186" }

function Start-DetachedProcess($Name, $FilePath, $Arguments, $WorkingDirectory, $StdOut, $StdErr, $WindowStyle = "Hidden") {
  $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -WorkingDirectory $WorkingDirectory -RedirectStandardOutput $StdOut -RedirectStandardError $StdErr -WindowStyle $WindowStyle -PassThru
  Write-Host "$Name PID=$($p.Id)"
  return $p.Id
}

$BridgePid = Start-DetachedProcess "bridge" "node.exe" @("qq-bridge.js") $Root $BridgeOut $BridgeErr "Hidden"
Start-Sleep -Seconds 2
$NapcatStarter = Join-Path $Root "start-napcat-hidden.ps1"
$NapcatPid = Start-DetachedProcess "napcat" "pwsh.exe" @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $NapcatStarter, $Qq) $Root $NapcatOut $NapcatErr "Hidden"

@{
  startedAt = (Get-Date).ToString("o")
  root = $Root
  qq = $Qq
  bridgePid = $BridgePid
  napcatStarterPid = $NapcatPid
  logs = @{
    bridgeOut = $BridgeOut
    bridgeErr = $BridgeErr
    napcatOut = $NapcatOut
    napcatErr = $NapcatErr
  }
} | ConvertTo-Json -Depth 5 | Set-Content -Path $PidFile -Encoding UTF8

Write-Host "QQ channel started detached. PID file: $PidFile"
Write-Host "NapCat WebUI: http://127.0.0.1:6099/webui?token=chisado"
