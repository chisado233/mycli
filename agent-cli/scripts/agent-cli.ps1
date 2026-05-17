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

$script:PackageRoot = Split-Path -Parent $PSScriptRoot
$script:ReadmePath = Join-Path $script:PackageRoot "README.md"
$script:WorkspaceConfigModule = Join-Path (Split-Path -Parent $script:PackageRoot) "common\workspace-config.ps1"
. $script:WorkspaceConfigModule
$script:WorkspaceConfig = Get-MyCliWorkspaceConfig -PackagePath 'agent-cli'
$script:ConfigPath = Join-Path ([string]$script:WorkspaceConfig.paths.config) "mapping-config.json"
$script:RegistryPath = Join-Path ([string]$script:WorkspaceConfig.paths.config) "registry.json"
$script:RunStateRoot = Join-Path ([string]$script:WorkspaceConfig.paths.var) "runs"
$script:ScheduleStateRoot = Join-Path ([string]$script:WorkspaceConfig.paths.var) "schedules"
$script:MountStateRoot = Join-Path ([string]$script:WorkspaceConfig.paths.var) "mounts"
$script:ClashPackageRoot = Join-Path (Split-Path -Parent $script:PackageRoot) "clash"
$script:DefaultClashScriptPath = Join-Path $script:ClashPackageRoot "scripts\clash-cli.ps1"
$script:DefaultClashAutoStatePath = "D:\agent_workspace\var\mycli\clash\auto-state.json"
$script:DefaultClashConfigPath = "C:\Users\38188\.config\clash\config.yaml"
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:Utf8WithBom = [System.Text.UTF8Encoding]::new($true)

function Write-AgentCliError {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Read-Utf8Text {
    param([string]$Path)

    try {
        return [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
    } catch {
        Write-AgentCliError "Failed to read UTF-8 text from '$Path'. $($_.Exception.Message)"
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
        Write-AgentCliError "Failed to write UTF-8 text to '$Path'. $($_.Exception.Message)"
    }
}

function ConvertTo-HashtableDeep {
    param([object]$InputObject)

    if ($null -eq $InputObject) {
        return $null
    }
    if ($InputObject -is [string] -or
        $InputObject -is [char] -or
        $InputObject -is [bool] -or
        $InputObject -is [byte] -or
        $InputObject -is [int] -or
        $InputObject -is [long] -or
        $InputObject -is [double] -or
        $InputObject -is [decimal] -or
        $InputObject -is [datetime]) {
        return $InputObject
    }
    if ($InputObject -is [System.Collections.IDictionary]) {
        $result = @{}
        foreach ($key in $InputObject.Keys) {
            $result[[string]$key] = ConvertTo-HashtableDeep -InputObject $InputObject[$key]
        }
        return $result
    }
    if ($InputObject -is [System.Collections.IEnumerable] -and -not ($InputObject -is [string])) {
        $items = @()
        foreach ($item in $InputObject) {
            $items += ,(ConvertTo-HashtableDeep -InputObject $item)
        }
        return $items
    }

    $properties = @($InputObject.PSObject.Properties)
    if ($properties.Count -gt 0) {
        $result = @{}
        foreach ($prop in $properties) {
            $result[$prop.Name] = ConvertTo-HashtableDeep -InputObject $prop.Value
        }
        return $result
    }

    return $InputObject
}

function Get-JsonFile {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        Write-AgentCliError "Required file not found: '$Path'."
    }
    try {
        return ConvertTo-HashtableDeep -InputObject ((Read-Utf8Text -Path $Path) | ConvertFrom-Json)
    } catch {
        Write-AgentCliError "Failed to parse JSON file '$Path'. $($_.Exception.Message)"
    }
}

function Save-JsonFile {
    param(
        [string]$Path,
        [object]$Value
    )

    $json = $Value | ConvertTo-Json -Depth 20
    Write-Utf8Text -Path $Path -Content $json
}

function Ensure-DirectoryExists {
    param([string]$Path)

    if ([string]::IsNullOrWhiteSpace($Path)) {
        return
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Get-RunStateRoot {
    Ensure-DirectoryExists -Path $script:RunStateRoot
    return $script:RunStateRoot
}

function Get-ScheduleStateRoot {
    Ensure-DirectoryExists -Path $script:ScheduleStateRoot
    return $script:ScheduleStateRoot
}

function Get-MountStateRoot {
    Ensure-DirectoryExists -Path $script:MountStateRoot
    return $script:MountStateRoot
}

function New-RunId {
    return "run_{0}_{1}" -f ([DateTime]::UtcNow.ToString("yyyyMMddTHHmmssfffZ")), ([Guid]::NewGuid().ToString("N").Substring(0, 8))
}

function Get-RunFileSet {
    param([string]$RunId)

    $root = Get-RunStateRoot
    return @{
        root = $root
        meta = Join-Path $root ("{0}.meta.json" -f $RunId)
        events = Join-Path $root ("{0}.events.jsonl" -f $RunId)
        raw = Join-Path $root ("{0}.raw.log" -f $RunId)
        report = Join-Path $root ("{0}.report.txt" -f $RunId)
    }
}

function Get-RunMetadataItems {
    $root = Get-RunStateRoot
    $items = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter "*.meta.json" -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try {
            $meta = Get-JsonFile -Path $file.FullName
            $meta["__meta_path"] = $file.FullName
            $items += ,$meta
        } catch {
            continue
        }
    }
    return $items
}

function Get-NextRoundNumber {
    param(
        [string]$SessionId,
        [string]$CurrentRunId
    )

    if ([string]::IsNullOrWhiteSpace($SessionId)) {
        return 1
    }

    $maxRound = 0
    foreach ($meta in @(Get-RunMetadataItems)) {
        if ($meta.ContainsKey("run_id") -and [string]$meta["run_id"] -eq $CurrentRunId) {
            continue
        }
        if ($meta.ContainsKey("session_id") -and [string]$meta["session_id"] -eq $SessionId) {
            $roundValue = 0
            if ($meta.ContainsKey("round") -and [int]::TryParse([string]$meta["round"], [ref]$roundValue)) {
                if ($roundValue -gt $maxRound) {
                    $maxRound = $roundValue
                }
            }
        }
    }

    return ($maxRound + 1)
}

function Set-TemporaryEnvironment {
    param([hashtable]$Environment)

    $saved = @{}
    if ($null -eq $Environment) {
        return $saved
    }

    foreach ($key in @($Environment.Keys)) {
        $name = [string]$key
        $existing = [System.Environment]::GetEnvironmentVariable($name, "Process")
        $saved[$name] = $existing
        [System.Environment]::SetEnvironmentVariable($name, [string]$Environment[$name], "Process")
    }
    return $saved
}

function Restore-TemporaryEnvironment {
    param([hashtable]$SavedEnvironment)

    if ($null -eq $SavedEnvironment) {
        return
    }

    foreach ($key in @($SavedEnvironment.Keys)) {
        $value = $SavedEnvironment[$key]
        if ($null -eq $value) {
            [System.Environment]::SetEnvironmentVariable([string]$key, $null, "Process")
        } else {
            [System.Environment]::SetEnvironmentVariable([string]$key, [string]$value, "Process")
        }
    }
}

function Get-OpenCodeFinalReport {
    param([System.Collections.Generic.List[string]]$TextParts)

    if ($null -eq $TextParts -or $TextParts.Count -eq 0) {
        return ""
    }
    return ($TextParts.ToArray() -join "")
}

function ConvertTo-PowerShellSingleQuotedString {
    param([string]$Value)
    if ($null -eq $Value) { $Value = "" }
    return "'{0}'" -f ($Value -replace "'", "''")
}

function Build-RemoteOpenCodeCommand {
    param(
        [hashtable]$Agent,
        [hashtable]$Options,
        [hashtable]$ProviderConfig
    )

    $remoteOpenCode = if ($ProviderConfig.ContainsKey("remote_opencode_binary")) { [string]$ProviderConfig["remote_opencode_binary"] } else { "opencode" }
    $remoteCwd = if ($Options.ContainsKey("cwd")) { [string]$Options["cwd"] } elseif ($ProviderConfig.ContainsKey("default_cwd")) { [string]$ProviderConfig["default_cwd"] } else { "D:\agent_workspace" }
    $remoteAgent = if ($ProviderConfig.ContainsKey("remote_opencode_agent_name") -and -not [string]::IsNullOrWhiteSpace([string]$ProviderConfig["remote_opencode_agent_name"])) { [string]$ProviderConfig["remote_opencode_agent_name"] } elseif ($Agent.ContainsKey("upstream_agent_name") -and -not [string]::IsNullOrWhiteSpace([string]$Agent["upstream_agent_name"])) { [string]$Agent["upstream_agent_name"] } else { "private-assistant" }

    $parts = New-Object System.Collections.Generic.List[string]
    $remoteConfigHome = if ($ProviderConfig.ContainsKey("remote_config_home")) { [string]$ProviderConfig["remote_config_home"] } else { "D:\agent_workspace\agent" }
    $parts.Add("`$env:XDG_CONFIG_HOME =")
    $parts.Add((ConvertTo-PowerShellSingleQuotedString -Value $remoteConfigHome))
    $parts.Add(";")
    $parts.Add("''")
    $parts.Add("|")
    $parts.Add("&")
    $parts.Add((ConvertTo-PowerShellSingleQuotedString -Value $remoteOpenCode))
    $parts.Add("run")
    $parts.Add("--agent")
    $parts.Add((ConvertTo-PowerShellSingleQuotedString -Value $remoteAgent))
    $parts.Add("--dir")
    $parts.Add((ConvertTo-PowerShellSingleQuotedString -Value $remoteCwd))
    $parts.Add("--format")
    $parts.Add("json")
    if ($Options.ContainsKey("fork")) { $parts.Add("--fork") }
    if ($Options.ContainsKey("continue")) {
        $parts.Add("--continue")
    } elseif ($Options.ContainsKey("session")) {
        $parts.Add("--session")
        $parts.Add((ConvertTo-PowerShellSingleQuotedString -Value ([string]$Options["session"])))
    }
    if ($Options.ContainsKey("model")) {
        $parts.Add("--model")
        $parts.Add((ConvertTo-PowerShellSingleQuotedString -Value ([string]$Options["model"])))
    }
    if ($Options.ContainsKey("session_name")) {
        $parts.Add("--title")
        $parts.Add((ConvertTo-PowerShellSingleQuotedString -Value ([string]$Options["session_name"])))
    }
    if ($Options.ContainsKey("prompt")) {
        $parts.Add((ConvertTo-PowerShellSingleQuotedString -Value ([string]$Options["prompt"])))
    }
    return ($parts.ToArray() -join " ")
}

function Invoke-TrackedRemoteOpenCodeRun {
    param(
        [string]$RemotePcBinary,
        [string]$Target,
        [string]$RemoteCommand,
        [int]$TimeoutSeconds,
        [hashtable]$Environment,
        [string]$ReturnMode,
        [string]$MappedAgentName,
        [string]$Prompt,
        [string]$Cwd,
        [string]$SessionName
    )

    $runId = New-RunId
    $files = Get-RunFileSet -RunId $runId
    $rawLines = [System.Collections.Generic.List[string]]::new()
    $eventLines = [System.Collections.Generic.List[string]]::new()
    $textParts = [System.Collections.Generic.List[string]]::new()
    $sessionId = $null
    $jsonParseErrors = 0
    $startedAt = [DateTime]::UtcNow.ToString("o")
    $savedEnvironment = Set-TemporaryEnvironment -Environment $Environment
    $arguments = @("run", $Target, $RemoteCommand)

    try {
        & $RemotePcBinary @arguments | ForEach-Object {
            $line = [string]$_
            $rawLines.Add($line)
            $parsed = $null
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                try {
                    $parsed = ConvertTo-HashtableDeep -InputObject ($line | ConvertFrom-Json)
                } catch {
                    $parsed = $null
                    if ($line.TrimStart().StartsWith("{")) { $jsonParseErrors += 1 }
                }
            }
            if ($null -ne $parsed) {
                $eventLines.Add($line)
                if ([string]::IsNullOrWhiteSpace($sessionId) -and $parsed.ContainsKey("sessionID")) { $sessionId = [string]$parsed["sessionID"] }
                if ($parsed.ContainsKey("type") -and [string]$parsed["type"] -eq "text") {
                    $part = ConvertTo-HashtableDeep -InputObject $parsed["part"]
                    if ($null -ne $part -and $part.ContainsKey("text")) { $textParts.Add([string]$part["text"]) }
                }
            }
            if ($ReturnMode -eq "stream") { Write-Output $line }
        }
        $exitCode = $LASTEXITCODE
    } finally {
        Restore-TemporaryEnvironment -SavedEnvironment $savedEnvironment
    }

    $finalReport = Get-OpenCodeFinalReport -TextParts $textParts
    $round = Get-NextRoundNumber -SessionId $sessionId -CurrentRunId $runId
    $finishedAt = [DateTime]::UtcNow.ToString("o")
    Write-Utf8Text -Path $files["raw"] -Content (($rawLines.ToArray()) -join [Environment]::NewLine) -EmitBom $false
    Write-Utf8Text -Path $files["events"] -Content (($eventLines.ToArray()) -join [Environment]::NewLine) -EmitBom $false
    Write-Utf8Text -Path $files["report"] -Content $finalReport -EmitBom $false
    $meta = @{
        run_id = $runId; started_at_utc = $startedAt; finished_at_utc = $finishedAt; agent = $MappedAgentName; source = "remote-opencode"; remote_target = $Target; prompt = $Prompt; cwd = $Cwd; session_name = $SessionName; session_id = $sessionId; round = $round; return_mode = $ReturnMode; provider_command = @($RemotePcBinary) + @($arguments); exit_code = $exitCode; status = if ($exitCode -eq 0) { "success" } else { "failed" }; json_parse_error_count = $jsonParseErrors; raw_output_path = $files["raw"]; event_log_path = $files["events"]; report_path = $files["report"]; event_count = $eventLines.Count
    }
    Save-JsonFile -Path $files["meta"] -Value $meta
    if ($ReturnMode -eq "silent") {
        if (-not [string]::IsNullOrWhiteSpace($sessionId)) { Write-Output ("sessionID: {0}" -f $sessionId); Write-Output ("round: {0}" -f $round); Write-Output "" }
        if (-not [string]::IsNullOrWhiteSpace($finalReport)) { Write-Output $finalReport }
    }
    if ($exitCode -ne 0) { exit $exitCode }
}

function Invoke-TrackedOpenCodeRun {
    param(
        [string]$Binary,
        [string[]]$Arguments,
        [hashtable]$Environment,
        [string]$ReturnMode,
        [string]$MappedAgentName,
        [string]$Prompt,
        [string]$Cwd,
        [string]$SessionName
    )

    $runId = New-RunId
    $files = Get-RunFileSet -RunId $runId
    $rawLines = [System.Collections.Generic.List[string]]::new()
    $eventLines = [System.Collections.Generic.List[string]]::new()
    $textParts = [System.Collections.Generic.List[string]]::new()
    $sessionId = $null
    $jsonParseErrors = 0
    $startedAt = [DateTime]::UtcNow.ToString("o")
    $savedEnvironment = Set-TemporaryEnvironment -Environment $Environment

    try {
        & $Binary @Arguments 2>&1 | ForEach-Object {
            $line = [string]$_
            $rawLines.Add($line)

            $parsed = $null
            if (-not [string]::IsNullOrWhiteSpace($line)) {
                try {
                    $parsed = ConvertTo-HashtableDeep -InputObject ($line | ConvertFrom-Json)
                } catch {
                    $parsed = $null
                    if ($line.TrimStart().StartsWith("{")) {
                        $jsonParseErrors += 1
                    }
                }
            }

            if ($null -ne $parsed) {
                $eventLines.Add($line)
                if ([string]::IsNullOrWhiteSpace($sessionId) -and $parsed.ContainsKey("sessionID")) {
                    $sessionId = [string]$parsed["sessionID"]
                }
                if ($parsed.ContainsKey("type") -and [string]$parsed["type"] -eq "text") {
                    $part = ConvertTo-HashtableDeep -InputObject $parsed["part"]
                    if ($null -ne $part -and $part.ContainsKey("text")) {
                        $textParts.Add([string]$part["text"])
                    }
                }
            }

            if ($ReturnMode -eq "stream") {
                Write-Output $line
            }
        }

        $exitCode = $LASTEXITCODE
    } finally {
        Restore-TemporaryEnvironment -SavedEnvironment $savedEnvironment
    }

    $finalReport = Get-OpenCodeFinalReport -TextParts $textParts
    $round = Get-NextRoundNumber -SessionId $sessionId -CurrentRunId $runId
    $finishedAt = [DateTime]::UtcNow.ToString("o")

    Write-Utf8Text -Path $files["raw"] -Content (($rawLines.ToArray()) -join [Environment]::NewLine) -EmitBom $false
    Write-Utf8Text -Path $files["events"] -Content (($eventLines.ToArray()) -join [Environment]::NewLine) -EmitBom $false
    Write-Utf8Text -Path $files["report"] -Content $finalReport -EmitBom $false

    $meta = @{
        run_id = $runId
        started_at_utc = $startedAt
        finished_at_utc = $finishedAt
        agent = $MappedAgentName
        source = "opencode"
        prompt = $Prompt
        cwd = $Cwd
        session_name = $SessionName
        session_id = $sessionId
        round = $round
        return_mode = $ReturnMode
        provider_command = @($Binary) + @($Arguments)
        exit_code = $exitCode
        status = if ($exitCode -eq 0) { "success" } else { "failed" }
        json_parse_error_count = $jsonParseErrors
        raw_output_path = $files["raw"]
        event_log_path = $files["events"]
        report_path = $files["report"]
        event_count = $eventLines.Count
    }
    Save-JsonFile -Path $files["meta"] -Value $meta

    if ($ReturnMode -eq "silent") {
        if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
            Write-Output ("sessionID: {0}" -f $sessionId)
            Write-Output ("round: {0}" -f $round)
            Write-Output ""
        }
        if (-not [string]::IsNullOrWhiteSpace($finalReport)) {
            Write-Output $finalReport
        }
    }

    if ($exitCode -ne 0) {
        exit $exitCode
    }
}

