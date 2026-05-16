$ErrorActionPreference = "Stop"

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$NapcatRoot = Join-Path $Root "napcat"
$Qq = if ($args.Count -ge 1 -and -not [string]::IsNullOrWhiteSpace([string]$args[0])) { [string]$args[0] } else { "3279329186" }

$Launcher = Join-Path $NapcatRoot "NapCatWinBootMain.exe"
$Inject = Join-Path $NapcatRoot "NapCatWinBootHook.dll"
$Main = Join-Path $NapcatRoot "napcat.mjs"
$Load = Join-Path $NapcatRoot "loadNapCat.js"
$PatchPackage = Join-Path $NapcatRoot "qqnt.json"

$reg = Get-ItemProperty -Path "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\QQ" -Name "UninstallString"
$qqPath = Join-Path (Split-Path -Parent $reg.UninstallString.Trim('"')) "QQ.exe"
if (-not (Test-Path -LiteralPath $qqPath)) {
  throw "provided QQ path is invalid: $qqPath"
}

$mainUriPath = $Main.Replace('\', '/')
Set-Content -LiteralPath $Load -Encoding UTF8 -Value "(async () => {await import(`"file:///$mainUriPath`")})()"

$env:NAPCAT_PATCH_PACKAGE = $PatchPackage
$env:NAPCAT_LOAD_PATH = $Load
$env:NAPCAT_INJECT_PATH = $Inject
$env:NAPCAT_LAUNCHER_PATH = $Launcher
$env:NAPCAT_MAIN_PATH = $Main

& $Launcher $qqPath $Inject $Qq
