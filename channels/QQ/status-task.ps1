$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$TaskRoot = "\QQChannel\"
Write-Host "== Scheduled Tasks =="
Get-ScheduledTask -TaskPath $TaskRoot -ErrorAction SilentlyContinue | Select-Object TaskName,State | Format-Table -AutoSize
Write-Host "== Task Info =="
foreach ($n in @("QQChannel-Bridge", "QQChannel-NapCat")) { Get-ScheduledTaskInfo -TaskPath $TaskRoot -TaskName $n -ErrorAction SilentlyContinue | Select-Object TaskName,LastRunTime,LastTaskResult,NextRunTime | Format-List }
Write-Host "== Processes =="
Get-Process -Name QQ,NapCatWinBootMain,node -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime,Path | Format-Table -AutoSize
Write-Host "== Health =="
try { $r=Invoke-WebRequest -Uri "http://127.0.0.1:6099/webui?token=chisado" -UseBasicParsing -TimeoutSec 5; Write-Host "NapCat WebUI: $($r.StatusCode)" } catch { Write-Host "NapCat WebUI failed: $($_.Exception.Message)" }
try { $tcp=Test-NetConnection -ComputerName 127.0.0.1 -Port 3001 -WarningAction SilentlyContinue; Write-Host "NapCat WS port 3001: $($tcp.TcpTestSucceeded)" } catch {}
Write-Host "== Bridge task log tail =="
$blog = Join-Path $Root "logs\bridge.task.log"
if (Test-Path $blog) { Get-Content $blog -Tail 30 }
Write-Host "== NapCat task log tail =="
$nlog = Join-Path $Root "logs\napcat.task.log"
if (Test-Path $nlog) { Get-Content $nlog -Tail 30 }