function Get-ConfigObject {
    return Get-JsonFile -Path $script:ConfigPath
}

function Get-RegistryObject {
    $registry = Get-JsonFile -Path $script:RegistryPath
    if (-not $registry.ContainsKey("agents")) { $registry["agents"] = @() }
    if (-not $registry.ContainsKey("current_agent")) { $registry["current_agent"] = $null }
    if (-not $registry.ContainsKey("last_sync_utc")) { $registry["last_sync_utc"] = $null }
    return $registry
}

function Save-RegistryObject {
    param([hashtable]$Registry)
    Save-JsonFile -Path $script:RegistryPath -Value $Registry
}

function Show-PackageHelp {
    Read-Utf8Text -Path $script:ReadmePath | Write-Output
}

function Split-CommandTokens {
    param([string[]]$Tokens)

    $options = @{}
    $positionals = New-Object System.Collections.Generic.List[string]
    $passthrough = New-Object System.Collections.Generic.List[string]
    $stopParsing = $false
    $i = 0
    while ($i -lt $Tokens.Count) {
        $token = [string]$Tokens[$i]
        if ($stopParsing) {
            $passthrough.Add($token)
            $i += 1
            continue
        }
        if ($token -eq "--") {
            $stopParsing = $true
            $i += 1
            continue
        }
        if ($token.StartsWith("--")) {
            $name = $token.Substring(2)
            if ([string]::IsNullOrWhiteSpace($name)) {
                Write-AgentCliError "Invalid option token '$token'."
            }
            $treatAsValue = $false
            if (($i + 1) -lt $Tokens.Count) {
                $nextToken = [string]$Tokens[$i + 1]
                if (-not $nextToken.StartsWith("--")) {
                    $treatAsValue = $true
                } elseif ($stopParsing -or $name -in @("agent", "model", "session_name", "prompt", "cwd", "session", "return_mode", "source", "name", "description", "mode", "tools", "path", "selector", "country")) {
                    $treatAsValue = $true
                }
            }
            if ($treatAsValue) {
                $options[$name] = [string]$Tokens[$i + 1]
                $i += 2
                continue
            }
            $options[$name] = $true
            $i += 1
            continue
        }
        $positionals.Add($token)
        $i += 1
    }

    return @{
        options = $options
        positionals = @($positionals)
        passthrough = @($passthrough)
    }
}

function Get-CurrentAgentName {
    param(
        [hashtable]$Config,
        [hashtable]$Registry
    )

    $fromRegistry = [string]$Registry["current_agent"]
    if (-not [string]::IsNullOrWhiteSpace($fromRegistry)) {
        return $fromRegistry
    }
    return [string]$Config["default_agent"]
}

function Get-ProviderKeys {
    param([hashtable]$Config)
    return @($Config["providers"].Keys | Sort-Object)
}

function Get-ProviderEnvironment {
    param([hashtable]$ProviderConfig)

    if (-not $ProviderConfig.ContainsKey("environment")) {
        $environment = @{}
    } else {
        $environment = ConvertTo-HashtableDeep -InputObject $ProviderConfig["environment"]
        if ($null -eq $environment) {
            $environment = @{}
        }
    }

    $result = @{}
    foreach ($key in @($environment.Keys)) {
        $result[[string]$key] = [string]$environment[$key]
    }

    if ($ProviderConfig.ContainsKey("proxy")) {
        $result = Resolve-ProviderProxyEnvironment -ProviderConfig $ProviderConfig -BaseEnvironment $result
    }

    return $result
}

function Get-ClashConfigValueMap {
    param([string]$Path)

    if (-not (Test-Path -LiteralPath $Path)) {
        return @{}
    }

    $map = @{}
    foreach ($line in @((Read-Utf8Text -Path $Path) -split "`r?`n")) {
        if ($line -match '^\s*#') {
            continue
        }
        if ($line -match '^\s*(?<key>[A-Za-z0-9._-]+)\s*:\s*(?<value>.*?)\s*$') {
            $value = [string]$matches["value"]
            $commentIndex = $value.IndexOf(" #")
            if ($commentIndex -ge 0) {
                $value = $value.Substring(0, $commentIndex)
            }
            $map[[string]$matches["key"]] = $value.Trim().Trim('"').Trim("'")
        }
    }

    return $map
}

function Get-ClashProxyUrl {
    param([hashtable]$ProxyConfig)

    $configFile = if ($ProxyConfig.ContainsKey("config_file")) {
        [string]$ProxyConfig["config_file"]
    } else {
        $script:DefaultClashConfigPath
    }
    $configMap = Get-ClashConfigValueMap -Path $configFile
    $mixedPort = if ($configMap.ContainsKey("mixed-port") -and -not [string]::IsNullOrWhiteSpace($configMap["mixed-port"])) {
        [string]$configMap["mixed-port"]
    } else {
        "7890"
    }
    return "http://127.0.0.1:{0}" -f $mixedPort
}

function Get-ClashAutoStateObject {
    param([hashtable]$ProxyConfig)

    $statePath = if ($ProxyConfig.ContainsKey("auto_state_file")) {
        [string]$ProxyConfig["auto_state_file"]
    } else {
        $script:DefaultClashAutoStatePath
    }
    if (-not (Test-Path -LiteralPath $statePath)) {
        return $null
    }

    try {
        return ConvertTo-HashtableDeep -InputObject ((Read-Utf8Text -Path $statePath) | ConvertFrom-Json)
    } catch {
        Write-AgentCliError "Failed to parse Clash auto state file '$statePath'. $($_.Exception.Message)"
    }
}

function Start-ClashAutoIfNeeded {
    param([hashtable]$ProxyConfig)

    $shouldAutoStart = $false
    if ($ProxyConfig.ContainsKey("auto_start_if_needed")) {
        $shouldAutoStart = [bool]$ProxyConfig["auto_start_if_needed"]
    }
    if (-not $shouldAutoStart) {
        return
    }

    $state = Get-ClashAutoStateObject -ProxyConfig $ProxyConfig
    if ($null -eq $state) {
        return
    }

    $isEnabled = $state.ContainsKey("enabled") -and [bool]$state["enabled"]
    $isRunning = $state.ContainsKey("running") -and [bool]$state["running"]
    if ($isEnabled -and $isRunning) {
        return
    }
    if (-not $state.ContainsKey("selector") -or -not $state.ContainsKey("country")) {
        return
    }

    $selector = [string]$state["selector"]
    $country = [string]$state["country"]
    if ([string]::IsNullOrWhiteSpace($selector) -or [string]::IsNullOrWhiteSpace($country)) {
        return
    }

    $intervalSeconds = if ($state.ContainsKey("intervalSeconds")) { [int]$state["intervalSeconds"] } else { 60 }
    $timeoutMs = if ($state.ContainsKey("timeoutMs")) { [int]$state["timeoutMs"] } else { 5000 }
    $url = if ($state.ContainsKey("url") -and -not [string]::IsNullOrWhiteSpace([string]$state["url"])) { [string]$state["url"] } else { "https://www.gstatic.com/generate_204" }
    $clashScriptPath = if ($ProxyConfig.ContainsKey("script")) { [string]$ProxyConfig["script"] } else { $script:DefaultClashScriptPath }
    if (-not (Test-Path -LiteralPath $clashScriptPath)) {
        return
    }

    & $clashScriptPath "auto-start" $selector $country ([string]$intervalSeconds) ([string]$timeoutMs) $url | Out-Null
}

function Resolve-ProviderProxyEnvironment {
    param(
        [hashtable]$ProviderConfig,
        [hashtable]$BaseEnvironment
    )

    $proxyConfig = ConvertTo-HashtableDeep -InputObject $ProviderConfig["proxy"]
    if ($null -eq $proxyConfig) {
        return $BaseEnvironment
    }

    $mode = if ($proxyConfig.ContainsKey("mode")) {
        [string]$proxyConfig["mode"]
    } else {
        "manual"
    }

    if ($mode -ne "auto") {
        return $BaseEnvironment
    }

    Start-ClashAutoIfNeeded -ProxyConfig $proxyConfig

    $proxyUrl = Get-ClashProxyUrl -ProxyConfig $proxyConfig
    $resolved = @{}
    foreach ($key in @($BaseEnvironment.Keys)) {
        $resolved[[string]$key] = [string]$BaseEnvironment[$key]
    }
    $resolved["HTTP_PROXY"] = $proxyUrl
    $resolved["HTTPS_PROXY"] = $proxyUrl
    $resolved["ALL_PROXY"] = $proxyUrl
    if (-not $resolved.ContainsKey("NO_PROXY")) {
        $resolved["NO_PROXY"] = "127.0.0.1,localhost"
    }

    return $resolved
}

function Invoke-ExternalProcess {
    param(
        [string]$FilePath,
        [string[]]$Arguments,
        [hashtable]$Environment,
        [string]$WorkingDirectory = ""
    )

    if ($null -eq $Environment) {
        if ([string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            & $FilePath @Arguments
            $exitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
            if ($null -ne $exitCodeVariable -and $null -ne $exitCodeVariable.Value) {
                exit $exitCodeVariable.Value
            }
            return
        }

        $psi = [System.Diagnostics.ProcessStartInfo]::new()
        $psi.FileName = $FilePath
        $psi.UseShellExecute = $false
        $psi.WorkingDirectory = $WorkingDirectory
        $escapedArguments = @($Arguments | ForEach-Object {
            $value = [string]$_
            if ($value -match '[\s"]') {
                '"' + ($value -replace '(\\*)"', '$1$1\"') + '"'
            } else {
                $value
            }
        })
        $psi.Arguments = ($escapedArguments -join " ")

        $process = [System.Diagnostics.Process]::Start($psi)
        $process.WaitForExit()
        exit $process.ExitCode
    }

    $resolvedEnvironment = @{}
    foreach ($key in @($Environment.Keys)) {
        $resolvedEnvironment[[string]$key] = [string]$Environment[$key]
    }

    $launchPath = $FilePath
    $launchArguments = @($Arguments)
    if ([System.IO.Path]::GetExtension($FilePath).Equals(".ps1", [System.StringComparison]::OrdinalIgnoreCase)) {
        $launchPath = "powershell.exe"
        $launchArguments = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $FilePath) + @($Arguments)
    }

    $psi = [System.Diagnostics.ProcessStartInfo]::new()
    $psi.FileName = $launchPath
    $psi.UseShellExecute = $false
    if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
        $psi.WorkingDirectory = $WorkingDirectory
    }
    $escapedArguments = @($launchArguments | ForEach-Object {
        $value = [string]$_
        if ($value -match '[\s"]') {
            '"' + ($value -replace '(\\*)"', '$1$1\"') + '"'
        } else {
            $value
        }
    })
    $psi.Arguments = ($escapedArguments -join " ")
    foreach ($entry in @($resolvedEnvironment.GetEnumerator())) {
        $psi.Environment[[string]$entry.Key] = [string]$entry.Value
    }

    $process = [System.Diagnostics.Process]::Start($psi)
    $process.WaitForExit()
    exit $process.ExitCode
}

