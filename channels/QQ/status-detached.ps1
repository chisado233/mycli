$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
$PidFile = Join-Path $Root "state\qq-channel-pids.json"
Write-Host "== PID file =="
if (Test-Path $PidFile) { Get-Content $PidFile -Raw } else { Write-Host "No PID file" }
Write-Host "== Processes =="
Get-Process -Name QQ,NapCatWinBootMain,node -ErrorAction SilentlyContinue | Select-Object Id,ProcessName,StartTime,Path | Format-Table -AutoSize
Write-Host "== Web checks =="
try { $r=Invoke-WebRequest -Uri "http://127.0.0.1:6099/webui?token=chisado" -UseBasicParsing -TimeoutSec 5; Write-Host "NapCat WebUI: $($r.StatusCode)" } catch { Write-Host "NapCat WebUI failed: $($_.Exception.Message)" }
try { $tcp=Test-NetConnection -ComputerName 127.0.0.1 -Port 3001 -WarningAction SilentlyContinue; Write-Host "NapCat WS port 3001: $($tcp.TcpTestSucceeded)" } catch {}
Write-Host "== Bridge log tail =="
$blog = Join-Path $Root "logs\bridge.detached.out.log"
if (Test-Path $blog) { Get-Content $blog -Tail 30 }
Write-Host "== NapCat log tail =="
$nlog = Join-Path $Root "logs\napcat.detached.out.log"
if (Test-Path $nlog) { Get-Content $nlog -Tail 30 }
