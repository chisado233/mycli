[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$script:ProjectRoot = "D:\agent_workspace\projects\CLIProxyAPI"
$script:ConfigPath = Join-Path $script:ProjectRoot "config.yaml"
$script:ExampleConfigPath = Join-Path $script:ProjectRoot "config.example.yaml"
$script:OutLog = Join-Path $script:ProjectRoot "server.out.log"
$script:ErrLog = Join-Path $script:ProjectRoot "server.err.log"
$script:PidFile = Join-Path $script:ProjectRoot ".cliproxyapi.pid"
$script:DefaultBaseUrl = "http://127.0.0.1:8317"
$script:PlainManagementKeyCache = Join-Path $script:ProjectRoot ".management-key.local.txt"

function Write-CpaError {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Read-Utf8Text {
    param([string]$Path)
    try { return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false)) }
    catch { Write-CpaError "Failed to read '$Path'. $($_.Exception.Message)" }
}

function Write-Utf8Text {
    param([string]$Path, [string]$Content)
    try { [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($true)) }
    catch { Write-CpaError "Failed to write '$Path'. $($_.Exception.Message)" }
}

function Ensure-ProjectRoot {
    if (-not (Test-Path -LiteralPath $script:ProjectRoot)) {
        Write-CpaError "Project root not found: $script:ProjectRoot"
    }
}

function Ensure-GoPath {
    $goPath = "C:\Program Files\Go\bin"
    if ((Test-Path -LiteralPath (Join-Path $goPath "go.exe")) -and ($env:Path -notlike "*$goPath*")) {
        $env:Path = "$goPath;$env:Path"
    }
}

function Get-ConfigPort {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) { return 8317 }
    $text = Read-Utf8Text -Path $script:ConfigPath
    $match = [regex]::Match($text, '(?m)^\s*port:\s*(?<port>\d+)\s*$')
    if ($match.Success) { return [int]$match.Groups['port'].Value }
    return 8317
}

function Get-ApiKey {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) { return "your-api-key-1" }
    $text = Read-Utf8Text -Path $script:ConfigPath
    $match = [regex]::Match($text, '(?m)^\s*-\s*"(?<key>[^"]+)"\s*$')
    if ($match.Success) { return $match.Groups['key'].Value }
    return "your-api-key-1"
}

function Initialize-Config {
    Ensure-ProjectRoot
    if (Test-Path -LiteralPath $script:ConfigPath) {
        Write-Host "Config already exists: $script:ConfigPath"
        return
    }
    if (-not (Test-Path -LiteralPath $script:ExampleConfigPath)) {
        Write-CpaError "Example config not found: $script:ExampleConfigPath"
    }
    Copy-Item -LiteralPath $script:ExampleConfigPath -Destination $script:ConfigPath
    Write-Host "Created config: $script:ConfigPath"
}

function New-LocalKey {
    return ([Convert]::ToBase64String([Security.Cryptography.RandomNumberGenerator]::GetBytes(32)).TrimEnd('=').Replace('+','-').Replace('/','_'))
}