function Normalize-AgentSegment {
    param([string]$Name)
    $lower = $Name.ToLowerInvariant().Trim()
    $normalized = $lower -replace '[^a-z0-9._-]+', '-'
    $normalized = $normalized.Trim('-')
    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return "agent"
    }
    return $normalized
}

function Parse-OpenCodeAgentList {
    param([string]$Output)

    $agents = @()
    foreach ($line in @($Output -split "\r?\n")) {
        if ($line -match '^(?<name>.+?) \((?<mode>primary|subagent|all)\)\s*$') {
            $agents += ,@{
                upstream = $matches["name"].Trim()
                mode = $matches["mode"].Trim()
            }
        }
    }
    return $agents
}

function Parse-ClaudeAgentList {
    param([string]$Output)

    $agents = @()
    foreach ($line in @($Output -split "\r?\n")) {
        $trimmed = $line.Trim()
        if ([string]::IsNullOrWhiteSpace($trimmed)) {
            continue
        }
        if ($trimmed -match '^\d+\s+active agents$') {
            continue
        }
        if ($trimmed.EndsWith(":")) {
            continue
        }

        if ($trimmed -match '^(?<name>.+?)\s+[^\x00-\x7F]+\s+.+$') {
            $name = $matches["name"].Trim()
            if ([string]::IsNullOrWhiteSpace($name)) {
                continue
            }

            $agents += ,@{
                upstream = $name
                mode = "primary"
            }
        }
    }
    return $agents
}

function Invoke-ProviderCommandCapture {
    param(
        [string]$Binary,
        [string[]]$Arguments,
        [hashtable]$Environment,
        [string]$WorkingDirectory = ""
    )

    $savedEnvironment = Set-TemporaryEnvironment -Environment $Environment
    try {
        if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
            Push-Location -LiteralPath $WorkingDirectory
        }
        try {
            $output = & $Binary @Arguments 2>&1 | Out-String
            $exitCode = $LASTEXITCODE
        } finally {
            if (-not [string]::IsNullOrWhiteSpace($WorkingDirectory)) {
                Pop-Location
            }
        }
    } finally {
        Restore-TemporaryEnvironment -SavedEnvironment $savedEnvironment
    }

    return @{
        output = $output
        exit_code = $exitCode
    }
}

function Get-ClaudeFinalReport {
    param([System.Collections.Generic.List[string]]$TextParts)

    if ($null -eq $TextParts -or $TextParts.Count -eq 0) {
        return ""
    }
    return ($TextParts.ToArray() -join "")
}

function Invoke-TrackedClaudeRun {
    param(
        [string]$Binary,
        [string[]]$Arguments,
        [hashtable]$Environment,
        [string]$ReturnMode,
        [string]$MappedAgentName,
        [string]$Prompt,
        [string]$Cwd,
        [string]$SessionName
    )

    $runId = New-RunId
    $files = Get-RunFileSet -RunId $runId
    $rawLines = [System.Collections.Generic.List[string]]::new()
    $eventLines = [System.Collections.Generic.List[string]]::new()
    $textParts = [System.Collections.Generic.List[string]]::new()
    $sessionId = $null
    $jsonParseErrors = 0
    $startedAt = [DateTime]::UtcNow.ToString("o")

    $savedEnvironment = Set-TemporaryEnvironment -Environment $Environment
    try {
        if (-not [string]::IsNullOrWhiteSpace($Cwd)) {
            Push-Location -LiteralPath $Cwd
        }
        try {
            & $Binary @Arguments 2>&1 | ForEach-Object {
                $line = [string]$_
                $rawLines.Add($line)

                $parsed = $null
                if (-not [string]::IsNullOrWhiteSpace($line)) {
                    try {
                        $parsed = ConvertTo-HashtableDeep -InputObject ($line | ConvertFrom-Json)
                    } catch {
                        $parsed = $null
                        if ($line.TrimStart().StartsWith("{")) {
                            $jsonParseErrors += 1
                        }
                    }
                }

                if ($null -ne $parsed) {
                    $eventLines.Add($line)
                    if ([string]::IsNullOrWhiteSpace($sessionId) -and $parsed.ContainsKey("session_id")) {
                        $sessionId = [string]$parsed["session_id"]
                    }
                    if ([string]::IsNullOrWhiteSpace($sessionId) -and $parsed.ContainsKey("sessionID")) {
                        $sessionId = [string]$parsed["sessionID"]
                    }
                    if ($parsed.ContainsKey("type") -and [string]$parsed["type"] -eq "system") {
                        if ($parsed.ContainsKey("subtype") -and [string]$parsed["subtype"] -eq "init" -and $parsed.ContainsKey("session_id")) {
                            $sessionId = [string]$parsed["session_id"]
                        }
                    }
                    if ($parsed.ContainsKey("type") -and [string]$parsed["type"] -eq "assistant" -and $parsed.ContainsKey("message")) {
                        $message = ConvertTo-HashtableDeep -InputObject $parsed["message"]
                        if ($null -ne $message -and $message.ContainsKey("content")) {
                            foreach ($contentPart in @($message["content"])) {
                                $part = ConvertTo-HashtableDeep -InputObject $contentPart
                                if ($null -ne $part -and $part.ContainsKey("type") -and [string]$part["type"] -eq "text" -and $part.ContainsKey("text")) {
                                    $textParts.Add([string]$part["text"])
                                }
                            }
                        }
                    }
                }

                if ($ReturnMode -eq "stream") {
                    Write-Output $line
                }
            }

            $exitCode = $LASTEXITCODE
        } finally {
            if (-not [string]::IsNullOrWhiteSpace($Cwd)) {
                Pop-Location
            }
        }
    } finally {
        Restore-TemporaryEnvironment -SavedEnvironment $savedEnvironment
    }

    $finalReport = ""
    if ($ReturnMode -eq "silent") {
        foreach ($line in @($rawLines.ToArray())) {
            if ([string]::IsNullOrWhiteSpace($line)) {
                continue
            }
            try {
                $parsed = ConvertTo-HashtableDeep -InputObject ($line | ConvertFrom-Json)
                if ($null -ne $parsed -and $parsed.ContainsKey("result")) {
                    $finalReport = [string]$parsed["result"]
                    if ([string]::IsNullOrWhiteSpace($sessionId) -and $parsed.ContainsKey("session_id")) {
                        $sessionId = [string]$parsed["session_id"]
                    }
                    break
                }
            } catch {
                continue
            }
        }
    }
    if ([string]::IsNullOrWhiteSpace($finalReport)) {
        $finalReport = Get-ClaudeFinalReport -TextParts $textParts
    }

    $round = Get-NextRoundNumber -SessionId $sessionId -CurrentRunId $runId
    $finishedAt = [DateTime]::UtcNow.ToString("o")

    Write-Utf8Text -Path $files["raw"] -Content (($rawLines.ToArray()) -join [Environment]::NewLine) -EmitBom $false
    Write-Utf8Text -Path $files["events"] -Content (($eventLines.ToArray()) -join [Environment]::NewLine) -EmitBom $false
    Write-Utf8Text -Path $files["report"] -Content $finalReport -EmitBom $false

    $meta = @{
        run_id = $runId
        started_at_utc = $startedAt
        finished_at_utc = $finishedAt
        agent = $MappedAgentName
        source = "claude"
        prompt = $Prompt
        cwd = $Cwd
        session_name = $SessionName
        session_id = $sessionId
        round = $round
        return_mode = $ReturnMode
        provider_command = @($Binary) + @($Arguments)
        exit_code = $exitCode
        status = if ($exitCode -eq 0) { "success" } else { "failed" }
        json_parse_error_count = $jsonParseErrors
        raw_output_path = $files["raw"]
        event_log_path = $files["events"]
        report_path = $files["report"]
        event_count = $eventLines.Count
    }
    Save-JsonFile -Path $files["meta"] -Value $meta

    if ($ReturnMode -eq "silent") {
        if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
            Write-Output ("sessionID: {0}" -f $sessionId)
            Write-Output ("round: {0}" -f $round)
            Write-Output ""
        }
        if (-not [string]::IsNullOrWhiteSpace($finalReport)) {
            Write-Output $finalReport
        }
    }

    if ($exitCode -ne 0) {
        exit $exitCode
    }
}

function Get-ProviderConfig {
    param(
        [hashtable]$Config,
        [string]$ProviderName
    )

    if (-not $Config["providers"].ContainsKey($ProviderName)) {
        Write-AgentCliError "Unknown provider source '$ProviderName'."
    }
    return $Config["providers"][$ProviderName]
}

function ConvertTo-MappedAgent {
    param(
        [string]$ProviderName,
        [hashtable]$ProviderConfig,
        [string]$UpstreamAgentName,
        [string]$Mode
    )

    $providerAgents = @{}
    if ($ProviderConfig.ContainsKey("agents")) {
        $providerAgents = $ProviderConfig["agents"]
    }
    $providerAliases = @{}
    if ($ProviderConfig.ContainsKey("agent_aliases")) {
        $providerAliases = $ProviderConfig["agent_aliases"]
    }

    $template = $null
    if ($providerAgents.ContainsKey($UpstreamAgentName)) {
        $template = $providerAgents[$UpstreamAgentName]
    } elseif ($providerAliases.ContainsKey($UpstreamAgentName)) {
        $template = $providerAliases[$UpstreamAgentName]
    }

    $mappedName = if ($null -ne $template -and $template.ContainsKey("mapped_name")) {
        [string]$template["mapped_name"]
    } else {
        "{0}/{1}" -f $ProviderName, (Normalize-AgentSegment -Name $UpstreamAgentName)
    }

    $displayName = if ($null -ne $template -and $template.ContainsKey("display_name")) {
        [string]$template["display_name"]
    } else {
        "{0}/{1}" -f $ProviderName, $UpstreamAgentName
    }

    return @{
        name = $mappedName
        display_name = $displayName
        source = $ProviderName
        upstream_agent_name = $UpstreamAgentName
        mode = $Mode
        binary = [string]$ProviderConfig["binary"]
        enabled = $true
    }
}

function Sync-Provider {
    param(
        [hashtable]$Config,
        [string]$ProviderName
    )

    $provider = Get-ProviderConfig -Config $Config -ProviderName $ProviderName
    if (-not [bool]$provider["enabled"]) {
        return @()
    }

    if ($ProviderName -eq "codex") {
        return ,(ConvertTo-MappedAgent -ProviderName "codex" -ProviderConfig $provider -UpstreamAgentName "default" -Mode "primary")
    }

    if ($ProviderName -eq "claude") {
        $discovery = if ($provider.ContainsKey("discovery")) { ConvertTo-HashtableDeep -InputObject $provider["discovery"] } else { @{} }
        $mapped = @()
        if ($null -ne $discovery -and $discovery.ContainsKey("type") -and [string]$discovery["type"] -eq "command") {
            $command = @($discovery["command"])
            if ($command.Count -gt 0) {
                $captureArguments = if ($command.Count -gt 1) { @($command[1..($command.Count - 1)]) } else { @() }
                $capture = Invoke-ProviderCommandCapture -Binary ([string]$command[0]) -Arguments $captureArguments -Environment (Get-ProviderEnvironment -ProviderConfig $provider)
                if ([int]$capture["exit_code"] -eq 0) {
                    $entries = Parse-ClaudeAgentList -Output ([string]$capture["output"])
                    foreach ($entry in $entries) {
                        $mapped += ,(ConvertTo-MappedAgent -ProviderName "claude" -ProviderConfig $provider -UpstreamAgentName ([string]$entry["upstream"]) -Mode ([string]$entry["mode"]))
                    }
                }
            }
        }
        if ($mapped.Count -eq 0) {
            $mapped += ,(ConvertTo-MappedAgent -ProviderName "claude" -ProviderConfig $provider -UpstreamAgentName "default" -Mode "primary")
        } elseif (-not (@($mapped | Where-Object { [string]$_["name"] -eq "claude/default" }).Count -gt 0)) {
            $mapped += ,(ConvertTo-MappedAgent -ProviderName "claude" -ProviderConfig $provider -UpstreamAgentName "default" -Mode "primary")
        }
        return @($mapped)
    }

    if ($ProviderName -eq "opencode") {
        $binary = [string]$provider["binary"]
        $output = & $binary "agent" "list" 2>&1 | Out-String
        if ($LASTEXITCODE -ne 0) {
            Write-AgentCliError "Failed to synchronize provider 'opencode'.`n$output"
        }
        $entries = Parse-OpenCodeAgentList -Output $output
        $mapped = @()
        foreach ($entry in $entries) {
            $mapped += ,(ConvertTo-MappedAgent -ProviderName "opencode" -ProviderConfig $provider -UpstreamAgentName ([string]$entry["upstream"]) -Mode ([string]$entry["mode"]))
        }
        return @($mapped)
    }

    if ($ProviderName -eq "remote-opencode") {
        $remoteAgent = if ($provider.ContainsKey("remote_agent")) { [string]$provider["remote_agent"] } else { "opencode/private-assistant" }
        $upstream = if ($remoteAgent.Contains("/")) { $remoteAgent.Substring($remoteAgent.IndexOf("/") + 1) } else { $remoteAgent }
        $target = if ($provider.ContainsKey("remote_target")) { [string]$provider["remote_target"] } else { "B" }
        $binary = if ($provider.ContainsKey("binary")) { [string]$provider["binary"] } else { "D:\agent_workspace\capability-library\mycli\remote-pc\scripts\remote-pc-cli.ps1" }
        return ,@{
            name = "remote-opencode/private-assistant"
            display_name = "remote-opencode/private-assistant on $target"
            source = "remote-opencode"
            upstream_agent_name = $upstream
            remote_agent = $remoteAgent
            remote_target = $target
            mode = "primary"
            binary = $binary
            enabled = $true
        }
    }

    Write-AgentCliError "Provider '$ProviderName' sync is not implemented."
}

function Invoke-Sync {
    param(
        [hashtable]$Config,
        [hashtable]$Registry
    )

    $allAgents = @()
    foreach ($providerName in Get-ProviderKeys -Config $Config) {
        $provider = Get-ProviderConfig -Config $Config -ProviderName $providerName
        if (-not [bool]$provider["enabled"]) {
            continue
        }
        $allAgents += @(Sync-Provider -Config $Config -ProviderName $providerName)
    }
    $Registry["agents"] = @($allAgents | Sort-Object name)
    $Registry["last_sync_utc"] = [DateTime]::UtcNow.ToString("o")
    Save-RegistryObject -Registry $Registry
    return $Registry
}

