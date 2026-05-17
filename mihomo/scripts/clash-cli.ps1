[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
Add-Type -AssemblyName System.Net.Http
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$script:PackageRoot = Split-Path -Parent $PSScriptRoot
$script:WorkspaceConfigModule = Join-Path (Split-Path -Parent $script:PackageRoot) "common\workspace-config.ps1"
. $script:WorkspaceConfigModule
$script:WorkspaceConfig = Get-MyCliWorkspaceConfig -PackagePath 'mihomo'
$script:StateDirectory = [string]$script:WorkspaceConfig.paths.var
$script:AutoStatePath = Join-Path $script:StateDirectory "auto-state.json"
$script:DefaultConfigDirectory = "C:\Users\38188\.config\clash"
$script:ConfigDirectory = $script:DefaultConfigDirectory
$script:ConfigFilePath = Join-Path $script:ConfigDirectory "config.yaml"
$script:AppExePath = ""
$script:CoreExePath = "D:\agent_workspace\tools\mycli\mihomo\mihomo.exe"
$script:RuntimeStatePath = Join-Path $script:StateDirectory "mihomo-runtime.json"
$script:PidPath = Join-Path $script:StateDirectory "mihomo.pid"
$script:LogOutPath = Join-Path ([string]$script:WorkspaceConfig.paths.logs) "mihomo.out.log"
$script:LogErrPath = Join-Path ([string]$script:WorkspaceConfig.paths.logs) "mihomo.err.log"
$script:RuntimeConfigDirectory = Join-Path ([string]$script:WorkspaceConfig.paths.config) "runtime"
$script:RuntimeConfigFilePath = Join-Path $script:RuntimeConfigDirectory "config.yaml"
$script:RuntimeController = "127.0.0.1:60220"
$script:RuntimeMixedPort = 7891
$script:DefaultDelayUrl = "https://www.gstatic.com/generate_204"
$script:DefaultDelayTimeout = 5000
$script:DefaultAutoIntervalSeconds = 60
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:Utf8WithBom = [System.Text.UTF8Encoding]::new($true)
$script:SelectorTypes = @("Selector", "URLTest", "Fallback", "LoadBalance")
$script:CountryMatchers = @(
    @{ name = "香港"; patterns = @("香港", "(?i)\bhk\b", "(?i)hong\s*kong", "(?i)\bhkg\b") },
    @{ name = "日本"; patterns = @("日本", "(?i)\bjp\b", "(?i)japan", "(?i)tokyo", "(?i)osaka") },
    @{ name = "新加坡"; patterns = @("新加坡", "(?i)\bsg\b", "(?i)singapore") },
    @{ name = "台湾"; patterns = @("台湾", "(?i)\btw\b", "(?i)taiwan", "(?i)hinet") },
    @{ name = "韩国"; patterns = @("韩国", "(?i)\bkr\b", "(?i)korea", "(?i)seoul") },
    @{ name = "美国"; patterns = @("美国", "(?i)united\s*states", "(?i)\busa\b", "(?i)\bus\b", "(?i)america", "(?i)\blax\b", "(?i)chicago", "(?i)vegas", "(?i)las\s*vegas", "(?i)\bchi\b") },
    @{ name = "英国"; patterns = @("英国", "(?i)\buk\b", "(?i)united\s*kingdom", "(?i)london") },
    @{ name = "德国"; patterns = @("德国", "(?i)\bde\b", "(?i)germany", "(?i)frankfurt") },
    @{ name = "法国"; patterns = @("法国", "(?i)\bfr\b", "(?i)france", "(?i)paris") },
    @{ name = "荷兰"; patterns = @("荷兰", "(?i)\bnl\b", "(?i)netherlands", "(?i)amsterdam") },
    @{ name = "加拿大"; patterns = @("加拿大", "(?i)\bca\b", "(?i)canada", "(?i)toronto", "(?i)vancouver") },
    @{ name = "澳大利亚"; patterns = @("澳大利亚", "(?i)australia", "(?i)\bau\b", "(?i)sydney", "(?i)melbourne") },
    @{ name = "马来西亚"; patterns = @("马来西亚", "(?i)malaysia", "(?i)\bmy\b", "(?i)kuala\s*lumpur") },
    @{ name = "泰国"; patterns = @("泰国", "(?i)thailand", "(?i)\bth\b", "(?i)bangkok") },
    @{ name = "印度"; patterns = @("印度", "(?i)india", "(?i)\bin\b", "(?i)mumbai", "(?i)delhi") }
)

function Write-ClashCliError {
    param([string]$Message)

    Write-Error $Message
    exit 1
}

function Read-Utf8Text {
    param([string]$Path)

    try {
        return [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
    } catch {
        Write-ClashCliError "Failed to read UTF-8 text from '$Path'. $($_.Exception.Message)"
    }
}

function Write-Utf8Text {
    param(
        [string]$Path,
        [string]$Content,
        [bool]$EmitBom = $true
    )

    try {
        $encoding = if ($EmitBom) { $script:Utf8WithBom } else { $script:Utf8NoBom }
        [System.IO.File]::WriteAllText($Path, $Content, $encoding)
    } catch {
        Write-ClashCliError "Failed to write UTF-8 text to '$Path'. $($_.Exception.Message)"
    }
}

function Ensure-StateDirectory {
    if (-not (Test-Path -LiteralPath $script:StateDirectory)) {
        New-Item -ItemType Directory -Path $script:StateDirectory -Force | Out-Null
    }
}

function Write-StateJson {
    param([object]$Value)

    Ensure-StateDirectory
    $json = $Value | ConvertTo-Json -Depth 20
    Write-Utf8Text -Path $script:AutoStatePath -Content $json
}

function Write-RuntimeStateJson {
    param([object]$Value)
    Ensure-StateDirectory
    $json = $Value | ConvertTo-Json -Depth 20
    Write-Utf8Text -Path $script:RuntimeStatePath -Content $json
}

function Read-RuntimeStateJson {
    if (-not (Test-Path -LiteralPath $script:RuntimeStatePath)) { return $null }
    try { return (Read-Utf8Text -Path $script:RuntimeStatePath) | ConvertFrom-Json } catch { return $null }
}

function Test-ObjectProperty {
    param([object]$Object, [string]$Name)
    return ($null -ne $Object -and ($Object.PSObject.Properties.Name -contains $Name))
}
function Read-StateJson {
    if (-not (Test-Path -LiteralPath $script:AutoStatePath)) {
        return $null
    }

    try {
        return (Read-Utf8Text -Path $script:AutoStatePath) | ConvertFrom-Json
    } catch {
        Write-ClashCliError "Failed to parse auto state file '$($script:AutoStatePath)'. $($_.Exception.Message)"
    }
}

function Show-Help {
    @"
mycli clash

Commands:
  mycli clash status
  mycli clash version
  mycli clash config
  mycli clash mode
  mycli clash mode-set <rule|global|direct>
  mycli clash selectors
  mycli clash selector [name]
  mycli clash use <selector> <proxy>
  mycli clash proxies [keyword]
  mycli clash countries [selector]
  mycli clash country <country> [selector]
  mycli clash country-use <selector> <country> [url] [timeoutMs]
  mycli clash test <proxy> [url] [timeoutMs]
  mycli clash providers
  mycli clash rules [limit]
  mycli clash auto-start <selector> <country> [intervalSec] [timeoutMs] [url]
  mycli clash auto-stop
  mycli clash auto-status
  mycli clash start
  mycli clash stop
  mycli clash restart
  mycli clash check-config
  mycli clash native [clash-core args...]
"@ | Write-Output
}

function Write-MihomoRuntimeConfig {
    param(
        [int]$MixedPort = $script:RuntimeMixedPort,
        [string]$Controller = $script:RuntimeController
    )

    if (-not (Test-Path -LiteralPath $script:RuntimeConfigDirectory)) {
        New-Item -ItemType Directory -Path $script:RuntimeConfigDirectory -Force | Out-Null
    }

    $profileDir = Join-Path $script:DefaultConfigDirectory "profiles"
    $sourceConfigPath = $null
    if (Test-Path -LiteralPath $profileDir) {
        $sourceConfigPath = @(Get-ChildItem -LiteralPath $profileDir -File -Filter "*.yml" | Where-Object { $_.Name -ne "list.yml" } | Sort-Object LastWriteTime -Descending | Select-Object -First 1).FullName
    }
    if ([string]::IsNullOrWhiteSpace($sourceConfigPath)) { $sourceConfigPath = Join-Path $script:DefaultConfigDirectory "config.yaml" }
    if (-not (Test-Path -LiteralPath $sourceConfigPath)) {
        if (Test-Path -LiteralPath $script:RuntimeConfigFilePath) {
            return $script:RuntimeConfigFilePath
        }
        Write-ClashCliError "No source Clash config was found in profiles\list.yml or config.yaml, and no runtime config exists at '$($script:RuntimeConfigFilePath)'."
    }
    $content = Read-Utf8Text -Path $sourceConfigPath
    $content = [regex]::Replace($content, '(?m)^\s*mixed-port\s*:\s*.*$', "mixed-port: $MixedPort")
    $content = [regex]::Replace($content, '(?m)^\s*external-controller\s*:\s*.*$', "external-controller: $Controller")
    $content = [regex]::Replace($content, '(?m)^\s*allow-lan\s*:\s*.*$', "allow-lan: false")
    if ($content -notmatch '(?m)^\s*mixed-port\s*:') { $content = "mixed-port: $MixedPort`r`n" + $content }
    if ($content -notmatch '(?m)^\s*external-controller\s*:') { $content = "external-controller: $Controller`r`n" + $content }
    $sourceMmdb = Join-Path $script:DefaultConfigDirectory "Country.mmdb"
    if (Test-Path -LiteralPath $sourceMmdb) { Copy-Item -LiteralPath $sourceMmdb -Destination (Join-Path $script:RuntimeConfigDirectory "Country.mmdb") -Force }
    Write-Utf8Text -Path $script:RuntimeConfigFilePath -Content $content -EmitBom:$false
    return $script:RuntimeConfigFilePath
}

function Use-MihomoRuntimeConfig {
    $script:ConfigDirectory = $script:RuntimeConfigDirectory
    $script:ConfigFilePath = $script:RuntimeConfigFilePath
}

function Use-MihomoRuntimeConfigIfAvailable {
    if (Test-Path -LiteralPath $script:RuntimeConfigFilePath) {
        Use-MihomoRuntimeConfig
        return $true
    }
    return $false
}

function Get-ConfigMap {
    if (-not (Test-Path -LiteralPath $script:ConfigFilePath)) {
        Write-ClashCliError "Clash config file was not found at '$($script:ConfigFilePath)'."
    }

    $map = @{}
    foreach ($line in @((Read-Utf8Text -Path $script:ConfigFilePath) -split "`r?`n")) {
        if ($line -match '^\s*#') {
            continue
        }
        if ($line -match '^\s*(?<key>[A-Za-z0-9._-]+)\s*:\s*(?<value>.*?)\s*$') {
            $value = [string]$matches["value"]
            $commentIndex = $value.IndexOf(" #")
            if ($commentIndex -ge 0) {
                $value = $value.Substring(0, $commentIndex)
            }
            $value = $value.Trim().Trim('"').Trim("'")
            $map[[string]$matches["key"]] = $value
        }
    }

    return $map
}

function Get-ClashSettings {
    $configMap = Get-ConfigMap
    $controller = if ($configMap.ContainsKey("external-controller") -and -not [string]::IsNullOrWhiteSpace($configMap["external-controller"])) {
        $configMap["external-controller"]
    } else {
        "127.0.0.1:9090"
    }

    return [ordered]@{
        configDirectory = $script:ConfigDirectory
        configFile = $script:ConfigFilePath
        appExe = $script:AppExePath
        coreExe = $script:CoreExePath
        controller = $controller
        secret = if ($configMap.ContainsKey("secret")) { [string]$configMap["secret"] } else { "" }
        mixedPort = if ($configMap.ContainsKey("mixed-port")) { [string]$configMap["mixed-port"] } else { "" }
        allowLan = if ($configMap.ContainsKey("allow-lan")) { [string]$configMap["allow-lan"] } else { "" }
    }
}

function New-HttpClient {
    if ("System.Net.Http.SocketsHttpHandler" -as [type]) {
        $handler = [System.Net.Http.SocketsHttpHandler]::new()
        $handler.UseProxy = $false
        $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
        return [System.Net.Http.HttpClient]::new($handler)
    }

    $legacyHandler = [System.Net.Http.HttpClientHandler]::new()
    $legacyHandler.UseProxy = $false
    $legacyHandler.AutomaticDecompression = [System.Net.DecompressionMethods]::GZip -bor [System.Net.DecompressionMethods]::Deflate
    return [System.Net.Http.HttpClient]::new($legacyHandler)
}

function Invoke-ClashApi {
    param(
        [ValidateSet("GET", "PUT", "PATCH")]
        [string]$Method,
        [string]$Path,
        [object]$Body,
        [switch]$IgnoreFailure
    )

    $settings = Get-ClashSettings
    $client = New-HttpClient

    try {
        $client.Timeout = [TimeSpan]::FromSeconds(15)
        if (-not [string]::IsNullOrWhiteSpace($settings.secret)) {
            $client.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new("Bearer", $settings.secret)
        }

        $request = [System.Net.Http.HttpRequestMessage]::new([System.Net.Http.HttpMethod]::new($Method), ("http://{0}{1}" -f $settings.controller, $Path))
        if ($PSBoundParameters.ContainsKey("Body") -and $null -ne $Body) {
            $json = $Body | ConvertTo-Json -Depth 20 -Compress
            $request.Content = [System.Net.Http.StringContent]::new($json, [System.Text.Encoding]::UTF8, "application/json")
        }

        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        $content = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            $statusCode = [int]$response.StatusCode
            $reason = [string]$response.ReasonPhrase
            $message = "Clash API request failed: $statusCode $reason. $content"
            if ($IgnoreFailure) {
                return [pscustomobject]@{
                    success = $false
                    message = $message
                    data = $null
                }
            }
            Write-ClashCliError $message
        }

        $data = $null
        if (-not [string]::IsNullOrWhiteSpace($content)) {
            $data = $content | ConvertFrom-Json
        }

        if ($IgnoreFailure) {
            return [pscustomobject]@{
                success = $true
                message = ""
                data = $data
            }
        }

        return $data
    } catch {
        $message = "Failed to call Clash API at '$($settings.controller)'. $($_.Exception.Message)"
        if ($IgnoreFailure) {
            return [pscustomobject]@{
                success = $false
                message = $message
                data = $null
            }
        }
        Write-ClashCliError $message
    } finally {
        $client.Dispose()
    }
}

function Get-PathSegment {
    param([string]$Value)

    return [System.Uri]::EscapeDataString($Value)
}

function Get-ProxySnapshot {
    return Invoke-ClashApi -Method GET -Path "/proxies"
}

function Get-SelectorProxy {
    param(
        [psobject]$Snapshot,
        [string]$SelectorName
    )

    $property = $Snapshot.proxies.PSObject.Properties[$SelectorName]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Get-LeafProxyRows {
    param([psobject]$Snapshot)

    if ($null -eq $Snapshot) {
        $Snapshot = Get-ProxySnapshot
    }

    $rows = @()
    foreach ($property in @($Snapshot.proxies.PSObject.Properties)) {
        $proxy = $property.Value
        $typeName = [string]$proxy.type
        if ($typeName -in ($script:SelectorTypes + @("Direct", "Reject"))) {
            continue
        }

        $history = @()
        if ($null -ne $proxy.history) {
            $history = @($proxy.history)
        }

        $lastDelayValue = if ($history.Count -gt 0) { [int]$history[-1].delay } else { -1 }
        $rows += ,([pscustomobject][ordered]@{
            name = [string]$proxy.name
            type = $typeName
            alive = [bool]$proxy.alive
            delay = $lastDelayValue
        })
    }

    return @($rows)
}

function Get-SelectorRows {
    param([psobject]$Snapshot)

    if ($null -eq $Snapshot) {
        $Snapshot = Get-ProxySnapshot
    }

    $rows = @()
    foreach ($property in @($Snapshot.proxies.PSObject.Properties)) {
        $proxy = $property.Value
        $typeName = [string]$proxy.type
        if ($typeName -notin $script:SelectorTypes) {
            continue
        }

        $choices = @()
        if ($null -ne $proxy.all) {
            $choices = @($proxy.all)
        }

        $rows += ,([pscustomobject][ordered]@{
            name = [string]$proxy.name
            type = $typeName
            now = if ($null -ne $proxy.now) { [string]$proxy.now } else { "" }
            count = $choices.Count
        })
    }

    return @($rows)
}

function Resolve-CountryName {
    param([string]$ProxyName)

    foreach ($matcher in $script:CountryMatchers) {
        foreach ($pattern in @($matcher.patterns)) {
            if ($ProxyName -match $pattern) {
                return [string]$matcher.name
            }
        }
    }

    return $null
}

function Normalize-CountryInput {
    param([string]$Country)

    $trimmed = [string]$Country
    if ([string]::IsNullOrWhiteSpace($trimmed)) {
        Write-ClashCliError "Country cannot be empty."
    }

    $resolved = Resolve-CountryName -ProxyName $trimmed
    if ($null -ne $resolved) {
        return $resolved
    }

    return $trimmed.Trim()
}

function Get-SelectorChoiceSet {
    param(
        [psobject]$Snapshot,
        [string]$SelectorName
    )

    $selector = Get-SelectorProxy -Snapshot $Snapshot -SelectorName $SelectorName
    if ($null -eq $selector) {
        Write-ClashCliError "Selector '$SelectorName' was not found."
    }

    $choiceSet = @{}
    foreach ($choice in @($selector.all)) {
        $choiceSet[[string]$choice] = $true
    }
    return $choiceSet
}

function Get-CountryProxyRows {
    param(
        [string]$Country,
        [string]$SelectorName
    )

    $snapshot = Get-ProxySnapshot
    $leafRows = Get-LeafProxyRows -Snapshot $snapshot
    $targetCountry = if ($PSBoundParameters.ContainsKey("Country") -and -not [string]::IsNullOrWhiteSpace($Country)) {
        Normalize-CountryInput -Country $Country
    } else {
        $null
    }

    $choiceSet = $null
    if ($PSBoundParameters.ContainsKey("SelectorName") -and -not [string]::IsNullOrWhiteSpace($SelectorName)) {
        $choiceSet = Get-SelectorChoiceSet -Snapshot $snapshot -SelectorName $SelectorName
    }

    $rows = @()
    foreach ($row in $leafRows) {
        $countryName = Resolve-CountryName -ProxyName $row.name
        if ($null -eq $countryName) {
            continue
        }
        if ($null -ne $targetCountry -and $countryName -ne $targetCountry) {
            continue
        }
        if ($null -ne $choiceSet -and -not $choiceSet.ContainsKey($row.name)) {
            continue
        }

        $rows += ,([pscustomobject][ordered]@{
            name = $row.name
            type = $row.type
            alive = $row.alive
            delay = $row.delay
            country = $countryName
        })
    }

    return @($rows | Sort-Object country, name)
}

function Measure-ProxyDelaySafe {
    param(
        [string]$ProxyName,
        [string]$Url = $script:DefaultDelayUrl,
        [int]$TimeoutMs = $script:DefaultDelayTimeout
    )

    $escapedName = Get-PathSegment -Value $ProxyName
    $escapedUrl = [System.Uri]::EscapeDataString($Url)
    $response = Invoke-ClashApi -Method GET -Path ("/proxies/{0}/delay?url={1}&timeout={2}" -f $escapedName, $escapedUrl, $TimeoutMs) -IgnoreFailure
    if (-not $response.success -or $null -eq $response.data) {
        return [pscustomobject]@{
            success = $false
            delay = $null
            message = $response.message
        }
    }

    $delayValue = [int]$response.data.delay
    if ($delayValue -le 0) {
        return [pscustomobject]@{
            success = $false
            delay = $delayValue
            message = "Delay result is 0."
        }
    }

    return [pscustomobject]@{
        success = $true
        delay = $delayValue
        message = ""
    }
}

function Get-BestCountryProxy {
    param(
        [string]$SelectorName,
        [string]$Country,
        [string]$Url = $script:DefaultDelayUrl,
        [int]$TimeoutMs = $script:DefaultDelayTimeout
    )

    $rows = Get-CountryProxyRows -Country $Country -SelectorName $SelectorName
    $measured = @()
    foreach ($row in $rows) {
        $probe = Measure-ProxyDelaySafe -ProxyName $row.name -Url $Url -TimeoutMs $TimeoutMs
        $measured += ,([pscustomobject][ordered]@{
            name = $row.name
            type = $row.type
            country = $row.country
            alive = $row.alive
            historyDelay = $row.delay
            measuredDelay = $probe.delay
            success = $probe.success
            message = $probe.message
        })
    }

    $best = $measured |
        Where-Object { $_.success } |
        Sort-Object measuredDelay, name |
        Select-Object -First 1

    if ($null -eq $best) {
        $best = $measured |
            Where-Object { $_.alive -and $_.historyDelay -gt 0 } |
            Sort-Object historyDelay, name |
            Select-Object -First 1
    }

    return [pscustomobject][ordered]@{
        selector = $SelectorName
        country = Normalize-CountryInput -Country $Country
        url = $Url
        timeoutMs = $TimeoutMs
        candidates = @($measured)
        best = $best
    }
}

function Set-SelectorProxy {
    param(
        [string]$SelectorName,
        [string]$ProxyName,
        [switch]$Quiet
    )

    $escapedSelector = Get-PathSegment -Value $SelectorName
    Invoke-ClashApi -Method PUT -Path ("/proxies/{0}" -f $escapedSelector) -Body @{ name = $ProxyName } | Out-Null
    if (-not $Quiet) {
        Show-Selector -SelectorName $SelectorName
    }
}

function Get-MihomoProcess {
    if (Test-Path -LiteralPath $script:PidPath) {
        $pidText = (Read-Utf8Text -Path $script:PidPath).Trim()
        $pidValue = 0
        if ([int]::TryParse($pidText, [ref]$pidValue)) {
            try {
                $process = Get-Process -Id $pidValue -ErrorAction Stop
                $path = $null
                try { $path = $process.Path } catch { $path = $null }
                if ($path -eq $script:CoreExePath -or $process.ProcessName -like "mihomo*") {
                    return $process
                }
            } catch {
                return $null
            }
        }
    }

    foreach ($process in @(Get-Process -Name "mihomo" -ErrorAction SilentlyContinue)) {
        try {
            if ($process.Path -eq $script:CoreExePath) { return $process }
        } catch {
            return $process
        }
    }
    return $null
}
function Get-ClashProcesses {
    $targets = @()
    foreach ($process in @(Get-Process -ErrorAction SilentlyContinue)) {
        $path = $null
        try {
            $path = $process.Path
        } catch {
            $path = $null
        }

        if ($process.ProcessName -like "mihomo*" -or
            $path -eq $script:CoreExePath) {
            $targets += ,$process
        }
    }
    return @($targets | Sort-Object ProcessName, Id -Unique)
}

function Get-AutoWorkerProcess {
    $state = Read-StateJson
    if ($null -eq $state -or $null -eq $state.pid) {
        return $null
    }

    try {
        return Get-Process -Id ([int]$state.pid) -ErrorAction Stop
    } catch {
        return $null
    }
}

function Update-AutoState {
    param([hashtable]$State)

    Write-StateJson -Value ([pscustomobject]$State)
}

function Show-Status {
    $settings = Get-ClashSettings
    $version = Invoke-ClashApi -Method GET -Path "/version"
    $runtimeConfig = Invoke-ClashApi -Method GET -Path "/configs"
    $snapshot = Get-ProxySnapshot
    $selectors = Get-SelectorRows -Snapshot $snapshot
    $globalSelector = $selectors | Where-Object { $_.name -eq "GLOBAL" } | Select-Object -First 1
    $processes = Get-ClashProcesses
    $autoState = Read-StateJson
    $autoProcess = Get-AutoWorkerProcess

    Write-Output ("Version: {0}" -f [string]$version.version)
    if ($version.PSObject.Properties.Name -contains "premium") { Write-Output ("Premium: {0}" -f [string]$version.premium) }
    Write-Output ("Controller: {0}" -f [string]$settings.controller)
    Write-Output ("Mixed Port: {0}" -f [string]$runtimeConfig.'mixed-port')
    Write-Output ("Mode: {0}" -f [string]$runtimeConfig.mode)
    if ($null -ne $globalSelector) {
        Write-Output ("GLOBAL: {0}" -f [string]$globalSelector.now)
    }
    Write-Output ("Selectors: {0}" -f [string]@($selectors).Count)
    Write-Output ("Processes: {0}" -f [string]@($processes).Count)
    if ($null -ne $autoState) {
        $autoStatus = if ($null -ne $autoProcess) { "running" } else { "stopped" }
        Write-Output ("Auto: {0}" -f $autoStatus)
        if (Test-ObjectProperty -Object $autoState -Name "selector" -and $null -ne $autoState.selector) {
            Write-Output ("Auto Selector: {0}" -f [string]$autoState.selector)
        }
        if (Test-ObjectProperty -Object $autoState -Name "country" -and $null -ne $autoState.country) {
            Write-Output ("Auto Country: {0}" -f [string]$autoState.country)
        }
    }
}

function Show-Version {
    $apiVersion = $null
    try {
        $apiVersion = Invoke-ClashApi -Method GET -Path "/version"
    } catch {
        $apiVersion = $null
    }
    $coreVersion = & $script:CoreExePath -v 2>&1

    if ($null -ne $apiVersion) {
        Write-Output ("API Version: {0}" -f [string]$apiVersion.version)
        if ($apiVersion.PSObject.Properties.Name -contains "premium") { Write-Output ("Premium: {0}" -f [string]$apiVersion.premium) }
    } else {
        Write-Output "API Version: unavailable (mihomo is not running or controller is unreachable)"
    }
    if ($LASTEXITCODE -eq 0 -and -not [string]::IsNullOrWhiteSpace(($coreVersion | Out-String))) {
        Write-Output ("Core Version: {0}" -f (($coreVersion | Out-String).Trim()))
    }
}

function Show-Config {
    $settings = Get-ClashSettings
    $runtimeConfig = Invoke-ClashApi -Method GET -Path "/configs"

    Write-Output ("Config Directory: {0}" -f [string]$settings.configDirectory)
    Write-Output ("Config File: {0}" -f [string]$settings.configFile)
    Write-Output ("App Exe: {0}" -f [string]$settings.appExe)
    Write-Output ("Core Exe: {0}" -f [string]$settings.coreExe)
    Write-Output ("Controller: {0}" -f [string]$settings.controller)
    Write-Output ("Secret Present: {0}" -f (-not [string]::IsNullOrWhiteSpace($settings.secret)))
    Write-Output ("Mixed Port: {0}" -f [string]$runtimeConfig.'mixed-port')
    Write-Output ("Allow LAN: {0}" -f [string]$runtimeConfig.'allow-lan')
    Write-Output ("Mode: {0}" -f [string]$runtimeConfig.mode)
    Write-Output ("Log Level: {0}" -f [string]$runtimeConfig.'log-level')
}

function Show-Mode {
    $runtimeConfig = Invoke-ClashApi -Method GET -Path "/configs"
    Write-Output ([string]$runtimeConfig.mode)
}

function Set-Mode {
    param([string]$Mode)

    if ($Mode -notin @("rule", "global", "direct")) {
        Write-ClashCliError "Unsupported mode '$Mode'. Expected one of: rule, global, direct."
    }

    Invoke-ClashApi -Method PATCH -Path "/configs" -Body @{ mode = $Mode } | Out-Null
    Show-Mode
}

function Show-Selectors {
    foreach ($row in @(Get-SelectorRows | Sort-Object name)) {
        Write-Output ("{0} | type={1} | now={2} | choices={3}" -f $row.name, $row.type, $row.now, $row.count)
    }
}

function Show-Selector {
    param([string]$SelectorName = "GLOBAL")

    $snapshot = Get-ProxySnapshot
    $proxy = Get-SelectorProxy -Snapshot $snapshot -SelectorName $SelectorName
    if ($null -eq $proxy) {
        Write-ClashCliError "Selector '$SelectorName' was not found."
    }

    Write-Output ("Name: {0}" -f [string]$proxy.name)
    Write-Output ("Type: {0}" -f [string]$proxy.type)
    if ($null -ne $proxy.now) {
        Write-Output ("Current: {0}" -f [string]$proxy.now)
    }
    Write-Output "Choices:"
    foreach ($choice in @($proxy.all)) {
        Write-Output ("  {0}" -f [string]$choice)
    }
}

function Show-Proxies {
    param([string]$Keyword)

    $rows = Get-LeafProxyRows | Sort-Object name
    if (-not [string]::IsNullOrWhiteSpace($Keyword)) {
        $rows = @($rows | Where-Object { $_.name -like "*$Keyword*" })
    }

    foreach ($row in $rows) {
        $delayDisplay = if ($row.delay -gt 0) { [string]$row.delay } else { "-" }
        Write-Output ("{0} | type={1} | alive={2} | delay={3}" -f $row.name, $row.type, $row.alive, $delayDisplay)
    }
}

function Show-Countries {
    param([string]$SelectorName)

    $rows = if (-not [string]::IsNullOrWhiteSpace($SelectorName)) {
        Get-CountryProxyRows -SelectorName $SelectorName
    } else {
        Get-CountryProxyRows
    }

    if (@($rows).Count -eq 0) {
        Write-Output "No country-classified proxies were found."
        return
    }

    foreach ($group in @($rows | Group-Object country | Sort-Object Name)) {
        $aliveCount = @($group.Group | Where-Object { $_.alive }).Count
        Write-Output ("{0} | total={1} | alive={2}" -f $group.Name, $group.Count, $aliveCount)
    }
}

function Show-Country {
    param(
        [string]$Country,
        [string]$SelectorName
    )

    $rows = if (-not [string]::IsNullOrWhiteSpace($SelectorName)) {
        Get-CountryProxyRows -Country $Country -SelectorName $SelectorName
    } else {
        Get-CountryProxyRows -Country $Country
    }

    if (@($rows).Count -eq 0) {
        Write-Output ("No proxies found for country '{0}'." -f (Normalize-CountryInput -Country $Country))
        return
    }

    foreach ($row in $rows | Sort-Object @{ Expression = "alive"; Descending = $true }, @{ Expression = "delay"; Descending = $false }, name) {
        $delayDisplay = if ($row.delay -gt 0) { [string]$row.delay } else { "-" }
        Write-Output ("{0} | alive={1} | delay={2} | type={3}" -f $row.name, $row.alive, $delayDisplay, $row.type)
    }
}

function Use-FastestCountryProxy {
    param(
        [string]$SelectorName,
        [string]$Country,
        [string]$Url = $script:DefaultDelayUrl,
        [int]$TimeoutMs = $script:DefaultDelayTimeout,
        [switch]$Quiet
    )

    $selection = Get-BestCountryProxy -SelectorName $SelectorName -Country $Country -Url $Url -TimeoutMs $TimeoutMs
    if ($null -eq $selection.best) {
        Write-ClashCliError "No usable proxy was found for country '$($selection.country)' in selector '$SelectorName'."
    }

    Set-SelectorProxy -SelectorName $SelectorName -ProxyName $selection.best.name -Quiet:$Quiet
    if (-not $Quiet) {
        Write-Output ("Switched {0} to {1} ({2} ms)." -f $SelectorName, $selection.best.name, [string]$selection.best.measuredDelay)
    }

    return $selection
}

function Test-ProxyDelay {
    param(
        [string]$ProxyName,
        [string]$Url = $script:DefaultDelayUrl,
        [int]$TimeoutMs = $script:DefaultDelayTimeout
    )

    $result = Measure-ProxyDelaySafe -ProxyName $ProxyName -Url $Url -TimeoutMs $TimeoutMs
    if (-not $result.success) {
        Write-ClashCliError "Delay test failed for '$ProxyName'. $($result.message)"
    }

    Write-Output ("Proxy: {0}" -f $ProxyName)
    Write-Output ("URL: {0}" -f $Url)
    Write-Output ("Delay: {0} ms" -f [string]$result.delay)
}

function Show-Providers {
    $providerResponse = Invoke-ClashApi -Method GET -Path "/providers/proxies"
    foreach ($property in @($providerResponse.providers.PSObject.Properties | Sort-Object Name)) {
        $provider = $property.Value
        $proxies = @()
        if ($null -ne $provider.proxies) {
            $proxies = @($provider.proxies)
        }
        Write-Output ("{0} | type={1} | proxies={2}" -f $provider.name, $provider.vehicleType, $proxies.Count)
    }
}

function Show-Rules {
    param([int]$Limit = 20)

    if ($Limit -lt 1) {
        Write-ClashCliError "Rule limit must be greater than 0."
    }

    $ruleResponse = Invoke-ClashApi -Method GET -Path "/rules"
    $rules = @($ruleResponse.rules | Select-Object -First $Limit)
    $index = 1
    foreach ($rule in $rules) {
        Write-Output ("{0}. {1} | {2} | {3}" -f $index, [string]$rule.type, [string]$rule.payload, [string]$rule.proxy)
        $index += 1
    }
}

function Start-ClashApp {
    if (-not (Test-Path -LiteralPath $script:CoreExePath)) {
        Write-ClashCliError "Mihomo executable was not found at '$($script:CoreExePath)'."
    }

    $existing = Get-MihomoProcess
    if ($null -ne $existing) {
        Write-Output ("Mihomo is already running. PID: {0}" -f $existing.Id)
        Show-Status
        return
    }

    $logDir = Split-Path -Parent $script:LogOutPath
    if (-not (Test-Path -LiteralPath $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
    Ensure-StateDirectory

    Write-MihomoRuntimeConfig | Out-Null
    Use-MihomoRuntimeConfig
    $args = @("-d", $script:ConfigDirectory, "-f", $script:ConfigFilePath)
    $process = Start-Process -FilePath $script:CoreExePath -ArgumentList $args -WindowStyle Hidden -PassThru -RedirectStandardOutput $script:LogOutPath -RedirectStandardError $script:LogErrPath
    Write-Utf8Text -Path $script:PidPath -Content ([string]$process.Id) -EmitBom:$false
    Write-RuntimeStateJson -Value ([ordered]@{
        pid = $process.Id
        exe = $script:CoreExePath
        configDirectory = $script:ConfigDirectory
        configFile = $script:ConfigFilePath
        startedAtUtc = [DateTime]::UtcNow.ToString("o")
        stdout = $script:LogOutPath
        stderr = $script:LogErrPath
    })

    Start-Sleep -Seconds 2
    Show-Status
}

function Stop-ClashApp {
    $process = Get-MihomoProcess
    if ($null -eq $process) {
        Write-Output "Mihomo is not running."
        if (Test-Path -LiteralPath $script:PidPath) { Remove-Item -LiteralPath $script:PidPath -Force }
        return
    }

    Stop-Process -Id $process.Id -Force
    if (Test-Path -LiteralPath $script:PidPath) { Remove-Item -LiteralPath $script:PidPath -Force }
    Write-Output ("Stopped Mihomo process. PID: {0}" -f [string]$process.Id)
}

function Test-ClashApiReady {
    param([int]$TimeoutSeconds = 10)

    $deadline = [DateTime]::UtcNow.AddSeconds($TimeoutSeconds)
    while ([DateTime]::UtcNow -lt $deadline) {
        $result = Invoke-ClashApi -Method GET -Path "/version" -IgnoreFailure
        if ($result.success) { return $true }
        Start-Sleep -Milliseconds 500
    }
    return $false
}

function Ensure-MihomoRunning {
    Use-MihomoRuntimeConfigIfAvailable | Out-Null
    if ($null -eq (Get-MihomoProcess)) {
        Start-ClashApp | Out-Null
    }
    Use-MihomoRuntimeConfigIfAvailable | Out-Null
    if (-not (Test-ClashApiReady -TimeoutSeconds 10)) {
        Write-ClashCliError "Mihomo controller is not reachable at '$($script:RuntimeController)'. Run 'mycli mihomo start' and check '$($script:LogErrPath)'."
    }
}

function Restart-ClashApp {
    Stop-ClashApp
    Start-Sleep -Seconds 2
    Start-ClashApp
}

function Test-ConfigFile {
    if (-not (Test-Path -LiteralPath $script:CoreExePath)) {
        Write-ClashCliError "Mihomo executable was not found at '$($script:CoreExePath)'."
    }

    & $script:CoreExePath -t -d $script:ConfigDirectory -f $script:ConfigFilePath
    $exitCode = $LASTEXITCODE
    if ($exitCode -ne 0) {
        exit $exitCode
    }
}

function Invoke-NativeCore {
    param([object[]]$NativeArgs)

    if (-not (Test-Path -LiteralPath $script:CoreExePath)) {
        Write-ClashCliError "Mihomo executable was not found at '$($script:CoreExePath)'."
    }

    $argList = @()
    foreach ($arg in @($NativeArgs)) {
        $text = [string]$arg
        if (-not [string]::IsNullOrWhiteSpace($text)) {
            $argList += ,$text
        }
    }

    if ($argList.Count -eq 0 -or $argList -contains "--help" -or $argList -contains "help") {
        & $script:CoreExePath -h
    } else {
        & $script:CoreExePath @argList
    }
    $exitCode = $LASTEXITCODE
    if ($null -ne $exitCode) {
        exit $exitCode
    }
}

function Start-AutoSwitch {
    param(
        [string]$SelectorName,
        [string]$Country,
        [int]$IntervalSeconds = $script:DefaultAutoIntervalSeconds,
        [int]$TimeoutMs = $script:DefaultDelayTimeout,
        [string]$Url = $script:DefaultDelayUrl
    )

    if ($IntervalSeconds -lt 5) {
        Write-ClashCliError "Auto interval must be at least 5 seconds."
    }

    $countryName = Normalize-CountryInput -Country $Country
    $existing = Get-AutoWorkerProcess
    if ($null -ne $existing) {
        Stop-AutoSwitch | Out-Null
        Start-Sleep -Seconds 1
    }

    $hostExe = (Get-Process -Id $PID).Path
    $scriptPath = $PSCommandPath
    $arguments = @(
        "-NoProfile",
        "-ExecutionPolicy", "Bypass",
        "-File", $scriptPath,
        "auto-worker",
        $SelectorName,
        $countryName,
        [string]$IntervalSeconds,
        [string]$TimeoutMs,
        $Url
    )

    Update-AutoState -State ([ordered]@{
        enabled = $true
        running = $false
        pid = $null
        selector = $SelectorName
        country = $countryName
        intervalSeconds = $IntervalSeconds
        timeoutMs = $TimeoutMs
        url = $Url
        startedAtUtc = [DateTime]::UtcNow.ToString("o")
        lastRunUtc = $null
        lastSwitchUtc = $null
        currentProxy = $null
        bestProxy = $null
        bestDelay = $null
        message = "Starting auto worker."
    })

    $process = Start-Process -FilePath $hostExe -ArgumentList $arguments -WindowStyle Hidden -PassThru
    Start-Sleep -Milliseconds 500

    Update-AutoState -State ([ordered]@{
        enabled = $true
        running = $true
        pid = $process.Id
        selector = $SelectorName
        country = $countryName
        intervalSeconds = $IntervalSeconds
        timeoutMs = $TimeoutMs
        url = $Url
        startedAtUtc = [DateTime]::UtcNow.ToString("o")
        lastRunUtc = $null
        lastSwitchUtc = $null
        currentProxy = $null
        bestProxy = $null
        bestDelay = $null
        message = "Auto worker is running."
    })

    Show-AutoStatus
}

function Stop-AutoSwitch {
    $state = Read-StateJson
    $process = Get-AutoWorkerProcess

    if ($null -eq $state -and $null -eq $process) {
        Write-Output "Auto switch is not running."
        return
    }

    if ($null -ne $process) {
        Stop-Process -Id $process.Id -Force
    }

    if ($null -ne $state) {
        Update-AutoState -State ([ordered]@{
            enabled = $false
            running = $false
            pid = $null
            selector = $state.selector
            country = $state.country
            intervalSeconds = $state.intervalSeconds
            timeoutMs = $state.timeoutMs
            url = $state.url
            startedAtUtc = $state.startedAtUtc
            stoppedAtUtc = [DateTime]::UtcNow.ToString("o")
            lastRunUtc = $state.lastRunUtc
            lastSwitchUtc = $state.lastSwitchUtc
            currentProxy = $state.currentProxy
            bestProxy = $state.bestProxy
            bestDelay = $state.bestDelay
            message = "Auto worker stopped."
        })
    }

    Write-Output "Auto switch stopped."
}

function Show-AutoStatus {
    $state = Read-StateJson
    if ($null -eq $state) {
        Write-Output "Auto switch has not been configured."
        return
    }

    $process = Get-AutoWorkerProcess
    Write-Output ("Enabled: {0}" -f [string]$state.enabled)
    Write-Output ("Running: {0}" -f ($null -ne $process))
    Write-Output ("Selector: {0}" -f [string]$state.selector)
    Write-Output ("Country: {0}" -f [string]$state.country)
    Write-Output ("Interval Seconds: {0}" -f [string]$state.intervalSeconds)
    Write-Output ("Timeout Ms: {0}" -f [string]$state.timeoutMs)
    Write-Output ("URL: {0}" -f [string]$state.url)
    if ($null -ne $process) {
        Write-Output ("PID: {0}" -f [string]$process.Id)
    }
    if ($null -ne $state.currentProxy) {
        Write-Output ("Current Proxy: {0}" -f [string]$state.currentProxy)
    }
    if ($null -ne $state.bestProxy) {
        Write-Output ("Best Proxy: {0}" -f [string]$state.bestProxy)
    }
    if ($null -ne $state.bestDelay) {
        Write-Output ("Best Delay: {0}" -f [string]$state.bestDelay)
    }
    if ($null -ne $state.lastRunUtc) {
        Write-Output ("Last Run UTC: {0}" -f [string]$state.lastRunUtc)
    }
    if ($null -ne $state.lastSwitchUtc) {
        Write-Output ("Last Switch UTC: {0}" -f [string]$state.lastSwitchUtc)
    }
    if ($null -ne $state.message) {
        Write-Output ("Message: {0}" -f [string]$state.message)
    }
}

function Invoke-AutoWorker {
    param(
        [string]$SelectorName,
        [string]$Country,
        [int]$IntervalSeconds,
        [int]$TimeoutMs,
        [string]$Url
    )

    while ($true) {
        $state = [ordered]@{
            enabled = $true
            running = $true
            pid = $PID
            selector = $SelectorName
            country = Normalize-CountryInput -Country $Country
            intervalSeconds = $IntervalSeconds
            timeoutMs = $TimeoutMs
            url = $Url
            startedAtUtc = [DateTime]::UtcNow.ToString("o")
            lastRunUtc = [DateTime]::UtcNow.ToString("o")
            lastSwitchUtc = $null
            currentProxy = $null
            bestProxy = $null
            bestDelay = $null
            message = ""
        }

        try {
            $selection = Get-BestCountryProxy -SelectorName $SelectorName -Country $Country -Url $Url -TimeoutMs $TimeoutMs
            $snapshot = Get-ProxySnapshot
            $selector = Get-SelectorProxy -Snapshot $snapshot -SelectorName $SelectorName
            if ($null -eq $selector) {
                throw "Selector '$SelectorName' was not found."
            }

            $current = if ($null -ne $selector.now) { [string]$selector.now } else { "" }
            $state.currentProxy = $current

            if ($null -eq $selection.best) {
                $state.message = "No usable proxy found for country '$($selection.country)'."
            } else {
                $bestProxy = [string]$selection.best.name
                $bestDelay = if ($null -ne $selection.best.measuredDelay) { [int]$selection.best.measuredDelay } else { [int]$selection.best.historyDelay }
                $state.bestProxy = $bestProxy
                $state.bestDelay = $bestDelay

                if ($current -ne $bestProxy) {
                    Set-SelectorProxy -SelectorName $SelectorName -ProxyName $bestProxy -Quiet
                    $state.currentProxy = $bestProxy
                    $state.lastSwitchUtc = [DateTime]::UtcNow.ToString("o")
                    $state.message = "Switched to fastest proxy '$bestProxy'."
                } else {
                    $state.message = "Current proxy '$current' is already the fastest healthy node."
                }
            }
        } catch {
            $state.message = $_.Exception.Message
        }

        Update-AutoState -State $state
        Start-Sleep -Seconds $IntervalSeconds
    }
}

function Invoke-Main {
    param([string[]]$Tokens)

    $Tokens = if ($null -eq $Tokens) { @() } else { @($Tokens) }
    if ($Tokens.Count -eq 0 -or $Tokens[0] -in @("--help", "help")) {
        Show-Help
        return
    }
    if ($Tokens.Count -gt 1 -and $Tokens[0] -ne "native" -and ($Tokens -contains '--help' -or $Tokens -contains '-h' -or $Tokens -contains 'help')) {
        Show-Help
        return
    }

    if ($Tokens[0] -in @("status", "version", "config", "mode", "mode-set", "selectors", "selector", "use", "proxies", "countries", "country", "country-use", "test", "providers", "rules")) {
        Use-MihomoRuntimeConfigIfAvailable | Out-Null
    }
    if ($Tokens[0] -in @("status", "version", "config", "mode", "mode-set", "selectors", "selector", "use", "proxies", "countries", "country", "country-use", "test", "providers", "rules")) {
        Ensure-MihomoRunning
    }

    switch ($Tokens[0]) {
        "write-runtime-config" {
            Write-MihomoRuntimeConfig | Write-Output
            return
        }
        "status" { Show-Status; return }
        "version" { Show-Version; return }
        "config" { Show-Config; return }
        "mode" { Show-Mode; return }
        "mode-set" {
            if ($Tokens.Count -lt 2) {
                Write-ClashCliError "Usage: mycli clash mode-set <rule|global|direct>"
            }
            Set-Mode -Mode $Tokens[1]
            return
        }
        "selectors" { Show-Selectors; return }
        "selector" {
            if ($Tokens.Count -ge 2) {
                Show-Selector -SelectorName $Tokens[1]
                return
            }
            Show-Selector
            return
        }
        "use" {
            if ($Tokens.Count -lt 3) {
                Write-ClashCliError "Usage: mycli clash use <selector> <proxy>"
            }
            Set-SelectorProxy -SelectorName $Tokens[1] -ProxyName $Tokens[2]
            return
        }
        "proxies" {
            if ($Tokens.Count -ge 2) {
                Show-Proxies -Keyword $Tokens[1]
                return
            }
            Show-Proxies
            return
        }
        "countries" {
            if ($Tokens.Count -ge 2) {
                Show-Countries -SelectorName $Tokens[1]
                return
            }
            Show-Countries
            return
        }
        "country" {
            if ($Tokens.Count -lt 2) {
                Write-ClashCliError "Usage: mycli clash country <country> [selector]"
            }
            if ($Tokens.Count -ge 3) {
                Show-Country -Country $Tokens[1] -SelectorName $Tokens[2]
                return
            }
            Show-Country -Country $Tokens[1]
            return
        }
        "country-use" {
            if ($Tokens.Count -lt 3) {
                Write-ClashCliError "Usage: mycli clash country-use <selector> <country> [url] [timeoutMs]"
            }
            $url = if ($Tokens.Count -ge 4) { [string]$Tokens[3] } else { $script:DefaultDelayUrl }
            $timeout = if ($Tokens.Count -ge 5) { [int]$Tokens[4] } else { $script:DefaultDelayTimeout }
            Use-FastestCountryProxy -SelectorName $Tokens[1] -Country $Tokens[2] -Url $url -TimeoutMs $timeout | Out-Null
            return
        }
        "test" {
            if ($Tokens.Count -lt 2) {
                Write-ClashCliError "Usage: mycli clash test <proxy> [url] [timeoutMs]"
            }
            $timeout = if ($Tokens.Count -ge 4) { [int]$Tokens[3] } else { $script:DefaultDelayTimeout }
            $url = if ($Tokens.Count -ge 3) { [string]$Tokens[2] } else { $script:DefaultDelayUrl }
            Test-ProxyDelay -ProxyName $Tokens[1] -Url $url -TimeoutMs $timeout
            return
        }
        "providers" { Show-Providers; return }
        "rules" {
            $limit = if ($Tokens.Count -ge 2) { [int]$Tokens[1] } else { 20 }
            Show-Rules -Limit $limit
            return
        }
        "auto-start" {
            if ($Tokens.Count -lt 3) {
                Write-ClashCliError "Usage: mycli clash auto-start <selector> <country> [intervalSec] [timeoutMs] [url]"
            }
            $interval = if ($Tokens.Count -ge 4) { [int]$Tokens[3] } else { $script:DefaultAutoIntervalSeconds }
            $timeout = if ($Tokens.Count -ge 5) { [int]$Tokens[4] } else { $script:DefaultDelayTimeout }
            $url = if ($Tokens.Count -ge 6) { [string]$Tokens[5] } else { $script:DefaultDelayUrl }
            Start-AutoSwitch -SelectorName $Tokens[1] -Country $Tokens[2] -IntervalSeconds $interval -TimeoutMs $timeout -Url $url
            return
        }
        "auto-stop" { Stop-AutoSwitch; return }
        "auto-status" { Show-AutoStatus; return }
        "auto-worker" {
            if ($Tokens.Count -lt 5) {
                Write-ClashCliError "Internal usage: auto-worker <selector> <country> <intervalSec> <timeoutMs> <url>"
            }
            Invoke-AutoWorker -SelectorName $Tokens[1] -Country $Tokens[2] -IntervalSeconds ([int]$Tokens[3]) -TimeoutMs ([int]$Tokens[4]) -Url $Tokens[5]
            return
        }
        "start" { Start-ClashApp; return }
        "stop" { Stop-ClashApp; return }
        "restart" { Restart-ClashApp; return }
        "check-config" { Test-ConfigFile; return }
        "native" {
            $remaining = @()
            if ($Tokens.Count -gt 1) {
                for ($i = 1; $i -lt $Tokens.Count; $i++) {
                    $tok = [string]$Tokens[$i]
                    $remaining += ,$tok
                }
            }
            Invoke-NativeCore -NativeArgs $remaining
            return
        }
        default {
            Write-ClashCliError "Unknown clash command '$($Tokens[0])'. Run 'mycli clash --help' for usage."
        }
    }
}

Invoke-Main -Tokens $CommandArgs

