function Set-ApiKey {
    param([string]$Key)
    Ensure-ProjectRoot
    Initialize-Config
    if (-not $Key) { $Key = New-LocalKey }
    $text = Read-Utf8Text -Path $script:ConfigPath
    $replacement = "api-keys:`r`n  - `"$Key`""
    if ($text -match '(?ms)^api-keys:\s*\r?\n(?:\s*-\s*"[^"]*"\s*\r?\n?)+') {
        $text = [regex]::Replace($text, '(?ms)^api-keys:\s*\r?\n(?:\s*-\s*"[^"]*"\s*\r?\n?)+', $replacement + "`r`n", 1)
    } else {
        $text += "`r`n$replacement`r`n"
    }
    Write-Utf8Text -Path $script:ConfigPath -Content $text
    Write-Host "Set local API key in config.yaml."
    Write-Host "Authorization header: Bearer $Key"
}

function Get-ManagementKeyStatus {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) { return "missing-config" }
    $text = Read-Utf8Text -Path $script:ConfigPath
    $match = [regex]::Match($text, '(?m)^\s*secret-key:\s*"(?<key>[^"]*)"\s*$')
    if (-not $match.Success -or -not $match.Groups['key'].Value) { return "empty" }
    $key = $match.Groups['key'].Value
    if ($key.StartsWith('$2')) { return "bcrypt-hash-present" }
    return "plaintext-present"
}

function Set-ManagementKey {
    param([string]$Key)
    Ensure-ProjectRoot
    Initialize-Config
    if (-not $Key) { $Key = New-LocalKey }
    $text = Read-Utf8Text -Path $script:ConfigPath
    if ($text -match '(?m)^\s*secret-key:\s*"[^"]*"\s*$') {
        $text = [regex]::Replace($text, '(?m)^\s*secret-key:\s*"[^"]*"\s*$', "  secret-key: `"$Key`"", 1)
    } else {
        $text = $text -replace '(?m)^remote-management:\s*$', "remote-management:`r`n  secret-key: `"$Key`""
    }
    Write-Utf8Text -Path $script:ConfigPath -Content $text
    Write-Utf8Text -Path $script:PlainManagementKeyCache -Content ($Key + "`r`n")
    Write-Host "Set Management API secret-key in config.yaml."
    Write-Host "Plain key cached locally at: $script:PlainManagementKeyCache"
    Write-Host "cliproxyApiManagementKey: $Key"
}

function Show-Status {
    Ensure-ProjectRoot
    Ensure-GoPath
    $port = Get-ConfigPort
    Write-Host "Project: $script:ProjectRoot"
    Write-Host "Config:  $script:ConfigPath"
    Write-Host "Config exists: $(Test-Path -LiteralPath $script:ConfigPath)"
    Write-Host "Go:      $(& go version 2>$null)"
    Write-Host "Port:    $port"
    Write-Host "API key set: $([bool](Get-ApiKey))"
    Write-Host "Management key status: $(Get-ManagementKeyStatus)"
    $connections = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
    Write-Host "Listening on port ${port}: $($connections.Count -gt 0)"
    if (Test-Path -LiteralPath $script:PidFile) {
        Write-Host "PID file: $(Read-Utf8Text -Path $script:PidFile)"
    }
}

function Invoke-Go {
    param([string[]]$Args)
    Ensure-GoPath
    Push-Location $script:ProjectRoot
    try {
        & go @Args
        exit $LASTEXITCODE
    } finally { Pop-Location }
}

function Start-Server {
    param([string[]]$ExtraArgs)
    Ensure-ProjectRoot
    Ensure-GoPath
    Initialize-Config
    $port = Get-ConfigPort
    $connections = @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)
    if ($connections.Count -gt 0) {
        Write-Host "CLIProxyAPI already appears to be listening on port $port."
        $connections | Select-Object LocalAddress, LocalPort, State, OwningProcess
        return
    }
    $env:GOPROXY = if ($env:GOPROXY) { $env:GOPROXY } else { "https://goproxy.cn,direct" }
    $env:GOSUMDB = if ($env:GOSUMDB) { $env:GOSUMDB } else { "sum.golang.google.cn" }
    $args = @("run", "./cmd/server", "--config", "config.yaml", "--no-browser", "--local-model") + $ExtraArgs
    $process = Start-Process -FilePath "go" -ArgumentList $args -WorkingDirectory $script:ProjectRoot -PassThru -RedirectStandardOutput $script:OutLog -RedirectStandardError $script:ErrLog
    Write-Utf8Text -Path $script:PidFile -Content ([string]$process.Id)
    Start-Sleep -Seconds 5
    Write-Host "Started CLIProxyAPI launcher PID: $($process.Id)"
    Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue | Select-Object LocalAddress, LocalPort, State, OwningProcess
}

function Stop-Server {
    Ensure-ProjectRoot
    $ids = New-Object System.Collections.Generic.HashSet[int]
    if (Test-Path -LiteralPath $script:PidFile) {
        $raw = (Read-Utf8Text -Path $script:PidFile).Trim()
        $parsed = 0
        if ([int]::TryParse($raw, [ref]$parsed)) { [void]$ids.Add($parsed) }
    }
    $port = Get-ConfigPort
    foreach ($conn in @(Get-NetTCPConnection -LocalPort $port -State Listen -ErrorAction SilentlyContinue)) {
        [void]$ids.Add([int]$conn.OwningProcess)
    }
    if ($ids.Count -eq 0) {
        Write-Host "No CLIProxyAPI process found from pid file or port $port."
        return
    }
    foreach ($id in $ids) {
        Stop-Process -Id $id -Force -ErrorAction SilentlyContinue
        Write-Host "Stopped PID $id"
    }
    Remove-Item -LiteralPath $script:PidFile -Force -ErrorAction SilentlyContinue
}

function Test-Api {
    Ensure-ProjectRoot
    $port = Get-ConfigPort
    $key = Get-ApiKey
    try {
        $response = Invoke-WebRequest -Uri "http://127.0.0.1:$port/v1/models" -Headers @{ Authorization = "Bearer $key" } -UseBasicParsing -TimeoutSec 10
        Write-Host "API OK: HTTP $($response.StatusCode)"
        Write-Host $response.Content
    } catch {
        Write-CpaError "API test failed. $($_.Exception.Message)"
    }
}

function Show-Logs {
    if (Test-Path -LiteralPath $script:OutLog) { Get-Content -LiteralPath $script:OutLog }
    if (Test-Path -LiteralPath $script:ErrLog) { Get-Content -LiteralPath $script:ErrLog }
}

Ensure-ProjectRoot
$command = if ($CommandArgs.Count -gt 0) { $CommandArgs[0] } else { "help" }
$rest = if ($CommandArgs.Count -gt 1) { $CommandArgs[1..($CommandArgs.Count - 1)] } else { @() }

switch ($command) {
    "help" { Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) "README.md"); exit 0 }
    "status" { Show-Status; exit 0 }
    "init-config" { Initialize-Config; exit 0 }
    "set-api-key" { Set-ApiKey -Key ($(if ($rest.Count -gt 0) { $rest[0] } else { "" })); exit 0 }
    "set-management-key" { Set-ManagementKey -Key ($(if ($rest.Count -gt 0) { $rest[0] } else { "" })); exit 0 }
    "start" { Start-Server -ExtraArgs $rest; exit 0 }
    "stop" { Stop-Server; exit 0 }
    "restart" { Stop-Server; Start-Server -ExtraArgs $rest; exit 0 }
    "test-api" { Test-Api; exit 0 }
    "logs" { Show-Logs; exit 0 }
    "build" { Invoke-Go @("build", "-o", "cli-proxy-api.exe", "./cmd/server") }
    "run" { Invoke-Go (@("run", "./cmd/server") + $rest) }
    "test" { Invoke-Go @("test", "./...") }
    "mod-download" { Invoke-Go @("mod", "download") }
    "docker-up" { Push-Location $script:ProjectRoot; try { & docker compose up -d --build; exit $LASTEXITCODE } finally { Pop-Location } }
    "docker-down" { Push-Location $script:ProjectRoot; try { & docker compose down; exit $LASTEXITCODE } finally { Pop-Location } }
    "native" { Invoke-Go $rest }
    default { Write-CpaError "Unknown command '$command'. Run: mycli cliproxyapi --help" }
}