function Ensure-SyncedIfNeeded {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [switch]$Force
    )

    if ($Force) {
        return Invoke-Sync -Config $Config -Registry $Registry
    }

    $syncConfig = $Config["sync"]
    if ([bool]$syncConfig["auto_sync"] -and ($null -eq $Registry["last_sync_utc"] -or @($Registry["agents"]).Count -eq 0)) {
        return Invoke-Sync -Config $Config -Registry $Registry
    }
    return $Registry
}

function Get-MappedAgent {
    param(
        [hashtable]$Registry,
        [string]$Name
    )

    foreach ($agent in @($Registry["agents"])) {
        if ([string]$agent["name"] -eq $Name) {
            return $agent
        }
    }
    return $null
}

function Get-ProviderFromAgentName {
    param([string]$AgentName)

    if ([string]::IsNullOrWhiteSpace($AgentName)) {
        return $null
    }
    $index = $AgentName.IndexOf("/")
    if ($index -lt 0) {
        return $null
    }
    return $AgentName.Substring(0, $index)
}

function Show-AgentList {
    param(
        [hashtable]$Config,
        [hashtable]$Registry
    )

    $Registry = Ensure-SyncedIfNeeded -Config $Config -Registry $Registry
    $current = Get-CurrentAgentName -Config $Config -Registry $Registry
    if (@($Registry["agents"]).Count -eq 0) {
        Write-Output "No mapped agents."
        return
    }
    foreach ($agent in @($Registry["agents"])) {
        $marker = if ([string]$agent["name"] -eq $current) { "*" } else { " " }
        Write-Output ("{0} {1}" -f $marker, [string]$agent["name"])
        Write-Output ("  Display: {0}" -f [string]$agent["display_name"])
        Write-Output ("  Source: {0}" -f [string]$agent["source"])
        Write-Output ("  Upstream: {0}" -f [string]$agent["upstream_agent_name"])
        Write-Output ("  Mode: {0}" -f [string]$agent["mode"])
    }
}

function Show-CurrentAgent {
    param(
        [hashtable]$Config,
        [hashtable]$Registry
    )

    $Registry = Ensure-SyncedIfNeeded -Config $Config -Registry $Registry
    $current = Get-CurrentAgentName -Config $Config -Registry $Registry
    if ([string]::IsNullOrWhiteSpace($current)) {
        Write-Output "No current agent configured."
        return
    }
    $agent = Get-MappedAgent -Registry $Registry -Name $current
    if ($null -eq $agent) {
        Write-Output $current
        return
    }
    Write-Output $agent["name"]
    Write-Output ("  Display: {0}" -f $agent["display_name"])
    Write-Output ("  Source: {0}" -f $agent["source"])
    Write-Output ("  Upstream: {0}" -f $agent["upstream_agent_name"])
    Write-Output ("  Mode: {0}" -f $agent["mode"])
}

function Show-Agent {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string]$Name
    )

    $Registry = Ensure-SyncedIfNeeded -Config $Config -Registry $Registry
    $agent = Get-MappedAgent -Registry $Registry -Name $Name
    if ($null -eq $agent) {
        Write-AgentCliError "Mapped agent '$Name' was not found."
    }
    foreach ($key in @("name", "display_name", "source", "upstream_agent_name", "mode", "binary")) {
        Write-Output ("{0}: {1}" -f $key, [string]$agent[$key])
    }
}

function Set-CurrentAgent {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string]$Name
    )

    $Registry = Ensure-SyncedIfNeeded -Config $Config -Registry $Registry
    $agent = Get-MappedAgent -Registry $Registry -Name $Name
    if ($null -eq $agent) {
        Write-AgentCliError "Mapped agent '$Name' was not found."
    }
    $Registry["current_agent"] = $Name
    Save-RegistryObject -Registry $Registry
    Write-Output ("Current agent set to {0}" -f $Name)
}

function Show-SourceList {
    param([hashtable]$Config)

    foreach ($providerName in Get-ProviderKeys -Config $Config) {
        $provider = Get-ProviderConfig -Config $Config -ProviderName $providerName
        Write-Output $providerName
        Write-Output ("  Display: {0}" -f [string]$provider["display_name"])
        Write-Output ("  Enabled: {0}" -f [bool]$provider["enabled"])
        Write-Output ("  Binary: {0}" -f [string]$provider["binary"])
    }
}

function Show-Source {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string]$ProviderName
    )

    $provider = Get-ProviderConfig -Config $Config -ProviderName $ProviderName
    $Registry = Ensure-SyncedIfNeeded -Config $Config -Registry $Registry
    $agents = @($Registry["agents"] | Where-Object { [string]$_["source"] -eq $ProviderName })
    Write-Output ("name: {0}" -f $ProviderName)
    Write-Output ("display_name: {0}" -f [string]$provider["display_name"])
    Write-Output ("binary: {0}" -f [string]$provider["binary"])
    Write-Output ("supports_agent_create: {0}" -f [bool]$provider["capabilities"]["supports_agent_create"])
    Write-Output ("supports_session_name: {0}" -f [bool]$provider["capabilities"]["supports_session_name"])
    Write-Output ("agent_count: {0}" -f $agents.Count)
    if ($provider.ContainsKey("proxy")) {
        $proxyConfig = ConvertTo-HashtableDeep -InputObject $provider["proxy"]
        if ($null -ne $proxyConfig -and $proxyConfig.ContainsKey("mode")) {
            Write-Output ("proxy_mode: {0}" -f [string]$proxyConfig["mode"])
        }
    }
}

function Show-CodexAutoStatus {
    $clashScriptPath = $script:DefaultClashScriptPath
    if (-not (Test-Path -LiteralPath $clashScriptPath)) {
        Write-AgentCliError "Clash CLI script was not found at '$clashScriptPath'."
    }

    & $clashScriptPath "auto-status"
    $exitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    if ($null -ne $exitCodeVariable -and $null -ne $exitCodeVariable.Value -and $exitCodeVariable.Value -ne 0) {
        exit $exitCodeVariable.Value
    }
}

function Set-CodexAutoMode {
    param([string[]]$Tokens)

    if ($Tokens.Count -eq 0) {
        @"
agent-cli codex-auto

Usage:
  mycli agent-cli codex-auto status
  mycli agent-cli codex-auto use <selector> <country> [intervalSec] [timeoutMs] [url]
  mycli agent-cli codex-auto stop
"@ | Write-Output
        return
    }

    $clashScriptPath = $script:DefaultClashScriptPath
    if (-not (Test-Path -LiteralPath $clashScriptPath)) {
        Write-AgentCliError "Clash CLI script was not found at '$clashScriptPath'."
    }

    switch ($Tokens[0]) {
        "status" {
            Show-CodexAutoStatus
            return
        }
        "use" {
            if ($Tokens.Count -lt 3) {
                Write-AgentCliError "Usage: mycli agent-cli codex-auto use <selector> <country> [intervalSec] [timeoutMs] [url]"
            }
            $intervalSeconds = if ($Tokens.Count -ge 4) { [string]$Tokens[3] } else { "60" }
            $timeoutMs = if ($Tokens.Count -ge 5) { [string]$Tokens[4] } else { "5000" }
            $url = if ($Tokens.Count -ge 6) { [string]$Tokens[5] } else { "https://www.gstatic.com/generate_204" }
            & $clashScriptPath "auto-start" $Tokens[1] $Tokens[2] $intervalSeconds $timeoutMs $url
            $exitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
            if ($null -ne $exitCodeVariable -and $null -ne $exitCodeVariable.Value -and $exitCodeVariable.Value -ne 0) {
                exit $exitCodeVariable.Value
            }
            return
        }
        "stop" {
            & $clashScriptPath "auto-stop"
            $exitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
            if ($null -ne $exitCodeVariable -and $null -ne $exitCodeVariable.Value -and $exitCodeVariable.Value -ne 0) {
                exit $exitCodeVariable.Value
            }
            return
        }
        default {
            Write-AgentCliError "Unknown codex-auto action '$($Tokens[0])'."
        }
    }
}

function Join-ToolList {
    param([string]$Value)
    return (($Value -split ",") | ForEach-Object { $_.Trim() } | Where-Object { $_ }) -join ","
}

function New-OpenCodeAgentFileContent {
    param(
        [string]$Description,
        [string]$Mode,
        [string]$ToolsCsv
    )

    $enabledTools = @{}
    foreach ($tool in @(($ToolsCsv -split ",") | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })) {
        $enabledTools[$tool] = $true
    }

    $toolSet = @{}
    foreach ($tool in @("bash", "read", "write", "edit", "glob", "grep", "webfetch", "task", "todowrite")) {
        $toolSet[$tool] = $false
    }
    foreach ($tool in $enabledTools.Keys) {
        if ($toolSet.ContainsKey([string]$tool)) {
            $toolSet[$tool] = $true
        }
    }

    $lines = @(
        "---",
        ("description: {0}" -f $Description),
        ("mode: {0}" -f $Mode),
        "tools:"
    )
    foreach ($tool in $toolSet.Keys) {
        $value = if ($toolSet[$tool]) { "true" } else { "false" }
        $lines += ("  {0}: {1}" -f $tool, $value)
    }
    $lines += @(
        "---",
        "You are an OpenCode agent created by agent-cli.",
        ("Your responsibility: {0}" -f $Description),
        "",
        "Default requirement: understand the context first, then make the smallest correct change and verify the result."
    )
    return ($lines -join "`n")
}

function Invoke-AgentCreate {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string[]]$Tokens
    )

    $parsed = Split-CommandTokens -Tokens $Tokens
    $options = $parsed["options"]
    if (-not $options.ContainsKey("source")) {
        Write-AgentCliError "Usage: mycli agent-cli agent create --source <name> --name <agent-name> --description <text> [--mode <mode>] [--tools <csv>]"
    }
    if (-not $options.ContainsKey("name")) {
        Write-AgentCliError "Option --name is required."
    }
    if (-not $options.ContainsKey("description")) {
        Write-AgentCliError "Option --description is required."
    }
    $source = [string]$options["source"]
    $provider = Get-ProviderConfig -Config $Config -ProviderName $source
    if (-not [bool]$provider["capabilities"]["supports_agent_create"]) {
        Write-AgentCliError "Source '$source' does not support agent creation yet."
    }
    if ($source -ne "opencode") {
        Write-AgentCliError "Agent creation is currently only implemented for source 'opencode'."
    }

    $name = [string]$options["name"]
    $description = [string]$options["description"]
    $mode = if ($options.ContainsKey("mode")) { [string]$options["mode"] } else { "primary" }
    $toolsCsv = if ($options.ContainsKey("tools")) {
        Join-ToolList -Value ([string]$options["tools"])
    } else {
        "bash,read,write,edit,glob,grep,task,todowrite"
    }

    $dir = [string]$provider["agent_create"]["directory"]
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
    $fileName = "{0}.md" -f (Normalize-AgentSegment -Name $name)
    $path = Join-Path $dir $fileName
    if (Test-Path -LiteralPath $path) {
        Write-AgentCliError "Agent file already exists: '$path'."
    }
    $content = New-OpenCodeAgentFileContent -Description $description -Mode $mode -ToolsCsv $toolsCsv
    Write-Utf8Text -Path $path -Content $content
    Write-Output ("Created OpenCode agent file: {0}" -f $path)

    $Registry = Invoke-Sync -Config $Config -Registry $Registry
    $expectedMapped = "opencode/{0}" -f (Normalize-AgentSegment -Name $name)
    $agent = Get-MappedAgent -Registry $Registry -Name $expectedMapped
    if ($null -ne $agent) {
        Write-Output ("Mapped agent available: {0}" -f $expectedMapped)
    } else {
        Write-Output "Agent file created and sync completed, but mapped name may differ from the requested slug."
    }
}

function Get-RunContext {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [hashtable]$Options
    )

    $agentName = if ($Options.ContainsKey("agent")) { [string]$Options["agent"] } else { Get-CurrentAgentName -Config $Config -Registry $Registry }
    if ([string]::IsNullOrWhiteSpace($agentName)) {
        Write-AgentCliError "No agent selected. Use --agent or set one with 'mycli agent-cli agent use <name>'."
    }
    $Registry = Ensure-SyncedIfNeeded -Config $Config -Registry $Registry
    $agent = Get-MappedAgent -Registry $Registry -Name $agentName
    if ($null -eq $agent) {
        Write-AgentCliError "Mapped agent '$agentName' was not found."
    }
    return $agent
}

function Build-RunInvocation {
    param(
        [hashtable]$Agent,
        [hashtable]$Options
    )

    $source = [string]$Agent["source"]
    $binary = [string]$Agent["binary"]
    $args = New-Object System.Collections.Generic.List[string]

    if ($source -eq "opencode") {
        $args.Add("run")
        if ($Options.ContainsKey("fork")) {
            $args.Add("--fork")
        }
        if ($Options.ContainsKey("continue")) {
            $args.Add("--continue")
        } elseif ($Options.ContainsKey("session")) {
            $args.Add("--session")
            $args.Add([string]$Options["session"])
        }
        if ($Options.ContainsKey("prompt")) {
            $args.Add([string]$Options["prompt"])
        }
        $args.Add("--agent")
        $args.Add([string]$Agent["upstream_agent_name"])
        if ($Options.ContainsKey("model")) {
            $args.Add("--model")
            $args.Add([string]$Options["model"])
        }
        if ($Options.ContainsKey("session_name")) {
            $args.Add("--title")
            $args.Add([string]$Options["session_name"])
        }
        if ($Options.ContainsKey("cwd")) {
            $args.Add("--dir")
            $args.Add([string]$Options["cwd"])
        }
        
        $returnMode = if ($Options.ContainsKey("return_mode")) { [string]$Options["return_mode"] } else { "" }
        if ($returnMode -in @("stream", "silent")) {
            $args.Add("--format")
            $args.Add("json")
        }

        return @{
            binary = $binary
            args = @($args)
        }
    }

    if ($source -eq "remote-opencode") {
        return @{
            binary = $binary
            args = @()
            working_directory = ""
        }
    }

    if ($source -eq "codex") {
        if ($Options.ContainsKey("fork")) {
            $args.Add("fork")
            if ($Options.ContainsKey("session")) {
                $args.Add([string]$Options["session"])
            } else {
                $args.Add("--last")
            }
        } elseif ($Options.ContainsKey("continue") -or $Options.ContainsKey("session")) {
            $args.Add("resume")
            if ($Options.ContainsKey("session")) {
                $args.Add([string]$Options["session"])
            } else {
                $args.Add("--last")
            }
        } else {
            $args.Add("exec")
        }
        if ($Options.ContainsKey("model")) {
            $args.Add("--model")
            $args.Add([string]$Options["model"])
        }
        if ($Options.ContainsKey("cwd")) {
            $args.Add("--cd")
            $args.Add([string]$Options["cwd"])
        }
        if ($Options.ContainsKey("prompt")) {
            $args.Add([string]$Options["prompt"])
        }
        return @{
            binary = $binary
            args = @($args)
            working_directory = ""
        }
    }

    if ($source -eq "claude") {
        $args.Add("--print")
        $returnMode = if ($Options.ContainsKey("return_mode")) { [string]$Options["return_mode"] } else { "silent" }
        if ($returnMode -eq "stream") {
            $args.Add("--verbose")
            $args.Add("--output-format")
            $args.Add("stream-json")
        } else {
            $args.Add("--output-format")
            $args.Add("json")
        }
        if ($Options.ContainsKey("fork")) {
            $args.Add("--fork-session")
        }
        if ($Options.ContainsKey("continue")) {
            $args.Add("--continue")
        } elseif ($Options.ContainsKey("session")) {
            $args.Add("--resume")
            $args.Add([string]$Options["session"])
        }
        if ($Options.ContainsKey("model")) {
            $args.Add("--model")
            $args.Add([string]$Options["model"])
        }
        if ($Options.ContainsKey("session_name")) {
            $args.Add("--name")
            $args.Add([string]$Options["session_name"])
        }
        if ([string]$Agent["upstream_agent_name"] -ne "default") {
            $args.Add("--agent")
            $args.Add([string]$Agent["upstream_agent_name"])
        }
        if ($Options.ContainsKey("prompt")) {
            $args.Add([string]$Options["prompt"])
        }
        return @{
            binary = $binary
            args = @($args)
            working_directory = if ($Options.ContainsKey("cwd")) { [string]$Options["cwd"] } else { "" }
        }
    }

    Write-AgentCliError "Run mapping for source '$source' is not implemented."
}

