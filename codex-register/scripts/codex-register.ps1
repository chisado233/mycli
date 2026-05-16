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

$script:ProjectRoot = "D:\agent_workspace\projects\codex-register-main"
$script:ConfigPath = Join-Path $script:ProjectRoot "config.json"
$script:ExampleConfigPath = Join-Path $script:ProjectRoot "config.example.json"
$script:CpaConfigPath = "D:\agent_workspace\projects\CLIProxyAPI\config.yaml"

function Write-CodexRegisterError {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Read-Utf8Text {
    param([string]$Path)
    try {
        return [System.IO.File]::ReadAllText($Path, [System.Text.UTF8Encoding]::new($false))
    } catch {
        Write-CodexRegisterError "Failed to read '$Path'. $($_.Exception.Message)"
    }
}

function Write-Utf8Text {
    param(
        [string]$Path,
        [string]$Content
    )
    try {
        [System.IO.File]::WriteAllText($Path, $Content, [System.Text.UTF8Encoding]::new($true))
    } catch {
        Write-CodexRegisterError "Failed to write '$Path'. $($_.Exception.Message)"
    }
}

function ConvertTo-HashtableDeep {
    param([object]$InputObject)

    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [string] -or $InputObject -is [char] -or $InputObject -is [bool] -or
        $InputObject -is [byte] -or $InputObject -is [int] -or $InputObject -is [long] -or
        $InputObject -is [double] -or $InputObject -is [decimal]) {
        return $InputObject
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = ConvertTo-HashtableDeep $InputObject[$key]
        }
        return $result
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += ,(ConvertTo-HashtableDeep $item)
        }
        return $items
    }

    $properties = @($InputObject.PSObject.Properties)
    if ($properties.Count -gt 0) {
        $result = @{}
        foreach ($prop in $properties) {
            $result[$prop.Name] = ConvertTo-HashtableDeep $prop.Value
        }
        return $result
    }
    return $InputObject
}

function Get-Config {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        Write-CodexRegisterError "config.json not found. Run: mycli codex-register init-config"
    }
    try {
        return ConvertTo-HashtableDeep ((Read-Utf8Text -Path $script:ConfigPath) | ConvertFrom-Json)
    } catch {
        Write-CodexRegisterError "Failed to parse config.json. $($_.Exception.Message)"
    }
}

function Save-Config {
    param([hashtable]$Config)
    $json = $Config | ConvertTo-Json -Depth 20
    Write-Utf8Text -Path $script:ConfigPath -Content ($json + "`r`n")
}

function Invoke-Npm {
    param([string[]]$Args)
    Push-Location $script:ProjectRoot
    try {
        & npm @Args
        exit $LASTEXITCODE
    } finally {
        Pop-Location
    }
}

function Ensure-ProjectRoot {
    if (-not (Test-Path -LiteralPath $script:ProjectRoot)) {
        Write-CodexRegisterError "Project root not found: $script:ProjectRoot"
    }
}

function Get-CpaManagementKey {
    if (-not (Test-Path -LiteralPath $script:CpaConfigPath)) {
        return ""
    }
    $text = Read-Utf8Text -Path $script:CpaConfigPath
    $match = [regex]::Match($text, '(?m)^\s*secret-key:\s*"(?<key>[^"]*)"\s*$')
    if ($match.Success) {
        return $match.Groups['key'].Value
    }
    return ""
}

function Show-Status {
    Ensure-ProjectRoot
    Write-Host "Project: $script:ProjectRoot"
    Write-Host "Config:  $script:ConfigPath"
    Write-Host "Config exists: $(Test-Path -LiteralPath $script:ConfigPath)"
    Write-Host "Node:    $(& node -v 2>$null)"
    Write-Host "npm:     $(& npm -v 2>$null)"
    if (Test-Path -LiteralPath $script:ConfigPath) {
        $config = Get-Config
        Write-Host "provider: $($config.provider)"
        Write-Host "defaultProxyUrl: $($config.defaultProxyUrl)"
        Write-Host "cliproxyApiAutoUploadAuth: $($config.cliproxyApiAutoUploadAuth)"
        Write-Host "cliproxyApiBaseUrl: $($config.cliproxyApiBaseUrl)"
        Write-Host "cliproxyApiManagementKey set: $([bool]$config.cliproxyApiManagementKey)"
        Write-Host "defaultPassword set: $([bool]$config.defaultPassword)"
    }
}

