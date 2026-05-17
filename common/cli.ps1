[CmdletBinding()]
param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CliArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$Script:CliRoot = Split-Path -Parent $PSScriptRoot
$Script:PackageFileName = "cli.package.json"
$Script:ReadmeFileName = "README.md"
$Script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$Script:Utf8WithBom = [System.Text.UTF8Encoding]::new($true)

function Read-Utf8Text {
    param([string]$Path)

    try {
        return [System.IO.File]::ReadAllText($Path, $Script:Utf8NoBom)
    } catch {
        Write-CliError "Failed to read UTF-8 text from '$Path'. $($_.Exception.Message)"
    }
}

function Write-Utf8Text {
    param(
        [string]$Path,
        [string]$Content,
        [bool]$EmitBom = $true
    )

    try {
        $encoding = if ($EmitBom) { $Script:Utf8WithBom } else { $Script:Utf8NoBom }
        [System.IO.File]::WriteAllText($Path, $Content, $encoding)
    } catch {
        Write-CliError "Failed to write UTF-8 text to '$Path'. $($_.Exception.Message)"
    }
}

function Get-RootReadmePath {
    return Join-Path $Script:CliRoot $Script:ReadmeFileName
}

function Write-CliError {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Get-OptionBundle {
    param([string[]]$Tokens)

    $tokenList = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Tokens)) {
        if ($null -ne $item) {
            $tokenList.Add([string]$item)
        }
    }

    $options = @{}
    $positionals = New-Object System.Collections.Generic.List[string]

    $i = 0
    while ($i -lt $tokenList.Count) {
        $token = $tokenList[$i]
        if ($token.StartsWith("--")) {
            $name = $token.Substring(2)
            if ([string]::IsNullOrWhiteSpace($name)) {
                Write-CliError "Invalid option name in token '$token'."
            }

            if (($i + 1) -lt $tokenList.Count -and -not $tokenList[$i + 1].StartsWith("--")) {
                $options[$name] = $tokenList[$i + 1]
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
        Options = $options
        Positionals = [string[]]$positionals
    }
}

function Get-PackageSegmentsFromString {
    param([string]$PackagePath)

    if ([string]::IsNullOrWhiteSpace($PackagePath)) {
        Write-CliError "Package path cannot be empty."
    }

    $segments = @($PackagePath -split "[\\/]" | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
    if (-not $segments -or $segments.Count -eq 0) {
        Write-CliError "Package path '$PackagePath' is invalid."
    }

    return [string[]]$segments
}

function Get-PackageDirectory {
    param([string[]]$Segments)

    $current = $Script:CliRoot
    foreach ($segment in $Segments) {
        $current = Join-Path $current $segment
    }
    return $current
}

function Get-PackageConfigPath {
    param([string[]]$Segments)

    return Join-Path (Get-PackageDirectory -Segments $Segments) $Script:PackageFileName
}

function Get-PackageReadmePath {
    param([string[]]$Segments)

    return Join-Path (Get-PackageDirectory -Segments $Segments) $Script:ReadmeFileName
}

function Test-PackageExists {
    param([string[]]$Segments)

    return Test-Path -LiteralPath (Get-PackageConfigPath -Segments $Segments)
}

function Get-OptionalMemberValue {
    param(
        [object]$InputObject,
        [string]$Name
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        if ($InputObject.Contains($Name)) {
            return $InputObject[$Name]
        }
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -ne $property) {
        return $property.Value
    }

    return $null
}

function ConvertTo-NormalizedCommand {
    param([object]$Command)

    if (-not $Command.name) {
        Write-CliError "Each command requires a 'name'."
    }
    if (-not $Command.summary) {
        Write-CliError "Command '$($Command.name)' requires a 'summary'."
    }
    if (-not $Command.entry) {
        Write-CliError "Command '$($Command.name)' requires an 'entry'."
    }
    if (-not [System.IO.Path]::IsPathRooted([string]$Command.entry)) {
        Write-CliError "Command '$($Command.name)' entry must be an absolute path."
    }

    $argsValue = @()
    if ($null -ne $Command.args) {
        $argsValue = @($Command.args)
    }
    $prefixArgsValue = @()
    $rawPrefixArgs = Get-OptionalMemberValue -InputObject $Command -Name "prefixArgs"
    if ($null -ne $rawPrefixArgs) {
        $prefixArgsValue = @($rawPrefixArgs)
    }

    foreach ($arg in $argsValue) {
        if (-not $arg.name) {
            Write-CliError "Command '$($Command.name)' has an argument without 'name'."
        }
        if ($null -eq $arg.required) {
            Write-CliError "Command '$($Command.name)' argument '$($arg.name)' requires 'required'."
        }
        if (-not $arg.summary) {
            Write-CliError "Command '$($Command.name)' argument '$($arg.name)' requires 'summary'."
        }
    }
    foreach ($prefixArg in $prefixArgsValue) {
        if ($null -eq $prefixArg) {
            Write-CliError "Command '$($Command.name)' prefixArgs cannot contain null."
        }
    }

    return [ordered]@{
        name = [string]$Command.name
        summary = [string]$Command.summary
        args = @($argsValue | ForEach-Object {
            $typeValue = Get-OptionalMemberValue -InputObject $_ -Name "type"
            $defaultValue = Get-OptionalMemberValue -InputObject $_ -Name "default"
            [ordered]@{
                name = [string]$_.name
                required = [bool]$_.required
                summary = [string]$_.summary
                type = if ($null -ne $typeValue) { [string]$typeValue } else { $null }
                default = $defaultValue
            }
        })
        prefixArgs = @($prefixArgsValue | ForEach-Object { [string]$_ })
        entry = [string]$Command.entry
    }
}

function Get-JsonValue {
    param(
        [hashtable]$Options,
        [string]$Name,
        [switch]$Required,
        [switch]$ArrayExpected
    )

    if (-not $Options.ContainsKey($Name)) {
        if ($Required) {
            Write-CliError "Missing required option --$Name."
        }
        return $null
    }

    try {
        $value = $Options[$Name] | ConvertFrom-Json
    } catch {
        Write-CliError "Option --$Name must be valid JSON. $($_.Exception.Message)"
    }

    if ($ArrayExpected) {
        if ($value -is [string]) {
            Write-CliError "Option --$Name must be a JSON array."
        }

        if ($value -is [System.Array]) {
            return $value
        }

        return @($value)
    }

    return $value
}

function New-PackageConfigObject {
    param(
        [string[]]$Segments,
        [string]$Summary,
        [string]$Source,
        [object[]]$Commands
    )

    return [ordered]@{
        name = $Segments[-1]
        summary = $Summary
        source = $Source
        commands = @($Commands)
    }
}

function Save-PackageConfig {
    param(
        [string[]]$Segments,
        [hashtable]$Config
    )

    $configPath = Get-PackageConfigPath -Segments $Segments
    $json = $Config | ConvertTo-Json -Depth 20
    Write-Utf8Text -Path $configPath -Content $json
}

function Get-PackageConfig {
    param([string[]]$Segments)

    $configPath = Get-PackageConfigPath -Segments $Segments
    if (-not (Test-Path -LiteralPath $configPath)) {
        Write-CliError "Package '$($Segments -join ' ')' is not registered."
    }

    try {
        $config = (Read-Utf8Text -Path $configPath) | ConvertFrom-Json
    } catch {
        Write-CliError "Failed to read package config at '$configPath'. $($_.Exception.Message)"
    }

    $commands = @()
    if ($null -ne $config.commands) {
        $commands = @($config.commands)
    }

    return [ordered]@{
        name = [string]$config.name
        summary = [string]$config.summary
        source = [string]$config.source
        commands = @($commands | ForEach-Object { ConvertTo-NormalizedCommand -Command $_ })
    }
}

function New-DefaultReadme {
    param(
        [string[]]$Segments,
        [string]$Summary,
        [string]$Source
    )

    $packageName = $Segments[-1]
    return @(
        "# $packageName",
        "",
        "## Summary",
        "",
        $Summary,
        "",
        "## Source",
        "",
        $Source,
        "",
        "## Command List",
        "",
        "- Add command details here.",
        "",
        "## Command Details",
        "",
        "### Example Command",
        "",
        "Describe the command here.",
        "",
        "Parameters:",
        "",
        '- `name`: describe the parameter here',
        "",
        "## Usage Examples",
        "",
        '```powershell',
        "cli $($Segments -join ' ') list",
        '```'
    ) -join "`n"
}

function Ensure-PackageDirectory {
    param([string[]]$Segments)

    $dir = Get-PackageDirectory -Segments $Segments
    if (-not (Test-Path -LiteralPath $dir)) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

function Ensure-AncestorPackages {
    param(
        [string[]]$Segments,
        [string]$Source
    )

    if ($Segments.Count -le 1) {
        return
    }

    for ($i = 1; $i -lt $Segments.Count; $i++) {
        $ancestorSegments = $Segments[0..($i - 1)]
        if (Test-PackageExists -Segments $ancestorSegments) {
            continue
        }

        Ensure-PackageDirectory -Segments $ancestorSegments
        $ancestorSummary = "Container package for $($ancestorSegments[-1])"
        $ancestorConfig = New-PackageConfigObject -Segments $ancestorSegments -Summary $ancestorSummary -Source $Source -Commands @()
        Save-PackageConfig -Segments $ancestorSegments -Config $ancestorConfig

        $ancestorReadmePath = Get-PackageReadmePath -Segments $ancestorSegments
        if (-not (Test-Path -LiteralPath $ancestorReadmePath)) {
            Write-Utf8Text -Path $ancestorReadmePath -Content (New-DefaultReadme -Segments $ancestorSegments -Summary $ancestorSummary -Source $Source)
        }
    }
}

function Register-Package {
    param(
        [string[]]$Segments,
        [string]$Summary,
        [string]$Source,
        [object[]]$Commands = @(),
        [string]$HelpContent
    )

    if (Test-PackageExists -Segments $Segments) {
        Write-CliError "Package '$($Segments -join ' ')' is already registered."
    }

    Ensure-AncestorPackages -Segments $Segments -Source $Source
    Ensure-PackageDirectory -Segments $Segments

    $normalizedCommands = @($Commands | ForEach-Object { ConvertTo-NormalizedCommand -Command $_ })
    $config = New-PackageConfigObject -Segments $Segments -Summary $Summary -Source $Source -Commands $normalizedCommands
    Save-PackageConfig -Segments $Segments -Config $config

    $readmePath = Get-PackageReadmePath -Segments $Segments
    if ($PSBoundParameters.ContainsKey("HelpContent") -and $null -ne $HelpContent) {
        Write-Utf8Text -Path $readmePath -Content $HelpContent
    } elseif (-not (Test-Path -LiteralPath $readmePath)) {
        Write-Utf8Text -Path $readmePath -Content (New-DefaultReadme -Segments $Segments -Summary $Summary -Source $Source)
    }

    Write-Output "Registered package '$($Segments -join ' ')'."
}

function Get-TopLevelPackageSegments {
    $dirs = Get-ChildItem -LiteralPath $Script:CliRoot -Directory | Where-Object { $_.Name -ne "common" }
    $results = @()
    foreach ($dir in $dirs) {
        $configPath = Join-Path $dir.FullName $Script:PackageFileName
        if (Test-Path -LiteralPath $configPath) {
            $results += ,@($dir.Name)
        }
    }
    return $results
}

function Get-SubpackageSegments {
    param([string[]]$ParentSegments)

    $parentDir = Get-PackageDirectory -Segments $ParentSegments
    if (-not (Test-Path -LiteralPath $parentDir)) {
        return @()
    }

    $dirs = Get-ChildItem -LiteralPath $parentDir -Directory
    $results = @()
    foreach ($dir in $dirs) {
        $configPath = Join-Path $dir.FullName $Script:PackageFileName
        if (Test-Path -LiteralPath $configPath) {
            $results += ,($ParentSegments + $dir.Name)
        }
    }
    return @($results)
}

function Format-ArgsSignature {
    param([object[]]$ArgItems)

    $ArgItems = @($ArgItems)
    if (-not $ArgItems -or $ArgItems.Count -eq 0) {
        return "(none)"
    }

    $parts = foreach ($arg in $ArgItems) {
        if ($arg.required) {
            "<$($arg.name)>"
        } else {
            "[$($arg.name)]"
        }
    }
    return ($parts -join " ")
}

function Format-ArgDescriptions {
    param([object[]]$ArgItems)

    $ArgItems = @($ArgItems)
    if (-not $ArgItems -or $ArgItems.Count -eq 0) {
        return "(none)"
    }

    return (($ArgItems | ForEach-Object {
        $pieces = @()
        $pieces += $_.name
        $pieces += if ($_.required) { "required" } else { "optional" }
        $pieces += $_.summary
        if ($_.type) {
            $pieces += "type=$($_.type)"
        }
        if ($null -ne $_.default -and "$($_.default)" -ne "") {
            $pieces += "default=$($_.default)"
        }
        ($pieces -join ", ")
    }) -join "; ")
}

function Show-RootHelp {
    $readmePath = Get-RootReadmePath
    if (-not (Test-Path -LiteralPath $readmePath)) {
        Write-CliError "Root README not found at '$readmePath'."
    }

    Read-Utf8Text -Path $readmePath | Write-Output
}

function Show-RootPackages {
    $packages = Get-TopLevelPackageSegments
    if (-not $packages -or $packages.Count -eq 0) {
        Write-Output "No registered packages."
        return
    }

    Write-Output "Packages"
    Write-Output "--------"
    foreach ($segments in $packages) {
        $config = Get-PackageConfig -Segments $segments
        Write-Output ("{0} - {1}" -f ($segments -join " "), $config.summary)
    }
}

function Show-PackageHelp {
    param([string[]]$Segments)

    $readmePath = Get-PackageReadmePath -Segments $Segments
    if (-not (Test-Path -LiteralPath $readmePath)) {
        Write-CliError "Package README not found at '$readmePath'."
    }

    Read-Utf8Text -Path $readmePath | Write-Output
}

function Show-PackageList {
    param([string[]]$Segments)

    $subpackages = @(Get-SubpackageSegments -ParentSegments $Segments)
    $config = Get-PackageConfig -Segments $Segments
    $commands = @($config.commands)

    Write-Output "Subpackages"
    Write-Output "-----------"
    if ($subpackages.Count -eq 0) {
        Write-Output "(none)"
    } else {
        foreach ($subpackage in $subpackages) {
            $subConfig = Get-PackageConfig -Segments $subpackage
            Write-Output ("{0} - {1}" -f $subpackage[-1], $subConfig.summary)
        }
    }

    Write-Output ""
    Write-Output "Commands"
    Write-Output "--------"
    if ($commands.Count -eq 0) {
        Write-Output "(none)"
        return
    }

    foreach ($command in $commands) {
        Write-Output ("{0}" -f $command.name)
        Write-Output ("  Summary: {0}" -f $command.summary)
        Write-Output ("  Args: {0}" -f (Format-ArgsSignature -ArgItems $command.args))
        Write-Output ("  Arg Details: {0}" -f (Format-ArgDescriptions -ArgItems $command.args))
    }
}

function Show-CommandList {
    param([string[]]$Segments)

    $config = Get-PackageConfig -Segments $Segments
    $commands = @($config.commands)
    if ($commands.Count -eq 0) {
        Write-Output "No commands registered in package '$($Segments -join ' ')'."
        return
    }

    foreach ($command in $commands) {
        Write-Output ("{0}" -f $command.name)
        Write-Output ("  Summary: {0}" -f $command.summary)
        Write-Output ("  Args: {0}" -f (Format-ArgsSignature -ArgItems $command.args))
        Write-Output ("  Arg Details: {0}" -f (Format-ArgDescriptions -ArgItems $command.args))
        if ($command.prefixArgs -and @($command.prefixArgs).Count -gt 0) {
            Write-Output ("  Prefix Args: {0}" -f ((@($command.prefixArgs)) -join " "))
        }
        Write-Output ("  Entry: {0}" -f $command.entry)
    }
}

function Find-PackageMatch {
    param([string[]]$Tokens)

    $Tokens = if ($null -eq $Tokens) { @() } else { @($Tokens) }
    $bestCount = 0
    for ($i = 1; $i -le $Tokens.Count; $i++) {
        $segments = $Tokens[0..($i - 1)]
        if (Test-PackageExists -Segments $segments) {
            $bestCount = $i
            continue
        }

        # As soon as a longer prefix stops matching a registered package,
        # the remaining tokens belong to package actions, command names, or args.
        if ($bestCount -gt 0) {
            break
        }

        # Package paths always start at the first token, so if the first segment
        # is not a package there is no need to keep scanning.
        break
    }

    if ($bestCount -eq 0) {
        return $null
    }

    return [ordered]@{
        Segments = [string[]]$Tokens[0..($bestCount - 1)]
        Remaining = @(
            if ($bestCount -lt $Tokens.Count) {
                $Tokens[$bestCount..($Tokens.Count - 1)]
            }
        )
    }
}

function Add-CommandToPackage {
    param(
        [string[]]$Segments,
        [hashtable]$CommandData
    )

    $config = Get-PackageConfig -Segments $Segments
    if ($config.commands | Where-Object { $_.name -eq $CommandData.name }) {
        Write-CliError "Command '$($CommandData.name)' already exists in package '$($Segments -join ' ')'."
    }

    $config.commands += ,$CommandData
    Save-PackageConfig -Segments $Segments -Config $config
    Write-Output "Registered command '$($CommandData.name)' in package '$($Segments -join ' ')'."
}

function Update-CommandInPackage {
    param(
        [string[]]$Segments,
        [string]$CommandName,
        [hashtable]$Options
    )

    $config = Get-PackageConfig -Segments $Segments
    $command = $config.commands | Where-Object { $_.name -eq $CommandName } | Select-Object -First 1
    if (-not $command) {
        Write-CliError "Command '$CommandName' was not found in package '$($Segments -join ' ')'."
    }

    if ($Options.ContainsKey("summary")) {
        $command.summary = [string]$Options["summary"]
    }
    if ($Options.ContainsKey("entry")) {
        if (-not [System.IO.Path]::IsPathRooted([string]$Options["entry"])) {
            Write-CliError "Option --entry must be an absolute path."
        }
        $command.entry = [string]$Options["entry"]
    }
    if ($Options.ContainsKey("prefix-args")) {
        $prefixArgs = Get-JsonValue -Options $Options -Name "prefix-args" -ArrayExpected
        $command.prefixArgs = @($prefixArgs | ForEach-Object { [string]$_ })
    }
    if ($Options.ContainsKey("args")) {
        $parsedArgs = Get-JsonValue -Options $Options -Name "args" -ArrayExpected
        $command.args = @($parsedArgs | ForEach-Object {
            if (-not $_.name) {
                Write-CliError "Each argument in --args must contain 'name'."
            }
            if ($null -eq $_.required) {
                Write-CliError "Argument '$($_.name)' in --args requires 'required'."
            }
            if (-not $_.summary) {
                Write-CliError "Argument '$($_.name)' in --args requires 'summary'."
            }
            $typeValue = Get-OptionalMemberValue -InputObject $_ -Name "type"
            $defaultValue = Get-OptionalMemberValue -InputObject $_ -Name "default"
            [ordered]@{
                name = [string]$_.name
                required = [bool]$_.required
                summary = [string]$_.summary
                type = if ($null -ne $typeValue) { [string]$typeValue } else { $null }
                default = $defaultValue
            }
        })
    }

    $config.commands = @($config.commands | ForEach-Object {
        if ($_.name -eq $CommandName) {
            ConvertTo-NormalizedCommand -Command $command
        } else {
            ConvertTo-NormalizedCommand -Command $_
        }
    })

    Save-PackageConfig -Segments $Segments -Config $config
    Write-Output "Updated command '$CommandName' in package '$($Segments -join ' ')'."
}

function Handle-PackageManagement {
    param([string[]]$Tokens)

    $Tokens = if ($null -eq $Tokens) { @() } else { @($Tokens) }
    if ($Tokens.Count -eq 0 -or $Tokens[0] -eq "--help") {
        @"
Package management

Usage:
  mycli package list
  mycli package register <package/path> --summary <text> --source <text>
  mycli package register-full <package/path> --summary <text> --source <text> --commands <json> --help <markdown>
"@ | Write-Output
        return
    }

    $action = $Tokens[0]
    $remainingTokens = if ($Tokens.Count -gt 1) { @($Tokens[1..($Tokens.Count - 1)]) } else { @() }
    $bundle = Get-OptionBundle -Tokens $remainingTokens
    $positionals = $bundle.Positionals
    $options = $bundle.Options

    switch ($action) {
        "list" {
            Show-RootPackages
        }
        "register" {
            if ($options.ContainsKey("help") -and $positionals.Count -eq 0) {
                Write-Output "Usage: mycli package register <package/path> --summary <text> --source <text>"
                return
            }
            if ($positionals.Count -lt 1) {
                Write-CliError "Usage: mycli package register <package/path> --summary <text> --source <text>"
            }
            if (-not $options.ContainsKey("summary") -or -not $options.ContainsKey("source")) {
                Write-CliError "Package registration requires --summary and --source."
            }
            Register-Package -Segments (Get-PackageSegmentsFromString -PackagePath $positionals[0]) -Summary ([string]$options["summary"]) -Source ([string]$options["source"])
        }
        "register-full" {
            if ($options.ContainsKey("help") -and $positionals.Count -eq 0) {
                Write-Output "Usage: mycli package register-full <package/path> --summary <text> --source <text> --commands <json> --help <markdown>"
                return
            }
            if ($positionals.Count -lt 1) {
                Write-CliError "Usage: mycli package register-full <package/path> --summary <text> --source <text> --commands <json> --help <markdown>"
            }
            foreach ($requiredName in @("summary", "source", "commands", "help")) {
                if (-not $options.ContainsKey($requiredName)) {
                    Write-CliError "Package register-full requires --$requiredName."
                }
            }
            $commands = Get-JsonValue -Options $options -Name "commands" -Required -ArrayExpected
            Register-Package -Segments (Get-PackageSegmentsFromString -PackagePath $positionals[0]) -Summary ([string]$options["summary"]) -Source ([string]$options["source"]) -Commands @($commands) -HelpContent ([string]$options["help"])
        }
        default {
            Write-CliError "Unknown package action '$action'."
        }
    }
}

function Handle-CommandManagement {
    param(
        [string[]]$PackageSegments,
        [string[]]$Tokens
    )

    $Tokens = if ($null -eq $Tokens) { @() } else { @($Tokens) }
    if ($Tokens.Count -eq 0 -or $Tokens[0] -eq "--help") {
        @"
Command management for package '$($PackageSegments -join ' ')'

Usage:
  mycli $($PackageSegments -join ' ') command list
  mycli $($PackageSegments -join ' ') command register <name> --summary <text> --entry <absolute-path> --args <json> [--prefix-args <json>]
  mycli $($PackageSegments -join ' ') command register-many --commands <json>
  mycli $($PackageSegments -join ' ') command update <name> [--summary <text>] [--entry <absolute-path>] [--args <json>] [--prefix-args <json>]
"@ | Write-Output
        return
    }

    $action = $Tokens[0]
    $remaining = if ($Tokens.Count -gt 1) { $Tokens[1..($Tokens.Count - 1)] } else { @() }
    $bundle = Get-OptionBundle -Tokens $remaining
    $positionals = $bundle.Positionals
    $options = $bundle.Options

    switch ($action) {
        "list" {
            Show-CommandList -Segments $PackageSegments
        }
        "register" {
            if ($options.ContainsKey("help")) {
                Write-Output "Usage: mycli $($PackageSegments -join ' ') command register <name> --summary <text> --entry <absolute-path> --args <json> [--prefix-args <json>]"
                return
            }
            if ($positionals.Count -lt 1) {
                Write-CliError "Usage: mycli $($PackageSegments -join ' ') command register <name> --summary <text> --entry <absolute-path> --args <json> [--prefix-args <json>]"
            }
            foreach ($requiredName in @("summary", "entry", "args")) {
                if (-not $options.ContainsKey($requiredName)) {
                    Write-CliError "Command registration requires --$requiredName."
                }
            }
            $parsedArgs = Get-JsonValue -Options $options -Name "args" -Required -ArrayExpected
            $commandData = ConvertTo-NormalizedCommand -Command ([ordered]@{
                name = $positionals[0]
                summary = [string]$options["summary"]
                args = @($parsedArgs)
                prefixArgs = if ($options.ContainsKey("prefix-args")) { @((Get-JsonValue -Options $options -Name "prefix-args" -ArrayExpected)) } else { @() }
                entry = [string]$options["entry"]
            })
            Add-CommandToPackage -Segments $PackageSegments -CommandData $commandData
        }
        "register-many" {
            if ($options.ContainsKey("help")) {
                Write-Output "Usage: mycli $($PackageSegments -join ' ') command register-many --commands <json>"
                return
            }
            if (-not $options.ContainsKey("commands")) {
                Write-CliError "Usage: mycli $($PackageSegments -join ' ') command register-many --commands <json>"
            }
            $commands = @((Get-JsonValue -Options $options -Name "commands" -Required -ArrayExpected))
            foreach ($command in $commands) {
                Add-CommandToPackage -Segments $PackageSegments -CommandData (ConvertTo-NormalizedCommand -Command $command)
            }
        }
        "update" {
            if ($options.ContainsKey("help")) {
                Write-Output "Usage: mycli $($PackageSegments -join ' ') command update <name> [--summary <text>] [--entry <absolute-path>] [--args <json>] [--prefix-args <json>]"
                return
            }
            if ($positionals.Count -lt 1) {
                Write-CliError "Usage: mycli $($PackageSegments -join ' ') command update <name> [--summary <text>] [--entry <absolute-path>] [--args <json>] [--prefix-args <json>]"
            }
            Update-CommandInPackage -Segments $PackageSegments -CommandName $positionals[0] -Options $options
        }
        default {
            Write-CliError "Unknown command action '$action'."
        }
    }
}

function Handle-HelpManagement {
    param(
        [string[]]$PackageSegments,
        [string[]]$Tokens
    )

    $Tokens = if ($null -eq $Tokens) { @() } else { @($Tokens) }
    if ($Tokens.Count -eq 0 -or $Tokens[0] -eq "--help") {
        @"
Help management for package '$($PackageSegments -join ' ')'

Usage:
  mycli $($PackageSegments -join ' ') help update --content <markdown>
"@ | Write-Output
        return
    }

    $action = $Tokens[0]
    $bundle = if ($Tokens.Count -gt 1) { Get-OptionBundle -Tokens $Tokens[1..($Tokens.Count - 1)] } else { @{ Options = @{}; Positionals = @() } }

    switch ($action) {
        "update" {
            if ($bundle.Options.ContainsKey("help")) {
                Write-Output "Usage: mycli $($PackageSegments -join ' ') help update --content <markdown>"
                return
            }
            if (-not $bundle.Options.ContainsKey("content")) {
                Write-CliError "Usage: mycli $($PackageSegments -join ' ') help update --content <markdown>"
            }
            $readmePath = Get-PackageReadmePath -Segments $PackageSegments
            Write-Utf8Text -Path $readmePath -Content ([string]$bundle.Options["content"])
            Write-Output "Updated README for package '$($PackageSegments -join ' ')'."
        }
        default {
            Write-CliError "Unknown help action '$action'."
        }
    }
}

function Invoke-RegisteredCommand {
    param(
        [string[]]$PackageSegments,
        [string]$CommandName,
        [string[]]$RemainingArgs
    )

    $config = Get-PackageConfig -Segments $PackageSegments
    $command = $config.commands | Where-Object { $_.name -eq $CommandName } | Select-Object -First 1
    if (-not $command) {
        Write-CliError "Unknown command '$CommandName' in package '$($PackageSegments -join ' ')'."
    }
    if (-not (Test-Path -LiteralPath $command.entry)) {
        Write-CliError "Command entry '$($command.entry)' does not exist."
    }

    if ($RemainingArgs -contains '--help' -or $RemainingArgs -contains '-h' -or $RemainingArgs -contains 'help') {
        Write-Output ("mycli {0} {1}" -f ($PackageSegments -join ' '), $CommandName)
        if (-not [string]::IsNullOrWhiteSpace([string]$command.summary)) {
            Write-Output ""
            Write-Output ([string]$command.summary)
        }
        $args = @($command.args)
        if ($args.Count -gt 0) {
            Write-Output ""
            Write-Output "Arguments:"
            foreach ($arg in $args) {
                $required = if ($arg.required) { "required" } else { "optional" }
                $type = if ($arg.type) { [string]$arg.type } else { "string" }
                $summary = if ($arg.summary) { [string]$arg.summary } else { "" }
                Write-Output ("  {0} ({1}, {2}) {3}" -f [string]$arg.name, $type, $required, $summary)
            }
        }
        return
    }

    $prefixArgs = @()
    if ($null -ne $command.prefixArgs) {
        $prefixArgs = @($command.prefixArgs)
    }
    & $command.entry @prefixArgs @RemainingArgs
    $exitCodeVariable = Get-Variable -Name LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue
    $exitCode = if ($null -ne $exitCodeVariable) { $exitCodeVariable.Value } else { $null }
    if ($null -ne $exitCode -and $exitCode -ne 0) {
        exit $exitCode
    }
}

function Invoke-Cli {
    param([string[]]$Tokens)

    $Tokens = if ($null -eq $Tokens) { @() } else { @($Tokens) }
    if (-not $Tokens -or $Tokens.Count -eq 0) {
        Show-RootHelp
        return
    }

    switch ($Tokens[0]) {
        "--help" { Show-RootHelp; return }
        "help" { Show-RootHelp; return }
        "list" { Show-RootPackages; return }
        "package" {
            $remaining = if ($Tokens.Count -gt 1) { $Tokens[1..($Tokens.Count - 1)] } else { @() }
            Handle-PackageManagement -Tokens $remaining
            return
        }
    }

    $packageMatch = Find-PackageMatch -Tokens $Tokens
    if (-not $packageMatch) {
        Write-CliError "Unknown package or command path '$($Tokens -join ' ')'."
    }

    $packageSegments = $packageMatch.Segments
    $remaining = $packageMatch.Remaining

    if (-not $remaining -or $remaining.Count -eq 0) {
        Show-PackageHelp -Segments $packageSegments
        return
    }

    switch ($remaining[0]) {
        "--help" { Show-PackageHelp -Segments $packageSegments; return }
        "help" {
            if ($remaining.Count -eq 1) {
                Show-PackageHelp -Segments $packageSegments
                return
            }
            Handle-HelpManagement -PackageSegments $packageSegments -Tokens $remaining[1..($remaining.Count - 1)]
            return
        }
        "list" { Show-PackageList -Segments $packageSegments; return }
        "command" {
            $next = if ($remaining.Count -gt 1) { $remaining[1..($remaining.Count - 1)] } else { @() }
            Handle-CommandManagement -PackageSegments $packageSegments -Tokens $next
            return
        }
        default {
            $commandArgs = if ($remaining.Count -gt 1) { $remaining[1..($remaining.Count - 1)] } else { @() }
            Invoke-RegisteredCommand -PackageSegments $packageSegments -CommandName $remaining[0] -RemainingArgs $commandArgs
            return
        }
    }
}

Invoke-Cli -Tokens $CliArgs