function Invoke-Run {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string[]]$Tokens
    )

    if (-not $Tokens -or $Tokens.Count -eq 0) {
        @"
agent-cli run

Usage:
  mycli agent-cli run [--agent <mapped-agent>] [--prompt <text>] [--return_mode <stream|silent>] ...

Options:
  --agent <name>         Mapped agent name (e.g. opencode/build)
  --prompt <text>        The prompt for the agent
  --model <name>         Model to use
  --cwd <path>           Working directory
  --continue             Continue the current/last session
  --session <id>         Specify a session ID to continue
  --fork                 Fork from a session
  --session_name <name>  Title for the session
  --return_mode <mode>   Output mode for opencode: 'stream' (live events) or 'silent' (final report only, default)
"@ | Write-Output
        return
    }

    if ($Tokens[0] -eq "--help") {
        @"
agent-cli run

Usage:
  mycli agent-cli run [--agent <mapped-agent>] [--prompt <text>] [--return_mode <stream|silent>] ...

Options:
  --agent <name>         Mapped agent name (e.g. opencode/build)
  --prompt <text>        The prompt for the agent
  --model <name>         Model to use
  --cwd <path>           Working directory
  --continue             Continue the current/last session
  --session <id>         Specify a session ID to continue
  --fork                 Fork from a session
  --session_name <name>  Title for the session
  --return_mode <mode>   Output mode for opencode: 'stream' (live events) or 'silent' (final report only, default)
"@ | Write-Output
        return
    }

    $parsed = Split-CommandTokens -Tokens $Tokens
    $options = $parsed["options"]
    if ($options.ContainsKey("continue") -and $options.ContainsKey("session")) {
        Write-AgentCliError "Options --continue and --session are mutually exclusive."
    }
    if ($options.ContainsKey("fork") -and -not ($options.ContainsKey("continue") -or $options.ContainsKey("session"))) {
        Write-AgentCliError "Option --fork requires --continue or --session."
    }
    
    $returnMode = if ($options.ContainsKey("return_mode")) { [string]$options["return_mode"] } else { "" }
    if ([string]::IsNullOrWhiteSpace($returnMode)) {
        $returnMode = "silent"
    }
    if ($returnMode -notmatch '^(stream|silent)$') {
        Write-AgentCliError "Option --return_mode must be 'stream' or 'silent'."
    }

    $agent = Get-RunContext -Config $Config -Registry $Registry -Options $options
    
    # We need to inject return_mode into the options so Build-RunInvocation sees it
    $options["return_mode"] = $returnMode

    $invocation = Build-RunInvocation -Agent $agent -Options $options
    $invokeArgs = @($invocation["args"])
    $providerConfig = Get-ProviderConfig -Config $Config -ProviderName ([string]$agent["source"])
    $environment = Get-ProviderEnvironment -ProviderConfig $providerConfig

    if ([string]$agent["source"] -eq "opencode" -and $returnMode -in @("stream", "silent")) {
        $prompt = if ($options.ContainsKey("prompt")) { [string]$options["prompt"] } else { "" }
        $cwd = if ($options.ContainsKey("cwd")) { [string]$options["cwd"] } else { "" }
        $sessionName = if ($options.ContainsKey("session_name")) { [string]$options["session_name"] } else { "" }
        Invoke-TrackedOpenCodeRun -Binary ([string]$invocation["binary"]) -Arguments $invokeArgs -Environment $environment -ReturnMode $returnMode -MappedAgentName ([string]$agent["name"]) -Prompt $prompt -Cwd $cwd -SessionName $sessionName
        return
    }

    if ([string]$agent["source"] -eq "remote-opencode" -and $returnMode -in @("stream", "silent")) {
        $prompt = if ($options.ContainsKey("prompt")) { [string]$options["prompt"] } else { "" }
        $cwd = if ($options.ContainsKey("cwd")) { [string]$options["cwd"] } elseif ($providerConfig.ContainsKey("default_cwd")) { [string]$providerConfig["default_cwd"] } else { "D:\agent_workspace" }
        $sessionName = if ($options.ContainsKey("session_name")) { [string]$options["session_name"] } else { "" }
        $target = if ($agent.ContainsKey("remote_target")) { [string]$agent["remote_target"] } elseif ($providerConfig.ContainsKey("remote_target")) { [string]$providerConfig["remote_target"] } else { "B" }
        $timeoutSeconds = if ($providerConfig.ContainsKey("timeout_seconds")) { [int]$providerConfig["timeout_seconds"] } else { 3600 }
        $remoteCommand = Build-RemoteOpenCodeCommand -Agent $agent -Options $options -ProviderConfig $providerConfig
        Invoke-TrackedRemoteOpenCodeRun -RemotePcBinary ([string]$invocation["binary"]) -Target $target -RemoteCommand $remoteCommand -TimeoutSeconds $timeoutSeconds -Environment $environment -ReturnMode $returnMode -MappedAgentName ([string]$agent["name"]) -Prompt $prompt -Cwd $cwd -SessionName $sessionName
        return
    }

    if ([string]$agent["source"] -eq "claude" -and $returnMode -in @("stream", "silent")) {
        $prompt = if ($options.ContainsKey("prompt")) { [string]$options["prompt"] } else { "" }
        $cwd = if ($options.ContainsKey("cwd")) { [string]$options["cwd"] } else { "" }
        $sessionName = if ($options.ContainsKey("session_name")) { [string]$options["session_name"] } else { "" }
        Invoke-TrackedClaudeRun -Binary ([string]$invocation["binary"]) -Arguments $invokeArgs -Environment $environment -ReturnMode $returnMode -MappedAgentName ([string]$agent["name"]) -Prompt $prompt -Cwd $cwd -SessionName $sessionName
        return
    }

    Invoke-ExternalProcess -FilePath ([string]$invocation["binary"]) -Arguments $invokeArgs -Environment $environment -WorkingDirectory ([string]$invocation["working_directory"])
}

function ConvertTo-SafeScheduleNameSegment {
    param([string]$Value)
    $segment = Normalize-AgentSegment -Name $Value
    if ($segment.Length -gt 48) {
        $segment = $segment.Substring(0, 48).Trim('-')
    }
    if ([string]::IsNullOrWhiteSpace($segment)) {
        return "agent-task"
    }
    return $segment
}

function New-ScheduleId {
    param([string]$Name)
    $prefix = if ([string]::IsNullOrWhiteSpace($Name)) { "agent" } else { ConvertTo-SafeScheduleNameSegment -Value $Name }
    return "agentcli-{0}-{1}" -f $prefix, ([Guid]::NewGuid().ToString("N").Substring(0, 8))
}

function Get-ScheduleFilePath {
    param([string]$ScheduleId)
    return (Join-Path (Get-ScheduleStateRoot) ("{0}.json" -f $ScheduleId))
}

function Get-AgentCliScriptPath {
    return $PSCommandPath
}

function ConvertTo-RunTokensFromOptions {
    param([hashtable]$Options)

    $tokens = New-Object System.Collections.Generic.List[string]
    foreach ($key in @("agent", "model", "session_name", "prompt", "cwd", "session", "return_mode")) {
        if ($Options.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$Options[$key])) {
            $tokens.Add("--$key")
            $tokens.Add([string]$Options[$key])
        }
    }
    foreach ($flag in @("continue", "fork")) {
        if ($Options.ContainsKey($flag) -and [bool]$Options[$flag]) {
            $tokens.Add("--$flag")
        }
    }
    return @($tokens)
}

function ConvertFrom-DelayText {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        Write-AgentCliError "Delay value cannot be empty. Examples: 30m, 2h, 1d."
    }
    if ($Value -match '^\s*(?<number>\d+)\s*(?<unit>s|sec|secs|second|seconds|m|min|mins|minute|minutes|h|hr|hrs|hour|hours|d|day|days)?\s*$') {
        $number = [int]$matches["number"]
        $unit = if ($matches.ContainsKey("unit") -and -not [string]::IsNullOrWhiteSpace($matches["unit"])) { [string]$matches["unit"] } else { "m" }
        switch -Regex ($unit.ToLowerInvariant()) {
            '^(s|sec|secs|second|seconds)$' { return (New-TimeSpan -Seconds $number) }
            '^(m|min|mins|minute|minutes)$' { return (New-TimeSpan -Minutes $number) }
            '^(h|hr|hrs|hour|hours)$' { return (New-TimeSpan -Hours $number) }
            '^(d|day|days)$' { return (New-TimeSpan -Days $number) }
        }
    }
    Write-AgentCliError "Invalid delay '$Value'. Examples: 30m, 2h, 1d."
}

function ConvertTo-ScheduleStartTime {
    param([hashtable]$Options)

    if ($Options.ContainsKey("in")) {
        return [DateTime]::Now.Add((ConvertFrom-DelayText -Value ([string]$Options["in"])))
    }
    if ($Options.ContainsKey("at")) {
        $parsed = [DateTime]::MinValue
        if ([DateTime]::TryParse([string]$Options["at"], [ref]$parsed)) {
            return $parsed
        }
        Write-AgentCliError "Invalid --at value '$($Options["at"])'. Use a value parseable by PowerShell DateTime, e.g. '2026-04-25 18:30'."
    }
    Write-AgentCliError "Schedule creation requires --in <delay> or --at <datetime>."
}

function ConvertTo-TaskArgumentString {
    param([string[]]$Arguments)

    return (@($Arguments) | ForEach-Object {
        $value = [string]$_
        if ($value -match '[\s"]') {
            '"' + ($value -replace '(\\*)"', '$1$1\"') + '"'
        } else {
            $value
        }
    }) -join " "
}

function Register-AgentCliScheduledRun {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string[]]$Tokens
    )

    $parsed = Split-CommandTokens -Tokens $Tokens
    $options = $parsed["options"]
    if ($options.ContainsKey("help")) {
        Show-ScheduleHelp
        return
    }
    if ($options.ContainsKey("continue") -and $options.ContainsKey("session")) {
        Write-AgentCliError "Options --continue and --session are mutually exclusive."
    }
    if ($options.ContainsKey("fork") -and -not ($options.ContainsKey("continue") -or $options.ContainsKey("session"))) {
        Write-AgentCliError "Option --fork requires --continue or --session."
    }
    if (-not $options.ContainsKey("prompt")) {
        Write-AgentCliError "Schedule creation requires --prompt <text>."
    }
    if ($options.ContainsKey("in") -and $options.ContainsKey("at")) {
        Write-AgentCliError "Options --in and --at are mutually exclusive."
    }

    $agent = Get-RunContext -Config $Config -Registry $Registry -Options $options
    if (-not $options.ContainsKey("agent")) {
        $options["agent"] = [string]$agent["name"]
    }
    if (-not $options.ContainsKey("return_mode")) {
        $options["return_mode"] = "silent"
    }

    $startTime = ConvertTo-ScheduleStartTime -Options $options
    if ($startTime -le [DateTime]::Now.AddSeconds(5)) {
        Write-AgentCliError "Scheduled start time must be at least a few seconds in the future."
    }

    $scheduleName = if ($options.ContainsKey("name")) { [string]$options["name"] } else { [string]$options["prompt"] }
    $scheduleId = New-ScheduleId -Name $scheduleName
    $taskPath = "\agent-cli\"
    $taskName = $scheduleId
    $runTokens = ConvertTo-RunTokensFromOptions -Options $options
    $scriptPath = Get-AgentCliScriptPath
    $taskArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath, "run") + @($runTokens)
    $argumentString = ConvertTo-TaskArgumentString -Arguments $taskArgs

    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument $argumentString
    $trigger = New-ScheduledTaskTrigger -Once -At $startTime
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Settings $settings -Description "agent-cli scheduled agent wake-up" -Force | Out-Null

    $record = @{
        schedule_id = $scheduleId
        task_name = $taskName
        task_path = $taskPath
        created_at_utc = [DateTime]::UtcNow.ToString("o")
        start_time_local = $startTime.ToString("o")
        status = "registered"
        agent = [string]$options["agent"]
        model = if ($options.ContainsKey("model")) { [string]$options["model"] } else { "" }
        session = if ($options.ContainsKey("session")) { [string]$options["session"] } else { "" }
        continue = $options.ContainsKey("continue")
        fork = $options.ContainsKey("fork")
        session_name = if ($options.ContainsKey("session_name")) { [string]$options["session_name"] } else { "" }
        cwd = if ($options.ContainsKey("cwd")) { [string]$options["cwd"] } else { "" }
        return_mode = [string]$options["return_mode"]
        prompt = [string]$options["prompt"]
        command = @($scriptPath, "run") + @($runTokens)
    }
    Save-JsonFile -Path (Get-ScheduleFilePath -ScheduleId $scheduleId) -Value $record

    Write-Output ("Scheduled agent wake-up: {0}" -f $scheduleId)
    Write-Output ("Task: {0}{1}" -f $taskPath, $taskName)
    Write-Output ("At: {0}" -f $startTime.ToString("yyyy-MM-dd HH:mm:ss"))
    Write-Output ("Agent: {0}" -f [string]$options["agent"])
    if ($options.ContainsKey("session")) { Write-Output ("Session: {0}" -f [string]$options["session"]) }
}

