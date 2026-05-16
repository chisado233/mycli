$ErrorActionPreference = "Stop"
$TaskRoot = "\QQChannel\"
Start-ScheduledTask -TaskPath $TaskRoot -TaskName "QQChannel-Bridge"
Start-Sleep -Seconds 2
Start-ScheduledTask -TaskPath $TaskRoot -TaskName "QQChannel-NapCat"
Write-Host "QQ channel Task Scheduler tasks started."
