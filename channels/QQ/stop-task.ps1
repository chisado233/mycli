$ErrorActionPreference = "Continue"
$TaskRoot = "\QQChannel\"
Stop-ScheduledTask -TaskPath $TaskRoot -TaskName "QQChannel-Bridge" -ErrorAction SilentlyContinue
Stop-ScheduledTask -TaskPath $TaskRoot -TaskName "QQChannel-NapCat" -ErrorAction SilentlyContinue
Get-Process -Name NapCatWinBootMain -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
Get-Process -Name QQ -ErrorAction SilentlyContinue | Where-Object { $_.Path -like "D:\app\QQNT\QQ.exe" } | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host "QQ channel Task Scheduler tasks stopped."