function Get-AgentCliScheduleRecords {
    $root = Get-ScheduleStateRoot
    $records = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try {
            $record = Get-JsonFile -Path $file.FullName
            $record["__path"] = $file.FullName
            $records += ,$record
        } catch {
            continue
        }
    }
    return @($records)
}

function Find-FutureAgentCliSchedule {
    param(
        [string]$AgentName,
        [string]$SessionId
    )

    $now = [DateTime]::Now
    foreach ($record in @(Get-AgentCliScheduleRecords)) {
        if (-not $record.ContainsKey("agent") -or [string]$record["agent"] -ne $AgentName) {
            continue
        }
        if (-not [string]::IsNullOrWhiteSpace($SessionId)) {
            if (-not $record.ContainsKey("session") -or [string]$record["session"] -ne $SessionId) {
                continue
            }
        }
        if (-not $record.ContainsKey("start_time_local")) {
            continue
        }
        $startTime = [DateTime]::MinValue
        if (-not [DateTime]::TryParse([string]$record["start_time_local"], [ref]$startTime)) {
            continue
        }
        if ($startTime -le $now) {
            continue
        }
        try {
            $taskPath = if ($record.ContainsKey("task_path") -and -not [string]::IsNullOrWhiteSpace([string]$record["task_path"])) { [string]$record["task_path"] } else { "\agent-cli\" }
            $task = Get-ScheduledTask -TaskName ([string]$record["task_name"]) -TaskPath $taskPath -ErrorAction Stop
            if ([string]$task.State -in @("Ready", "Running", "Queued")) {
                return $record
            }
        } catch {
            continue
        }
    }
    return $null
}

function Show-AgentCliSchedules {
    $records = @(Get-AgentCliScheduleRecords)
    if ($records.Count -eq 0) {
        Write-Output "No agent-cli schedules recorded."
        return
    }
    foreach ($record in $records) {
        $taskState = "unknown"
        try {
            $recordTaskPath = if ($record.ContainsKey("task_path") -and -not [string]::IsNullOrWhiteSpace([string]$record["task_path"])) { [string]$record["task_path"] } else { "\agent-cli\" }
            $task = Get-ScheduledTask -TaskName ([string]$record["task_name"]) -TaskPath $recordTaskPath -ErrorAction Stop
            $taskState = [string]$task.State
        } catch {
            $taskState = "missing"
        }
        Write-Output ([string]$record["schedule_id"])
        $displayTaskPath = if ($record.ContainsKey("task_path") -and -not [string]::IsNullOrWhiteSpace([string]$record["task_path"])) { [string]$record["task_path"] } else { "\agent-cli\" }
        Write-Output ("  Task: {0}{1}" -f $displayTaskPath, [string]$record["task_name"])
        Write-Output ("  State: {0}" -f $taskState)
        Write-Output ("  At: {0}" -f [string]$record["start_time_local"])
        Write-Output ("  Agent: {0}" -f [string]$record["agent"])
        if (-not [string]::IsNullOrWhiteSpace([string]$record["model"])) { Write-Output ("  Model: {0}" -f [string]$record["model"]) }
        if (-not [string]::IsNullOrWhiteSpace([string]$record["session"])) { Write-Output ("  Session: {0}" -f [string]$record["session"]) }
        Write-Output ("  Prompt: {0}" -f [string]$record["prompt"])
    }
}

function Remove-AgentCliSchedule {
    param([string]$ScheduleId)
    if ([string]::IsNullOrWhiteSpace($ScheduleId)) {
        Write-AgentCliError "Usage: mycli agent-cli schedule cancel <schedule-id>"
    }
    $recordPath = Get-ScheduleFilePath -ScheduleId $ScheduleId
    $taskPath = "\agent-cli\"
    $taskName = $ScheduleId
    if (Test-Path -LiteralPath $recordPath) {
        $record = Get-JsonFile -Path $recordPath
        if ($record.ContainsKey("task_name") -and -not [string]::IsNullOrWhiteSpace([string]$record["task_name"])) {
            $taskName = [string]$record["task_name"]
        }
        if ($record.ContainsKey("task_path") -and -not [string]::IsNullOrWhiteSpace([string]$record["task_path"])) {
            $taskPath = [string]$record["task_path"]
        }
    }
    try {
        Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction Stop
    } catch {
        Write-Output ("Scheduled task not found or already removed: {0}{1}" -f $taskPath, $taskName)
    }
    if (Test-Path -LiteralPath $recordPath) {
        Remove-Item -LiteralPath $recordPath -Force
    }
    Write-Output ("Cancelled schedule: {0}" -f $ScheduleId)
}

function Show-ScheduleHelp {
    @"
agent-cli schedule

Usage:
  mycli agent-cli schedule add --in <delay> --agent <mapped-agent> --prompt <text> [run options]
  mycli agent-cli schedule add --at <datetime> --agent <mapped-agent> --prompt <text> [run options]
  mycli agent-cli schedule list
  mycli agent-cli schedule cancel <schedule-id>

Run options passed to the future wake-up:
  --agent <name>         Mapped agent name. Defaults to current agent if omitted.
  --model <name>         Model to use when the task fires.
  --session <id>         Resume a specific session when the task fires.
  --continue             Continue provider's latest/current session when the task fires.
  --fork                 Fork from --session or --continue.
  --session_name <name>  Session title/name.
  --cwd <path>           Working directory.
  --return_mode <mode>   stream or silent. Defaults to silent.
  --prompt <text>        Prompt to send at wake-up time.

Delay examples: 30m, 2h, 1d.
"@ | Write-Output
}

function Handle-ScheduleCommand {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string[]]$Tokens
    )

    if (-not $Tokens -or $Tokens.Count -eq 0 -or $Tokens[0] -eq "--help") {
        Show-ScheduleHelp
        return
    }
    switch ($Tokens[0]) {
        "add" {
            $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }
            Register-AgentCliScheduledRun -Config $Config -Registry $Registry -Tokens $rest
            return
        }
        "list" { Show-AgentCliSchedules; return }
        "cancel" {
            if ($Tokens.Count -lt 2) { Write-AgentCliError "Usage: mycli agent-cli schedule cancel <schedule-id>" }
            Remove-AgentCliSchedule -ScheduleId ([string]$Tokens[1])
            return
        }
        default { Write-AgentCliError "Unknown schedule action '$($Tokens[0])'." }
    }
}

function New-MountId {
    param([string]$Name)
    $prefix = if ([string]::IsNullOrWhiteSpace($Name)) { "mount" } else { ConvertTo-SafeScheduleNameSegment -Value $Name }
    return "agentmount-{0}-{1}" -f $prefix, ([Guid]::NewGuid().ToString("N").Substring(0, 8))
}

function Get-MountFilePath {
    param([string]$MountId)
    return (Join-Path (Get-MountStateRoot) ("{0}.json" -f $MountId))
}

function Get-AgentCliMountRecords {
    $root = Get-MountStateRoot
    $records = @()
    foreach ($file in @(Get-ChildItem -LiteralPath $root -Filter "*.json" -File -ErrorAction SilentlyContinue | Sort-Object Name)) {
        try {
            $record = Get-JsonFile -Path $file.FullName
            $record["__path"] = $file.FullName
            $records += ,$record
        } catch {
            continue
        }
    }
    return @($records)
}

function Get-LatestRunForAgentSession {
    param(
        [string]$AgentName,
        [string]$SessionId
    )
    $items = @(Get-RunMetadataItems | Where-Object {
        [string]$_["agent"] -eq $AgentName -and
        (-not [string]::IsNullOrWhiteSpace($SessionId)) -and
        [string]$_["session_id"] -eq $SessionId
    } | Sort-Object started_at_utc)
    if ($items.Count -eq 0) {
        return $null
    }
    return $items[-1]
}

function Test-AgentSessionRecentlyWorked {
    param(
        [string]$AgentName,
        [string]$SessionId,
        [int]$QuietMinutes
    )

    $latest = Get-LatestRunForAgentSession -AgentName $AgentName -SessionId $SessionId
    if ($null -eq $latest -or -not $latest.ContainsKey("finished_at_utc")) {
        return $false
    }
    $finishedAt = [DateTime]::MinValue
    if (-not [DateTime]::TryParse([string]$latest["finished_at_utc"], [ref]$finishedAt)) {
        return $false
    }
    return ($finishedAt.ToUniversalTime() -gt [DateTime]::UtcNow.AddMinutes(-1 * $QuietMinutes))
}

function Get-HeartbeatPrompt {
    param([hashtable]$Mount)

    $custom = if ($Mount.ContainsKey("heartbeat_prompt")) { [string]$Mount["heartbeat_prompt"] } else { "" }
    if (-not [string]::IsNullOrWhiteSpace($custom)) {
        return $custom
    }
    return @"
You are being woken by agent-cli mount heartbeat.

Lifecycle rules:
1. Inspect the current session context and continue useful pending work if any.
2. If you need to pause and be woken later, create an agent-cli schedule for this same agent/session before ending your turn.
3. If there is no useful work, report that clearly and either schedule your next wake-up or stay idle.
4. If this lifecycle/session should end and be replaced by a fresh session, include the exact marker AGENT_CLI_LIFECYCLE_END in your final response.

Return a concise status report.
"@
}

function Get-RunReportText {
    param([hashtable]$RunMeta)
    if ($null -eq $RunMeta -or -not $RunMeta.ContainsKey("report_path")) {
        return ""
    }
    $path = [string]$RunMeta["report_path"]
    if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
        return ""
    }
    return Read-Utf8Text -Path $path
}

function Invoke-MountHeartbeat {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [hashtable]$Mount
    )

    $agentName = [string]$Mount["agent"]
    $sessionId = if ($Mount.ContainsKey("session")) { [string]$Mount["session"] } else { "" }
    $quietMinutes = if ($Mount.ContainsKey("quiet_minutes")) { [int]$Mount["quiet_minutes"] } else { 30 }
    $endMarker = if ($Mount.ContainsKey("end_marker") -and -not [string]::IsNullOrWhiteSpace([string]$Mount["end_marker"])) { [string]$Mount["end_marker"] } else { "AGENT_CLI_LIFECYCLE_END" }

    if (-not [string]::IsNullOrWhiteSpace($sessionId)) {
        $futureSchedule = Find-FutureAgentCliSchedule -AgentName $agentName -SessionId $sessionId
        if ($null -ne $futureSchedule) {
            return @{ action = "skipped"; reason = "future_schedule_exists"; schedule_id = [string]$futureSchedule["schedule_id"] }
        }
        if (Test-AgentSessionRecentlyWorked -AgentName $agentName -SessionId $sessionId -QuietMinutes $quietMinutes) {
            return @{ action = "skipped"; reason = "recently_worked" }
        }
    }

    $options = @{
        agent = $agentName
        prompt = (Get-HeartbeatPrompt -Mount $Mount)
        return_mode = if ($Mount.ContainsKey("return_mode")) { [string]$Mount["return_mode"] } else { "silent" }
    }
    if (-not [string]::IsNullOrWhiteSpace($sessionId)) { $options["session"] = $sessionId }
    foreach ($key in @("model", "cwd", "session_name")) {
        if ($Mount.ContainsKey($key) -and -not [string]::IsNullOrWhiteSpace([string]$Mount[$key])) {
            $options[$key] = [string]$Mount[$key]
        }
    }

    $beforeRuns = @(Get-RunMetadataItems)
    $beforeIds = @{}
    foreach ($run in $beforeRuns) {
        if ($run.ContainsKey("run_id")) { $beforeIds[[string]$run["run_id"]] = $true }
    }

    $agent = Get-RunContext -Config $Config -Registry $Registry -Options $options
    $invocation = Build-RunInvocation -Agent $agent -Options $options
    $providerConfig = Get-ProviderConfig -Config $Config -ProviderName ([string]$agent["source"])
    $environment = Get-ProviderEnvironment -ProviderConfig $providerConfig
    $invokeArgs = @($invocation["args"])
    $heartbeatCwd = if ($options.ContainsKey("cwd")) { [string]$options["cwd"] } else { "" }
    $heartbeatSessionName = if ($options.ContainsKey("session_name")) { [string]$options["session_name"] } else { "" }
    if ([string]$agent["source"] -eq "opencode") {
        Invoke-TrackedOpenCodeRun -Binary ([string]$invocation["binary"]) -Arguments $invokeArgs -Environment $environment -ReturnMode ([string]$options["return_mode"]) -MappedAgentName ([string]$agent["name"]) -Prompt ([string]$options["prompt"]) -Cwd $heartbeatCwd -SessionName $heartbeatSessionName
    } elseif ([string]$agent["source"] -eq "claude") {
        Invoke-TrackedClaudeRun -Binary ([string]$invocation["binary"]) -Arguments $invokeArgs -Environment $environment -ReturnMode ([string]$options["return_mode"]) -MappedAgentName ([string]$agent["name"]) -Prompt ([string]$options["prompt"]) -Cwd $heartbeatCwd -SessionName $heartbeatSessionName
    } else {
        Invoke-ExternalProcess -FilePath ([string]$invocation["binary"]) -Arguments $invokeArgs -Environment $environment -WorkingDirectory ([string]$invocation["working_directory"])
    }

    $newRuns = @(Get-RunMetadataItems | Where-Object { $_.ContainsKey("run_id") -and -not $beforeIds.ContainsKey([string]$_["run_id"]) } | Sort-Object started_at_utc)
    $runMeta = if ($newRuns.Count -gt 0) { $newRuns[-1] } else { $null }
    $report = Get-RunReportText -RunMeta $runMeta
    $ended = (-not [string]::IsNullOrWhiteSpace($report) -and $report.Contains($endMarker))

    return @{ action = "heartbeat"; ended = $ended; run = $runMeta }
}