function Initialize-Config {
    Ensure-ProjectRoot
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        if (-not (Test-Path -LiteralPath $script:ExampleConfigPath)) {
            Write-CodexRegisterError "Example config not found: $script:ExampleConfigPath"
        }
        Copy-Item -LiteralPath $script:ExampleConfigPath -Destination $script:ConfigPath
    }
    $config = Get-Config
    if (-not $config.ContainsKey('cliproxyApiBaseUrl') -or -not $config.cliproxyApiBaseUrl) {
        $config.cliproxyApiBaseUrl = "http://localhost:8317"
    }
    $key = Get-CpaManagementKey
    if ($key) {
        $config.cliproxyApiManagementKey = $key
    }
    Save-Config -Config $config
    Write-Host "Prepared config: $script:ConfigPath"
    if ($key) {
        Write-Host "CPA management key copied from CLIProxyAPI config."
    } else {
        Write-Host "CPA management key not found. Fill config.json cliproxyApiManagementKey manually."
    }
}

function Enable-CpaUpload {
    Ensure-ProjectRoot
    $config = Get-Config
    $config.cliproxyApiAutoUploadAuth = $true
    if (-not $config.cliproxyApiBaseUrl) {
        $config.cliproxyApiBaseUrl = "http://localhost:8317"
    }
    $key = Get-CpaManagementKey
    if ($key) {
        $config.cliproxyApiManagementKey = $key
    }
    Save-Config -Config $config
    Write-Host "Enabled CLIProxyAPI auth auto-upload in config.json."
    Write-Host "cliproxyApiBaseUrl: $($config.cliproxyApiBaseUrl)"
    Write-Host "cliproxyApiManagementKey set: $([bool]$config.cliproxyApiManagementKey)"
}

function Test-Proxy {
    Ensure-ProjectRoot
    $config = Get-Config
    if (-not $config.defaultProxyUrl) {
        Write-CodexRegisterError "defaultProxyUrl is empty in config.json."
    }
    try {
        $response = Invoke-WebRequest -Uri "https://auth.openai.com" -Proxy $config.defaultProxyUrl -UseBasicParsing -TimeoutSec 15
        Write-Host "Proxy OK: HTTP $($response.StatusCode) via $($config.defaultProxyUrl)"
    } catch {
        Write-CodexRegisterError "Proxy test failed via '$($config.defaultProxyUrl)'. $($_.Exception.Message)"
    }
}

function Test-Cpa {
    Ensure-ProjectRoot
    $config = Get-Config
    if (-not $config.cliproxyApiManagementKey) {
        Write-CodexRegisterError "cliproxyApiManagementKey is empty in config.json."
    }
    $base = ([string]$config.cliproxyApiBaseUrl).TrimEnd('/')
    try {
        $response = Invoke-WebRequest -Uri "$base/v1/models" -Headers @{ Authorization = "Bearer your-api-key-1" } -UseBasicParsing -TimeoutSec 10
        Write-Host "CLIProxyAPI reachable: HTTP $($response.StatusCode) at $base"
    } catch {
        Write-CodexRegisterError "CLIProxyAPI reachability test failed at '$base'. $($_.Exception.Message)"
    }
}

Ensure-ProjectRoot
$command = if ($CommandArgs.Count -gt 0) { $CommandArgs[0] } else { "help" }
$rest = if ($CommandArgs.Count -gt 1) { $CommandArgs[1..($CommandArgs.Count - 1)] } else { @() }

switch ($command) {
    "help" { Get-Content -LiteralPath (Join-Path (Split-Path -Parent $PSScriptRoot) "README.md"); exit 0 }
    "status" { Show-Status; exit 0 }
    "init-config" { Initialize-Config; exit 0 }
    "enable-cpa-upload" { Enable-CpaUpload; exit 0 }
    "test-proxy" { Test-Proxy; exit 0 }
    "test-cpa" { Test-Cpa; exit 0 }
    "install" { Invoke-Npm @("install") }
    "build" { Invoke-Npm @("run", "build") }
    "dev" { Invoke-Npm (@("run", "dev", "--") + $rest) }
    "start" { Invoke-Npm (@("run", "start", "--") + $rest) }
    "run-once" { Invoke-Npm @("run", "start", "--", "--n", "1") }
    "check" { Invoke-Npm (@("run", "check", "--") + $rest) }
    "check-cpa" { Invoke-Npm (@("run", "check:cpa", "--") + $rest) }
    "batch" { Invoke-Npm (@("run", "batch", "--") + $rest) }
    "native" { Invoke-Npm $rest }
    default { Write-CodexRegisterError "Unknown command '$command'. Run: mycli codex-register --help" }
}
