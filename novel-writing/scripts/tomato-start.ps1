param(
    [string]$Addr = "127.0.0.1:18423",
    [string]$Password = "",
    [Alias("save-path", "out")]
    [string]$SavePath = "D:\agent_workspace\capability-library\mycli\novel-writing\collector\books\.tomato-raw",
    [switch]$Restart
)

$ErrorActionPreference = "Stop"

$ProjectRoot = "D:\agent_workspace\capability-library\mycli\novel-writing\collector\Tomato-Novel-Downloader-main"
$ExePath = Join-Path $ProjectRoot "TomatoNovelDownloader-Win64-v2.4.9.exe"
$StateDir = "D:\agent_workspace\capability-library\mycli\novel-writing\collector\state"
$PidFile = Join-Path $StateDir "tomato-server.pid"
if (-not $Addr) { $Addr = "127.0.0.1:18423" }
if (-not $SavePath) { $SavePath = "D:\agent_workspace\capability-library\mycli\novel-writing\collector\books\.tomato-raw" }
$BaseUrl = "http://$Addr"

function Test-TomatoServer {
    param([string]$Url)
    try {
        return Invoke-RestMethod -Uri "$Url/api/status" -TimeoutSec 3
    } catch {
        return $null
    }
}

function Stop-RecordedServer {
    if (-not (Test-Path -LiteralPath $PidFile)) { return }
    $raw = (Get-Content -LiteralPath $PidFile -Raw).Trim()
    if (-not $raw) { return }
    $pidValue = [int]$raw
    $proc = Get-Process -Id $pidValue -ErrorAction SilentlyContinue
    if ($proc) {
        Stop-Process -Id $pidValue -Force
        Start-Sleep -Seconds 1
    }
}

function Set-TomatoConfig {
    param(
        [string]$Url,
        [string]$TargetSavePath
    )

    New-Item -ItemType Directory -Force -Path $TargetSavePath | Out-Null
    $cfg = Invoke-RestMethod -Uri "$Url/api/config/full" -TimeoutSec 10
    $cfg.save_path = $TargetSavePath
    $cfg.novel_format = "txt"
    $cfg.bulk_files = $false
    $cfg.ask_format_after_download = $false
    $cfg.enable_audiobook = $false
    $cfg.enable_segment_comments = $false
    $cfg.max_workers = 1
    if ($cfg.min_wait_time -lt 1000) { $cfg.min_wait_time = 1000 }
    if ($cfg.max_wait_time -lt $cfg.min_wait_time) { $cfg.max_wait_time = $cfg.min_wait_time }
    $body = $cfg | ConvertTo-Json -Depth 30
    Invoke-RestMethod -Uri "$Url/api/config/full" -Method Post -ContentType "application/json; charset=utf-8" -Body $body -TimeoutSec 10 | Out-Null
}

if (-not (Test-Path -LiteralPath $ProjectRoot)) {
    throw "Tomato downloader project not found: $ProjectRoot"
}
if (-not (Test-Path -LiteralPath $ExePath)) {
    throw "Tomato downloader executable not found: $ExePath. Please download the release exe first."
}

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
New-Item -ItemType Directory -Force -Path $SavePath | Out-Null

if ($Restart) {
    Stop-RecordedServer
}

$status = Test-TomatoServer -Url $BaseUrl
if (-not $status) {
    $argList = @("--server")
    if ($Password) { $argList += @("--password", $Password) }

    $oldAddr = [Environment]::GetEnvironmentVariable("TOMATO_WEB_ADDR", "Process")
    $oldPassword = [Environment]::GetEnvironmentVariable("TOMATO_WEB_PASSWORD", "Process")
    try {
        [Environment]::SetEnvironmentVariable("TOMATO_WEB_ADDR", $Addr, "Process")
        if ($Password) { [Environment]::SetEnvironmentVariable("TOMATO_WEB_PASSWORD", $Password, "Process") }
        $proc = Start-Process -FilePath $ExePath -ArgumentList $argList -WorkingDirectory $ProjectRoot -PassThru
        Set-Content -LiteralPath $PidFile -Value $proc.Id -Encoding UTF8
    } finally {
        [Environment]::SetEnvironmentVariable("TOMATO_WEB_ADDR", $oldAddr, "Process")
        [Environment]::SetEnvironmentVariable("TOMATO_WEB_PASSWORD", $oldPassword, "Process")
    }

    for ($i = 0; $i -lt 30; $i++) {
        Start-Sleep -Seconds 1
        $status = Test-TomatoServer -Url $BaseUrl
        if ($status) { break }
    }
}

if (-not $status) {
    throw "Tomato downloader server did not respond at $BaseUrl"
}

Set-TomatoConfig -Url $BaseUrl -TargetSavePath $SavePath
$status = Test-TomatoServer -Url $BaseUrl

[pscustomobject]@{
    status = "ok"
    url = $BaseUrl
    version = $status.version
    savePath = $SavePath
    executable = $ExePath
    pidFile = $PidFile
} | ConvertTo-Json -Depth 6