function Register-AgentCliMount {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string[]]$Tokens
    )

    $parsed = Split-CommandTokens -Tokens $Tokens
    $options = $parsed["options"]
    if ($options.ContainsKey("help")) { Show-MountHelp; return }
    if (-not $options.ContainsKey("agent")) { Write-AgentCliError "Mount creation requires --agent <mapped-agent>." }

    $agentOptions = @{ agent = [string]$options["agent"] }
    $agent = Get-RunContext -Config $Config -Registry $Registry -Options $agentOptions
    $mountName = if ($options.ContainsKey("name")) { [string]$options["name"] } else { [string]$agent["name"] }
    $mountId = New-MountId -Name $mountName
    $intervalMinutes = if ($options.ContainsKey("interval_minutes")) { [int]$options["interval_minutes"] } else { 15 }
    $quietMinutes = if ($options.ContainsKey("quiet_minutes")) { [int]$options["quiet_minutes"] } else { [Math]::Max($intervalMinutes, 15) }
    if ($intervalMinutes -lt 1) { Write-AgentCliError "--interval_minutes must be >= 1." }
    if ($quietMinutes -lt 1) { Write-AgentCliError "--quiet_minutes must be >= 1." }

    $mount = @{
        mount_id = $mountId
        name = $mountName
        agent = [string]$agent["name"]
        session = if ($options.ContainsKey("session")) { [string]$options["session"] } else { "" }
        model = if ($options.ContainsKey("model")) { [string]$options["model"] } else { "" }
        cwd = if ($options.ContainsKey("cwd")) { [string]$options["cwd"] } else { "" }
        session_name = if ($options.ContainsKey("session_name")) { [string]$options["session_name"] } else { "" }
        heartbeat_prompt = if ($options.ContainsKey("heartbeat_prompt")) { [string]$options["heartbeat_prompt"] } else { "" }
        end_marker = if ($options.ContainsKey("end_marker")) { [string]$options["end_marker"] } else { "AGENT_CLI_LIFECYCLE_END" }
        return_mode = if ($options.ContainsKey("return_mode")) { [string]$options["return_mode"] } else { "silent" }
        interval_minutes = $intervalMinutes
        quiet_minutes = $quietMinutes
        created_at_utc = [DateTime]::UtcNow.ToString("o")
        status = "mounted"
        generation = 1
        current_session = if ($options.ContainsKey("session")) { [string]$options["session"] } else { "" }
        last_tick_utc = ""
        last_action = "created"
    }
    Save-JsonFile -Path (Get-MountFilePath -MountId $mountId) -Value $mount

    $taskPath = "\agent-cli\mount\"
    $taskName = $mountId
    $scriptPath = Get-AgentCliScriptPath
    $taskArgs = @("-NoProfile", "-ExecutionPolicy", "Bypass", "-File", $scriptPath, "mount", "tick", $mountId)
    $action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument (ConvertTo-TaskArgumentString -Arguments $taskArgs)
    $trigger = New-ScheduledTaskTrigger -Once -At ([DateTime]::Now.AddMinutes($intervalMinutes)) -RepetitionInterval (New-TimeSpan -Minutes $intervalMinutes)
    $settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
    Register-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Action $action -Trigger $trigger -Settings $settings -Description "agent-cli mounted agent lifecycle heartbeat" -Force | Out-Null

    $mount["task_name"] = $taskName
    $mount["task_path"] = $taskPath
    Save-JsonFile -Path (Get-MountFilePath -MountId $mountId) -Value $mount
    Write-Output ("Mounted agent lifecycle: {0}" -f $mountId)
    Write-Output ("Task: {0}{1}" -f $taskPath, $taskName)
    Write-Output ("Agent: {0}" -f [string]$mount["agent"])
    if (-not [string]::IsNullOrWhiteSpace([string]$mount["session"])) { Write-Output ("Session: {0}" -f [string]$mount["session"]) }
}

function Invoke-MountTick {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string]$MountId
    )
    $path = Get-MountFilePath -MountId $MountId
    if (-not (Test-Path -LiteralPath $path)) { Write-AgentCliError "Mount '$MountId' was not found." }
    $mount = Get-JsonFile -Path $path
    $result = Invoke-MountHeartbeat -Config $Config -Registry $Registry -Mount $mount
    $mount["last_tick_utc"] = [DateTime]::UtcNow.ToString("o")
    $mount["last_action"] = [string]$result["action"]
    if ($result.ContainsKey("reason")) { $mount["last_reason"] = [string]$result["reason"] }
    if ($result.ContainsKey("schedule_id")) { $mount["last_schedule_id"] = [string]$result["schedule_id"] }
    if ($result.ContainsKey("run") -and $null -ne $result["run"]) {
        $run = ConvertTo-HashtableDeep -InputObject $result["run"]
        $mount["last_run_id"] = [string]$run["run_id"]
        if ($run.ContainsKey("session_id") -and -not [string]::IsNullOrWhiteSpace([string]$run["session_id"])) {
            $mount["current_session"] = [string]$run["session_id"]
            $mount["session"] = [string]$run["session_id"]
        }
    }
    if ($result.ContainsKey("ended") -and [bool]$result["ended"]) {
        $mount["generation"] = [int]$mount["generation"] + 1
        $mount["session"] = ""
        $mount["current_session"] = ""
        $mount["last_action"] = "lifecycle_ended_new_session_next"
    }
    Save-JsonFile -Path $path -Value $mount
    Write-Output ("Mount tick: {0} -> {1}" -f $MountId, [string]$mount["last_action"])
}

function Show-AgentCliMounts {
    $records = @(Get-AgentCliMountRecords)
    if ($records.Count -eq 0) { Write-Output "No agent-cli mounts recorded."; return }
    foreach ($mount in $records) {
        $taskState = "unknown"
        try {
            $taskPath = if ($mount.ContainsKey("task_path")) { [string]$mount["task_path"] } else { "\agent-cli\mount\" }
            $task = Get-ScheduledTask -TaskName ([string]$mount["task_name"]) -TaskPath $taskPath -ErrorAction Stop
            $taskState = [string]$task.State
        } catch { $taskState = "missing" }
        Write-Output ([string]$mount["mount_id"])
        Write-Output ("  State: {0}" -f $taskState)
        Write-Output ("  Agent: {0}" -f [string]$mount["agent"])
        Write-Output ("  Session: {0}" -f [string]$mount["session"])
        Write-Output ("  Interval: {0} min" -f [string]$mount["interval_minutes"])
        Write-Output ("  Last: {0} {1}" -f [string]$mount["last_tick_utc"], [string]$mount["last_action"])
    }
}

function Get-AgentCliMountById {
    param([string]$MountId)
    if ([string]::IsNullOrWhiteSpace($MountId)) {
        Write-AgentCliError "Mount id cannot be empty."
    }
    $path = Get-MountFilePath -MountId $MountId
    if (-not (Test-Path -LiteralPath $path)) {
        Write-AgentCliError "Mount '$MountId' was not found."
    }
    $mount = Get-JsonFile -Path $path
    $mount["__path"] = $path
    return $mount
}

function Get-TaskStateForMount {
    param([hashtable]$Mount)
    try {
        $taskPath = if ($Mount.ContainsKey("task_path") -and -not [string]::IsNullOrWhiteSpace([string]$Mount["task_path"])) { [string]$Mount["task_path"] } else { "\agent-cli\mount\" }
        $taskName = if ($Mount.ContainsKey("task_name") -and -not [string]::IsNullOrWhiteSpace([string]$Mount["task_name"])) { [string]$Mount["task_name"] } else { [string]$Mount["mount_id"] }
        $task = Get-ScheduledTask -TaskName $taskName -TaskPath $taskPath -ErrorAction Stop
        return [string]$task.State
    } catch {
        return "missing"
    }
}

function Show-AgentCliMount {
    param([string]$MountId)
    $mount = Get-AgentCliMountById -MountId $MountId
    Write-Output ("mount_id: {0}" -f [string]$mount["mount_id"])
    Write-Output ("name: {0}" -f [string]$mount["name"])
    Write-Output ("status: {0}" -f [string]$mount["status"])
    Write-Output ("task_state: {0}" -f (Get-TaskStateForMount -Mount $mount))
    Write-Output ("task: {0}{1}" -f [string]$mount["task_path"], [string]$mount["task_name"])
    Write-Output ("agent: {0}" -f [string]$mount["agent"])
    Write-Output ("model: {0}" -f [string]$mount["model"])
    Write-Output ("session: {0}" -f [string]$mount["session"])
    Write-Output ("current_session: {0}" -f [string]$mount["current_session"])
    Write-Output ("session_name: {0}" -f [string]$mount["session_name"])
    Write-Output ("cwd: {0}" -f [string]$mount["cwd"])
    Write-Output ("interval_minutes: {0}" -f [string]$mount["interval_minutes"])
    Write-Output ("quiet_minutes: {0}" -f [string]$mount["quiet_minutes"])
    Write-Output ("generation: {0}" -f [string]$mount["generation"])
    Write-Output ("created_at_utc: {0}" -f [string]$mount["created_at_utc"])
    Write-Output ("last_tick_utc: {0}" -f [string]$mount["last_tick_utc"])
    Write-Output ("last_action: {0}" -f [string]$mount["last_action"])
    if ($mount.ContainsKey("last_reason")) { Write-Output ("last_reason: {0}" -f [string]$mount["last_reason"]) }
    if ($mount.ContainsKey("last_schedule_id")) { Write-Output ("last_schedule_id: {0}" -f [string]$mount["last_schedule_id"]) }
    if ($mount.ContainsKey("last_run_id")) { Write-Output ("last_run_id: {0}" -f [string]$mount["last_run_id"]) }
    Write-Output ("state_path: {0}" -f [string]$mount["__path"])
}

function Get-MountRunHistory {
    param(
        [hashtable]$Mount,
        [int]$Last = 5
    )
    $agentName = [string]$Mount["agent"]
    $sessionId = if ($Mount.ContainsKey("session") -and -not [string]::IsNullOrWhiteSpace([string]$Mount["session"])) { [string]$Mount["session"] } elseif ($Mount.ContainsKey("current_session")) { [string]$Mount["current_session"] } else { "" }
    $createdAt = [DateTime]::MinValue
    if ($Mount.ContainsKey("created_at_utc")) { [DateTime]::TryParse([string]$Mount["created_at_utc"], [ref]$createdAt) | Out-Null }
    $runs = @(Get-RunMetadataItems | Where-Object {
        [string]$_["agent"] -eq $agentName -and
        ($createdAt -eq [DateTime]::MinValue -or ([DateTime]::Parse([string]$_["started_at_utc"]).ToUniversalTime() -ge $createdAt.ToUniversalTime())) -and
        ([string]::IsNullOrWhiteSpace($sessionId) -or [string]$_["session_id"] -eq $sessionId -or ($Mount.ContainsKey("last_run_id") -and [string]$_["run_id"] -eq [string]$Mount["last_run_id"]))
    } | Sort-Object started_at_utc)
    if ($Last -gt 0 -and $runs.Count -gt $Last) {
        return @($runs | Select-Object -Last $Last)
    }
    return @($runs)
}

function Write-RunLogSummary {
    param([hashtable]$Run)
    Write-Output ("--- Run {0} | session={1} | round={2} | status={3} | started={4} ---" -f [string]$Run["run_id"], [string]$Run["session_id"], [string]$Run["round"], [string]$Run["status"], [string]$Run["started_at_utc"])
    if ($Run.ContainsKey("prompt") -and -not [string]::IsNullOrWhiteSpace([string]$Run["prompt"])) {
        $prompt = [string]$Run["prompt"]
        if ($prompt.Length -gt 300) { $prompt = $prompt.Substring(0, 300) + "..." }
        Write-Output ("Prompt: {0}" -f $prompt)
    }
    if ($Run.ContainsKey("report_path")) { Write-Output ("Report: {0}" -f [string]$Run["report_path"]) }
    if ($Run.ContainsKey("raw_output_path")) { Write-Output ("Raw: {0}" -f [string]$Run["raw_output_path"]) }
    if ($Run.ContainsKey("event_log_path")) { Write-Output ("Events: {0}" -f [string]$Run["event_log_path"]) }
}

function Show-AgentCliMountLogs {
    param([string[]]$Tokens)
    if (-not $Tokens -or $Tokens.Count -eq 0) {
        Write-AgentCliError "Usage: mycli agent-cli mount logs <mount-id> [--last <n>] [--raw|--events|--report|--paths]"
    }
    $mountId = [string]$Tokens[0]
    $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }
    $parsed = Split-CommandTokens -Tokens $rest
    $options = $parsed["options"]
    $last = if ($options.ContainsKey("last")) { [int]$options["last"] } else { 5 }
    if ($last -lt 1) { $last = 1 }
    $mode = "summary"
    foreach ($candidate in @("raw", "events", "report", "paths")) {
        if ($options.ContainsKey($candidate)) { $mode = $candidate }
    }

    $mount = Get-AgentCliMountById -MountId $mountId
    Write-Output ("Mount: {0} | agent={1} | session={2} | last_action={3}" -f [string]$mount["mount_id"], [string]$mount["agent"], [string]$mount["session"], [string]$mount["last_action"])
    $runs = @(Get-MountRunHistory -Mount $mount -Last $last)
    if ($runs.Count -eq 0) {
        Write-Output "No tracked run logs found for this mount yet."
        return
    }
    foreach ($runObj in $runs) {
        $run = ConvertTo-HashtableDeep -InputObject $runObj
        if ($mode -eq "summary") {
            Write-RunLogSummary -Run $run
            $report = Get-RunReportText -RunMeta $run
            if (-not [string]::IsNullOrWhiteSpace($report)) {
                Write-Output "Report preview:"
                $lines = @($report -split "`r?`n") | Select-Object -First 40
                foreach ($line in $lines) { Write-Output $line }
            }
            Write-Output ""
            continue
        }
        if ($mode -eq "paths") {
            Write-RunLogSummary -Run $run
            Write-Output ""
            continue
        }
        $pathKey = switch ($mode) {
            "raw" { "raw_output_path" }
            "events" { "event_log_path" }
            "report" { "report_path" }
        }
        Write-Output ("--- {0}: {1} ---" -f $mode, [string]$run["run_id"])
        $path = if ($run.ContainsKey($pathKey)) { [string]$run[$pathKey] } else { "" }
        if ([string]::IsNullOrWhiteSpace($path) -or -not (Test-Path -LiteralPath $path)) {
            Write-Output "(log file not found)"
        } else {
            Get-Content -LiteralPath $path -Encoding UTF8 | Write-Output
        }
        Write-Output ""
    }
}

function Remove-AgentCliMount {
    param([string]$MountId)
    if ([string]::IsNullOrWhiteSpace($MountId)) { Write-AgentCliError "Usage: mycli agent-cli mount cancel <mount-id>" }
    $path = Get-MountFilePath -MountId $MountId
    $taskPath = "\agent-cli\mount\"
    $taskName = $MountId
    if (Test-Path -LiteralPath $path) {
        $mount = Get-JsonFile -Path $path
        if ($mount.ContainsKey("task_name")) { $taskName = [string]$mount["task_name"] }
        if ($mount.ContainsKey("task_path")) { $taskPath = [string]$mount["task_path"] }
    }
    try { Unregister-ScheduledTask -TaskName $taskName -TaskPath $taskPath -Confirm:$false -ErrorAction Stop } catch { Write-Output ("Mount task not found or already removed: {0}{1}" -f $taskPath, $taskName) }
    if (Test-Path -LiteralPath $path) { Remove-Item -LiteralPath $path -Force }
    Write-Output ("Cancelled mount: {0}" -f $MountId)
}

function Show-MountHelp {
    @"
agent-cli mount

Usage:
  mycli agent-cli mount add --agent <mapped-agent> [--session <id>] [options]
  mycli agent-cli mount list
  mycli agent-cli mount show <mount-id>
  mycli agent-cli mount logs <mount-id> [--last <n>] [--raw|--events|--report|--paths]
  mycli agent-cli mount tick <mount-id>
  mycli agent-cli mount cancel <mount-id>

Options:
  --model <name>                Model used for heartbeat wake-ups.
  --cwd <path>                  Working directory.
  --session_name <name>         Session name for new sessions.
  --interval_minutes <n>        Lifecycle check interval. Default: 15.
  --quiet_minutes <n>           Treat recent work inside this window as alive. Default: max(interval, 15).
  --heartbeat_prompt <text>     Custom heartbeat prompt. Defaults to built-in lifecycle instructions.
  --end_marker <text>           Marker meaning this lifecycle ended. Default: AGENT_CLI_LIFECYCLE_END.
  --return_mode <stream|silent> Default: silent.
"@ | Write-Output
}

function Handle-MountCommand {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string[]]$Tokens
    )
    if (-not $Tokens -or $Tokens.Count -eq 0 -or $Tokens[0] -eq "--help") { Show-MountHelp; return }
    switch ($Tokens[0]) {
        "add" { $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }; Register-AgentCliMount -Config $Config -Registry $Registry -Tokens $rest; return }
        "list" { Show-AgentCliMounts; return }
        "show" { if ($Tokens.Count -lt 2) { Write-AgentCliError "Usage: mycli agent-cli mount show <mount-id>" }; Show-AgentCliMount -MountId ([string]$Tokens[1]); return }
        "logs" { $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }; Show-AgentCliMountLogs -Tokens $rest; return }
        "tick" { if ($Tokens.Count -lt 2) { Write-AgentCliError "Usage: mycli agent-cli mount tick <mount-id>" }; Invoke-MountTick -Config $Config -Registry $Registry -MountId ([string]$Tokens[1]); return }
        "cancel" { if ($Tokens.Count -lt 2) { Write-AgentCliError "Usage: mycli agent-cli mount cancel <mount-id>" }; Remove-AgentCliMount -MountId ([string]$Tokens[1]); return }
        default { Write-AgentCliError "Unknown mount action '$($Tokens[0])'." }
    }
}

