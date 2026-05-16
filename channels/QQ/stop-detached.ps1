$ErrorActionPreference = "Continue"
$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$StateDir = Join-Path $Root "state"
$PidFile = Join-Path $StateDir "qq-channel-pids.json"
if (Test-Path $PidFile) {
  $s = Get-Content $PidFile -Raw | ConvertFrom-Json
  foreach ($pidValue in @($s.bridgePid, $s.napcatStarterPid)) {
    if ($pidValue) { Stop-Process -Id $pidValue -Force -ErrorAction SilentlyContinue }
  }
}
Get-Process -Name NapCatWinBootMain -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process -Name QQ -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "D:\app\QQNT\QQ.exe" } | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "QQ channel stop requested."
