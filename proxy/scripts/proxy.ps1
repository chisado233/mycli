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

$script:MyCliRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$script:MyCli = Join-Path $script:MyCliRoot "mycli.ps1"
$script:WorkspaceConfigModule = Join-Path $script:MyCliRoot "common\workspace-config.ps1"
. $script:WorkspaceConfigModule
$script:WorkspaceConfig = Get-MyCliWorkspaceConfig -PackagePath 'proxy'
$script:StatePath = Join-Path ([string]$script:WorkspaceConfig.paths.var) "proxy-state.json"
$script:Utf8 = [System.Text.UTF8Encoding]::new($false)

function Write-ProxyError {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Ensure-StateDir {
    $dir = Split-Path -Parent $script:StatePath
    if (-not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
}

function Get-ProxyState {
    if (-not (Test-Path -LiteralPath $script:StatePath)) { return @{ active = "mihomo" } }
    try { return ([IO.File]::ReadAllText($script:StatePath, $script:Utf8) | ConvertFrom-Json -AsHashtable) } catch { return @{ active = "mihomo" } }
}

function Save-ProxyState {
    param([hashtable]$State)
    Ensure-StateDir
    [IO.File]::WriteAllText($script:StatePath, ($State | ConvertTo-Json -Depth 10), $script:Utf8)
}

function Get-Backend {
    param([string[]]$Tokens)
    $state = Get-ProxyState
    $backend = if ($state.ContainsKey("active") -and -not [string]::IsNullOrWhiteSpace([string]$state.active)) { [string]$state.active } else { "mihomo" }
    $rest = @($Tokens)
    $idx = [Array]::IndexOf($rest, "--backend")
    if ($idx -ge 0) {
        if ($idx -ge ($rest.Count - 1)) { Write-ProxyError "--backend requires mihomo or clash." }
        $backend = [string]$rest[$idx + 1]
        $newRest = @()
        for ($i = 0; $i -lt $rest.Count; $i++) {
            if ($i -eq $idx -or $i -eq ($idx + 1)) { continue }
            $newRest += ,([string]$rest[$i])
        }
        $rest = $newRest
    }
    if ($backend -notin @("mihomo", "clash")) { Write-ProxyError "Unsupported backend '$backend'. Expected mihomo or clash." }
    return @{ backend = $backend; rest = $rest }
}

function Invoke-Backend {
    param(
        [string]$Backend,
        [string[]]$BackendArgs
    )
    [object[]]$invokeArgs = @([string]$Backend)
    if ($null -ne $BackendArgs) {
        foreach ($arg in $BackendArgs) { $invokeArgs += [string]$arg }
    }
    & $script:MyCli @invokeArgs
    $exitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $code = if ($null -ne $exitCodeVariable) { $exitCodeVariable.Value } else { 0 }
    if ($null -ne $code -and $code -ne 0) { exit $code }
}

function Show-Help {
@"
mycli proxy

Unified local proxy CLI. Defaults to backend 'mihomo' but can route to 'clash'.

Commands:
  mycli proxy backend
  mycli proxy backend mihomo|clash
  mycli proxy status [--backend mihomo|clash]
  mycli proxy version [--backend mihomo|clash]
  mycli proxy config [--backend mihomo|clash]
  mycli proxy start [--backend mihomo|clash]
  mycli proxy stop [--backend mihomo|clash]
  mycli proxy restart [--backend mihomo|clash]
  mycli proxy selectors [--backend mihomo|clash]
  mycli proxy selector [name] [--backend mihomo|clash]
  mycli proxy proxies [keyword] [--backend mihomo|clash]
  mycli proxy countries [selector] [--backend mihomo|clash]
  mycli proxy country <country> [selector] [--backend mihomo|clash]
  mycli proxy test <proxy> [url] [timeoutMs] [--backend mihomo|clash]
  mycli proxy use <selector> <proxy> [--backend mihomo|clash]
  mycli proxy country-use <selector> <country> [url] [timeoutMs] [--backend mihomo|clash]
  mycli proxy mode
  mycli proxy mode-set rule|global|direct
  mycli proxy providers
  mycli proxy rules [limit]
  mycli proxy check-config
  mycli proxy core-version

Ports:
  mihomo: mixed 127.0.0.1:7891, controller 127.0.0.1:60220
  clash:  mixed 127.0.0.1:7890, controller from Clash config
"@ | Write-Output
}

function Invoke-Main {
    param([string[]]$Tokens)
    $Tokens = if ($null -eq $Tokens) { @() } else { @($Tokens) }
    if ($Tokens.Count -eq 0 -or $Tokens[0] -in @("--help", "help")) { Show-Help; return }

    if ($Tokens[0] -eq "backend") {
        if ($Tokens.Count -eq 1 -or ($Tokens.Count -eq 2 -and [string]::IsNullOrWhiteSpace([string]$Tokens[1])) -or ($Tokens.Count -eq 2 -and $Tokens[1] -eq "backend")) {
            $state = Get-ProxyState
            $active = if ($state.ContainsKey("active") -and -not [string]::IsNullOrWhiteSpace([string]$state.active)) { [string]$state.active } else { "mihomo" }
            Write-Output $active
            return
        }
        $backendValue = if ($Tokens[1] -eq "backend") { [string]$Tokens[2] } else { [string]$Tokens[1] }
        if ($backendValue -notin @("mihomo", "clash")) { Write-ProxyError "Usage: mycli proxy backend mihomo|clash" }
        Save-ProxyState -State @{ active = $backendValue; updatedAt = [DateTime]::UtcNow.ToString("o") }
        Write-Output ("Active proxy backend: {0}" -f $backendValue)
        return
    }

    $parsed = Get-Backend -Tokens $Tokens
    $backend = [string]$parsed.backend
    $rest = @($parsed.rest)

    if ($rest.Count -eq 0) { Show-Help; return }

    switch ($rest[0]) {
        "core-version" {
            if ($backend -eq "mihomo") { Invoke-Backend -Backend $backend -BackendArgs @("core-version") }
            else { Invoke-Backend -Backend $backend -BackendArgs @("version") }
            return
        }
        default {
            Invoke-Backend -Backend $backend -BackendArgs $rest
            return
        }
    }
}

Invoke-Main -Tokens $CommandArgs