function Invoke-Native {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string[]]$Tokens
    )

    if (-not $Tokens -or $Tokens.Count -eq 0 -or $Tokens -contains '--help' -or $Tokens -contains '-h' -or $Tokens -contains 'help') {
        @"
agent-cli native

Usage:
  mycli agent-cli native [--agent <mapped-agent> | --source <provider>] [--] [native-args...]

Pass arguments through to the selected provider's native CLI. Use -- to separate
agent-cli options from native provider arguments.
"@ | Write-Output
        return
    }

    $passthroughIndex = [Array]::IndexOf($Tokens, "--")
    $passthrough = @()
    $parseTokens = @($Tokens)
    if ($passthroughIndex -ge 0) {
        $passthrough = if ($passthroughIndex -lt ($Tokens.Count - 1)) { @($Tokens[($passthroughIndex + 1)..($Tokens.Count - 1)]) } else { @() }
        $parseTokens = if ($passthroughIndex -gt 0) { @($Tokens[0..($passthroughIndex - 1)]) } else { @() }
    }

    $parsed = Split-CommandTokens -Tokens $parseTokens
    $options = $parsed["options"]
    if ($passthroughIndex -lt 0) {
        $passthrough = @($parsed["positionals"] + $parsed["passthrough"])
    }
    $providerName = $null
    if ($options.ContainsKey("source")) {
        $providerName = [string]$options["source"]
    } elseif ($options.ContainsKey("agent")) {
        $providerName = Get-ProviderFromAgentName -AgentName ([string]$options["agent"])
    } else {
        $providerName = Get-ProviderFromAgentName -AgentName (Get-CurrentAgentName -Config $Config -Registry $Registry)
    }
    if ([string]::IsNullOrWhiteSpace($providerName)) {
        Write-AgentCliError "Native passthrough requires --agent, --source, or a configured current agent."
    }
    $provider = Get-ProviderConfig -Config $Config -ProviderName $providerName
    $environment = Get-ProviderEnvironment -ProviderConfig $provider
    Invoke-ExternalProcess -FilePath ([string]$provider["binary"]) -Arguments $passthrough -Environment $environment
}

function Handle-AgentCommand {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string[]]$Tokens
    )

    if (-not $Tokens -or $Tokens.Count -eq 0) {
        @"
agent-cli agent

Usage:
  mycli agent-cli agent list
  mycli agent-cli agent show <mapped-agent>
  mycli agent-cli agent use <mapped-agent>
  mycli agent-cli agent create --source opencode --name <name> --description <text> [--mode <mode>] [--tools <csv>]
"@ | Write-Output
        return
    }

    switch ($Tokens[0]) {
        "list" { Show-AgentList -Config $Config -Registry $Registry; return }
        "show" {
            if ($Tokens.Count -lt 2) { Write-AgentCliError "Usage: mycli agent-cli agent show <mapped-agent>" }
            Show-Agent -Config $Config -Registry $Registry -Name $Tokens[1]
            return
        }
        "use" {
            if ($Tokens.Count -lt 2) { Write-AgentCliError "Usage: mycli agent-cli agent use <mapped-agent>" }
            Set-CurrentAgent -Config $Config -Registry $Registry -Name $Tokens[1]
            return
        }
        "create" {
            $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }
            Invoke-AgentCreate -Config $Config -Registry $Registry -Tokens $rest
            return
        }
        default { Write-AgentCliError "Unknown agent action '$($Tokens[0])'." }
    }
}

function Handle-SourceCommand {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string[]]$Tokens
    )

    if (-not $Tokens -or $Tokens.Count -eq 0) {
        @"
agent-cli source

Usage:
  mycli agent-cli source list
  mycli agent-cli source show <provider>
"@ | Write-Output
        return
    }
    switch ($Tokens[0]) {
        "list" { Show-SourceList -Config $Config; return }
        "show" {
            if ($Tokens.Count -lt 2) { Write-AgentCliError "Usage: mycli agent-cli source show <provider>" }
            Show-Source -Config $Config -Registry $Registry -ProviderName $Tokens[1]
            return
        }
        default { Write-AgentCliError "Unknown source action '$($Tokens[0])'." }
    }
}

function Handle-SessionCommand {
    param(
        [hashtable]$Config,
        [hashtable]$Registry,
        [string[]]$Tokens
    )

    if (-not $Tokens -or $Tokens.Count -eq 0) {
        @"
agent-cli session

Usage:
  mycli agent-cli session events --session <id> [--round <n> | --last <n> | --all]
  mycli agent-cli session events --last <n>
"@ | Write-Output
        return
    }

    switch ($Tokens[0]) {
        "--help" {
            @"
agent-cli session

Usage:
  mycli agent-cli session events --session <id> [--round <n> | --last <n> | --all]
  mycli agent-cli session events --last <n>
"@ | Write-Output
            return
        }
        "events" {
            $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }
            $parsed = Split-CommandTokens -Tokens $rest
            $options = $parsed["options"]
            
            $sessionId = if ($options.ContainsKey("session")) { [string]$options["session"] } else { "" }
            
            $allMeta = @(Get-RunMetadataItems) | Sort-Object started_at_utc
            
            if ([string]::IsNullOrWhiteSpace($sessionId)) {
                if ($options.ContainsKey("last")) {
                    $lastCount = [int]$options["last"]
                    $allMeta = $allMeta | Select-Object -Last $lastCount
                } else {
                    Write-AgentCliError "Usage: mycli agent-cli session events --last <n> (when not specifying a session)"
                }
            } else {
                $sessionMeta = $allMeta | Where-Object { [string]$_["session_id"] -eq $sessionId }
                if ($sessionMeta.Count -eq 0) {
                    Write-AgentCliError "No records found for session '$sessionId'."
                }
                
                if ($options.ContainsKey("round")) {
                    $roundValue = [string]$options["round"]
                    $sessionMeta = $sessionMeta | Where-Object { [string]$_["round"] -eq $roundValue }
                    if ($sessionMeta.Count -eq 0) {
                        Write-AgentCliError "No records found for session '$sessionId' round '$roundValue'."
                    }
                    $allMeta = $sessionMeta
                } elseif ($options.ContainsKey("all")) {
                    $allMeta = $sessionMeta
                } else {
                    $lastCount = if ($options.ContainsKey("last")) { [int]$options["last"] } else { 1 }
                    $allMeta = $sessionMeta | Select-Object -Last $lastCount
                }
            }
            
            if ($allMeta.Count -eq 0) {
                Write-Output "No event logs found matching criteria."
                return
            }
            
            foreach ($meta in $allMeta) {
                Write-Output ("--- Run ID: {0} | Session: {1} | Round: {2} | Started: {3} ---" -f [string]$meta["run_id"], [string]$meta["session_id"], [string]$meta["round"], [string]$meta["started_at_utc"])
                $logPath = [string]$meta["event_log_path"]
                if (-not [string]::IsNullOrWhiteSpace($logPath) -and (Test-Path -LiteralPath $logPath)) {
                    Get-Content -LiteralPath $logPath -Encoding UTF8 | Write-Output
                } elseif (-not [string]::IsNullOrWhiteSpace([string]$meta["raw_output_path"]) -and (Test-Path -LiteralPath ([string]$meta["raw_output_path"]))) {
                    Write-Output "(No structured event log found, displaying raw output)"
                    Get-Content -LiteralPath ([string]$meta["raw_output_path"]) -Encoding UTF8 | Write-Output
                } else {
                    Write-Output "(No logs available)"
                }
                Write-Output ""
            }
            return
        }
        default {
            Write-AgentCliError "Unknown session action '$($Tokens[0])'."
        }
    }
}

function Invoke-AgentCli {
    param([string[]]$Tokens)

    $Config = Get-ConfigObject
    $Registry = Get-RegistryObject

    if (-not $Tokens -or $Tokens.Count -eq 0) {
        @"
agent-cli

Usage:
  mycli agent-cli <command> [options]

Commands:
  agents                 List mapped agents
  current                Show current default agent
  sync                   Sync providers into registry
  agent                  Manage agents (list, show, use, create)
  source                 Manage providers (list, show)
  session                Inspect stored session event logs
  schedule               Schedule a future agent session wake-up
  mount                  Keep an agent/session alive with lifecycle heartbeats
  run                    Run an agent
  llm-call               Call configured LLM APIs directly by provider/model
  native                 Pass through to native provider CLI
  codex-auto             Manage codex proxy auto-start
  --help                 Show this help text

Direct LLM examples:
  mycli agent-cli llm-call --list-models
  mycli agent-cli llm-call --model "MoreCode/gpt-5.4" --prompt "hello"
  mycli agent-cli llm-call --model "MoreCode/gpt-image-2" --task image-generate --prompt "a watercolor white kitten"

Run 'mycli agent-cli <command> --help' for command-specific help.
"@ | Write-Output
        return
    }

    switch ($Tokens[0]) {
        "--help" {
            @"
agent-cli

Usage:
  mycli agent-cli <command> [options]

Commands:
  agents                 List mapped agents
  current                Show current default agent
  sync                   Sync providers into registry
  agent                  Manage agents (list, show, use, create)
  source                 Manage providers (list, show)
  session                Inspect stored session event logs
  schedule               Schedule a future agent session wake-up
  mount                  Keep an agent/session alive with lifecycle heartbeats
  run                    Run an agent
  llm-call               Call configured LLM APIs directly by provider/model
  native                 Pass through to native provider CLI
  codex-auto             Manage codex proxy auto-start
  --help                 Show this help text

Direct LLM examples:
  mycli agent-cli llm-call --list-models
  mycli agent-cli llm-call --model "MoreCode/gpt-5.4" --prompt "hello"
  mycli agent-cli llm-call --model "MoreCode/gpt-image-2" --task image-generate --prompt "a watercolor white kitten"

Run 'mycli agent-cli <command> --help' for command-specific help.
"@ | Write-Output
            return
        }
        "agents" { Show-AgentList -Config $Config -Registry $Registry; return }
        "current" { Show-CurrentAgent -Config $Config -Registry $Registry; return }
        "sync" {
            $Registry = Invoke-Sync -Config $Config -Registry $Registry
            Write-Output ("Synchronized {0} mapped agent(s)." -f @($Registry["agents"]).Count)
            Write-Output ("Current default agent: {0}" -f (Get-CurrentAgentName -Config $Config -Registry $Registry))
            return
        }
        "agent" {
            $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }
            Handle-AgentCommand -Config $Config -Registry $Registry -Tokens $rest
            return
        }
        "source" {
            $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }
            Handle-SourceCommand -Config $Config -Registry $Registry -Tokens $rest
            return
        }
        "session" {
            $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }
            Handle-SessionCommand -Config $Config -Registry $Registry -Tokens $rest
            return
        }
        "schedule" {
            $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }
            Handle-ScheduleCommand -Config $Config -Registry $Registry -Tokens $rest
            return
        }
        "mount" {
            $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }
            Handle-MountCommand -Config $Config -Registry $Registry -Tokens $rest
            return
        }
        "run" {
            $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }
            Invoke-Run -Config $Config -Registry $Registry -Tokens $rest
            return
        }
        "native" {
            $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }
            Invoke-Native -Config $Config -Registry $Registry -Tokens $rest
            return
        }
        "codex-auto" {
            $rest = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }
            Set-CodexAutoMode -Tokens $rest
            return
        }
        "workflow" {
            Write-Output "workflow is a reserved entry point and is not implemented yet."
            return
        }
        "recommend" {
            Write-Output "recommend is a reserved entry point and is not implemented yet."
            return
        }
        default {
            Write-AgentCliError "Unknown agent-cli action '$($Tokens[0])'. Run 'mycli agent-cli --help' for usage."
        }
    }
}

Invoke-AgentCli -Tokens $CommandArgs
