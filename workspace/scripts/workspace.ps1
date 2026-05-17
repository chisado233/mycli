param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [object[]]$Arguments
)

$ErrorActionPreference = 'Stop'

$ArgumentList = New-Object System.Collections.Generic.List[string]
foreach ($argument in @($Arguments)) {
    if ($null -eq $argument) { continue }
    if ($argument -is [System.Array]) {
        foreach ($item in $argument) {
            if ($null -ne $item) { $ArgumentList.Add([string]$item) | Out-Null }
        }
    } else {
        $ArgumentList.Add([string]$argument) | Out-Null
    }
}
$ArgumentArray = [string[]]$ArgumentList.ToArray()

$WorkspaceRoot = 'D:\agent_workspace'
$RootNames = @('tmp', 'var', 'logs', 'cache', 'config', 'data', 'downloads', 'backups', 'ui', 'tools', 'models')
$ScopedRootNames = @('tmp', 'var', 'logs', 'cache', 'config', 'data', 'downloads', 'backups', 'ui')
$Domains = @('mycli', 'projects', 'skills', 'agents', 'shared')

function Write-Usage {
    @'
Usage:
  mycli workspace root
  mycli workspace paths [--json]
  mycli workspace path <root> <domain> <name...>
  mycli workspace inspect <domain> <name...> [--json]
  mycli workspace config-path <domain> <name...>
  mycli workspace config <domain> <name...> [--json]
  mycli workspace ensure [--json]
  mycli workspace ensure <domain> <name...> [--json]
  mycli workspace ensure-package <package-path> [--json]
  mycli workspace ensure-project <project-id-or-path> [--json]
  mycli workspace ensure-skill <skill-name-or-path> [--json]

Roots:
  tmp, var, logs, cache, config, data, downloads, backups, ui, tools, models

Domains:
  mycli, projects, skills, agents, shared
'@
}

function Test-JsonFlag {
    param([string[]]$Items)
    return @($Items) -contains '--json'
}

function Test-HelpFlag {
    param([string[]]$Items)
    return @($Items) -contains '--help' -or @($Items) -contains '-h' -or @($Items) -contains 'help'
}

function Remove-Flags {
    param([string[]]$Items)
    return @($Items | Where-Object { $_ -ne '--json' })
}

function ConvertTo-SafeSegments {
    param([string[]]$Items)

    $segments = New-Object System.Collections.Generic.List[string]
    foreach ($item in @($Items)) {
        if ([string]::IsNullOrWhiteSpace($item)) { continue }
        $normalized = $item -replace '/', '\'
        foreach ($part in ($normalized -split '\\+')) {
            if ([string]::IsNullOrWhiteSpace($part)) { continue }
            if ($part -eq '.' -or $part -eq '..') {
                throw "Invalid path segment '$part'."
            }
            if ($part -ne $part.Trim() -or $part.EndsWith('.')) {
                throw "Invalid leading/trailing whitespace or trailing dot in path segment '$part'."
            }
            if ($part -match '[\[\]]') {
                throw "Invalid wildcard character in path segment '$part'."
            }
            if ([System.IO.Path]::IsPathRooted($part)) {
                throw "Invalid rooted path segment '$part'."
            }
            $invalidChars = [System.IO.Path]::GetInvalidFileNameChars()
            if ($part.IndexOfAny($invalidChars) -ge 0) {
                throw "Invalid character in path segment '$part'."
            }
            if ($part -match '^(?i)(CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM[1-9]|LPT[1-9])(\..*)?$') {
                throw "Reserved Windows device name in path segment '$part'."
            }
            $segments.Add($part) | Out-Null
        }
    }

    if ($segments.Count -eq 0) {
        throw 'At least one name/path segment is required.'
    }

    return @($segments)
}

function Resolve-ProjectName {
    param([string[]]$Items)
    $itemList = @($Items)
    if ($itemList.Length -eq 1 -and -not [string]::IsNullOrWhiteSpace($itemList[0])) {
        $value = $itemList[0]
        if ([System.IO.Path]::IsPathRooted($value) -or $value -match '[\\/]') {
            return ConvertTo-SafeSegments @((Split-Path -Leaf $value.TrimEnd('\', '/')))
        }
    }
    return ConvertTo-SafeSegments $itemList
}

function Resolve-SkillName {
    param([string[]]$Items)
    $itemList = @($Items)
    if ($itemList.Length -eq 1 -and -not [string]::IsNullOrWhiteSpace($itemList[0])) {
        $value = $itemList[0]
        if ([System.IO.Path]::IsPathRooted($value) -or $value -match '[\\/]') {
            $leaf = Split-Path -Leaf $value.TrimEnd('\', '/')
            if ($leaf -ieq 'SKILL.md') {
                $leaf = Split-Path -Leaf (Split-Path -Parent $value)
            }
            return ConvertTo-SafeSegments @($leaf)
        }
    }
    return ConvertTo-SafeSegments $itemList
}

function Resolve-WorkspacePath {
    param(
        [string]$RootName,
        [string]$Domain,
        [string[]]$NameSegments
    )

    if ($RootNames -notcontains $RootName) {
        throw "Unknown root '$RootName'. Allowed: $($RootNames -join ', ')."
    }
    if ($Domains -notcontains $Domain) {
        throw "Unknown domain '$Domain'. Allowed: $($Domains -join ', ')."
    }

    $path = [System.IO.Path]::Combine($WorkspaceRoot, $RootName)
    $path = [System.IO.Path]::Combine($path, $Domain)
    foreach ($segment in (ConvertTo-SafeSegments $NameSegments)) {
        $path = [System.IO.Path]::Combine($path, $segment)
    }
    return $path
}

function New-DirectoryIfMissing {
    param([string]$Path)

    Assert-WorkspaceTarget -Path $Path

    $created = $false
    if (Test-Path -LiteralPath $Path) {
        if (-not (Test-Path -LiteralPath $Path -PathType Container)) {
            throw "Path exists but is not a directory: $Path"
        }
    } else {
        [System.IO.Directory]::CreateDirectory($Path) | Out-Null
        $created = $true
    }

    [pscustomobject]@{
        path = $Path
        created = $created
        exists = Test-Path -LiteralPath $Path -PathType Container
    }
}

function Assert-WorkspaceTarget {
    param([string]$Path)

    $rootFullPath = [System.IO.Path]::GetFullPath($WorkspaceRoot).TrimEnd('\')
    $targetFullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ($targetFullPath -ne $rootFullPath -and -not $targetFullPath.StartsWith($rootFullPath + '\', [System.StringComparison]::OrdinalIgnoreCase)) {
        throw "Refusing to write outside workspace root '$WorkspaceRoot': $Path"
    }

    $current = $targetFullPath
    while ($current -and $current.StartsWith($rootFullPath, [System.StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $current) {
            $item = Get-Item -LiteralPath $current -Force
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Refusing to write through reparse point: $current"
            }
        }
        if ($current -eq $rootFullPath) { break }
        $parent = Split-Path -Parent $current
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $current) { break }
        $current = $parent.TrimEnd('\')
    }
}

function Get-RootRows {
    foreach ($rootName in $RootNames) {
        [pscustomobject]@{
            name = $rootName
            path = Join-Path $WorkspaceRoot $rootName
            scoped = $ScopedRootNames -contains $rootName
        }
    }
}

function Get-ScopedRows {
    param(
        [string]$Domain,
        [string[]]$NameSegments
    )

    foreach ($rootName in $ScopedRootNames) {
        [pscustomobject]@{
            root = $rootName
            domain = $Domain
            name = ($NameSegments -join '/')
            path = Resolve-WorkspacePath -RootName $rootName -Domain $Domain -NameSegments $NameSegments
        }
    }
}

function Get-WorkspaceConfigPath {
    param(
        [string]$Domain,
        [string[]]$NameSegments
    )

    $configRoot = Resolve-WorkspacePath -RootName 'config' -Domain $Domain -NameSegments $NameSegments
    return [System.IO.Path]::Combine($configRoot, 'workspace-config.json')
}

function New-WorkspaceConfigObject {
    param(
        [string]$Domain,
        [string[]]$NameSegments
    )

    $safeSegments = ConvertTo-SafeSegments $NameSegments
    $paths = [ordered]@{}
    foreach ($rootName in $ScopedRootNames) {
        $paths[$rootName] = Resolve-WorkspacePath -RootName $rootName -Domain $Domain -NameSegments $safeSegments
    }

    [pscustomobject]@{
        schema = 'mycli.workspace-config.v1'
        domain = $Domain
        name = ($safeSegments -join '/')
        workspaceRoot = $WorkspaceRoot
        generatedAt = (Get-Date).ToString('o')
        paths = $paths
    }
}

function Save-WorkspaceConfig {
    param(
        [string]$Domain,
        [string[]]$NameSegments
    )

    $safeSegments = ConvertTo-SafeSegments $NameSegments
    $configDirectory = Resolve-WorkspacePath -RootName 'config' -Domain $Domain -NameSegments $safeSegments
    New-DirectoryIfMissing $configDirectory | Out-Null
    $configPath = Get-WorkspaceConfigPath -Domain $Domain -NameSegments $safeSegments
    Assert-WorkspaceTarget -Path $configPath
    $config = New-WorkspaceConfigObject -Domain $Domain -NameSegments $safeSegments
    $jsonText = $config | ConvertTo-Json -Depth 8
    [System.IO.File]::WriteAllText($configPath, $jsonText + [Environment]::NewLine, [System.Text.UTF8Encoding]::new($false))
    [pscustomobject]@{
        path = $configPath
        created = $true
        exists = Test-Path -LiteralPath $configPath -PathType Leaf
    }
}

function Write-TableRows {
    param([object[]]$Rows)
    foreach ($row in $Rows) {
        if ($row.PSObject.Properties.Name -contains 'root') {
            "{0,-9} {1}" -f $row.root, $row.path
        } else {
            "{0,-9} {1}" -f $row.name, $row.path
        }
    }
}

function Ensure-BaseWorkspace {
    $results = New-Object System.Collections.Generic.List[object]
    $results.Add((New-DirectoryIfMissing $WorkspaceRoot)) | Out-Null
    foreach ($rootName in $RootNames) {
        $rootPath = Join-Path $WorkspaceRoot $rootName
        $results.Add((New-DirectoryIfMissing $rootPath)) | Out-Null
        if ($ScopedRootNames -contains $rootName) {
            foreach ($domain in $Domains) {
                $results.Add((New-DirectoryIfMissing (Join-Path $rootPath $domain))) | Out-Null
            }
        }
    }
    return $results.ToArray()
}

function Ensure-ScopedWorkspace {
    param(
        [string]$Domain,
        [string[]]$NameSegments
    )

    $results = New-Object System.Collections.Generic.List[object]
    foreach ($item in (Ensure-BaseWorkspace)) {
        $results.Add($item) | Out-Null
    }
    foreach ($row in (Get-ScopedRows -Domain $Domain -NameSegments $NameSegments)) {
        $results.Add((New-DirectoryIfMissing $row.path)) | Out-Null
    }
    $results.Add((Save-WorkspaceConfig -Domain $Domain -NameSegments $NameSegments)) | Out-Null
    return $results.ToArray()
}

$argsNoFlags = [string[]]@(Remove-Flags $ArgumentArray)
if ($null -eq $argsNoFlags) { $argsNoFlags = [string[]]@() }
$json = Test-JsonFlag $ArgumentArray
$command = if ($argsNoFlags.Length -gt 0) { $argsNoFlags[0] } else { '--help' }
$rest = [string[]]$(if ($argsNoFlags.Length -gt 1) { @($argsNoFlags[1..($argsNoFlags.Length - 1)]) } else { @() })
if ($null -eq $rest) { $rest = [string[]]@() }

if ($command -notin @('--help', '-h', 'help') -and (Test-HelpFlag $rest)) {
    Write-Usage
    exit 0
}

try {
    switch ($command) {
        '--help' { Write-Usage }
        '-h' { Write-Usage }
        'help' { Write-Usage }
        'root' { $WorkspaceRoot }
        'paths' {
            $rows = @(Get-RootRows)
            if ($json) { $rows | ConvertTo-Json -Depth 5 } else { Write-TableRows $rows }
        }
        'path' {
            if ($rest.Length -lt 3) { throw 'Usage: mycli workspace path <root> <domain> <name...>' }
            $path = Resolve-WorkspacePath -RootName $rest[0] -Domain $rest[1] -NameSegments @($rest[2..($rest.Length - 1)])
            $path
        }
        'inspect' {
            if ($rest.Length -lt 2) { throw 'Usage: mycli workspace inspect <domain> <name...>' }
            $segments = ConvertTo-SafeSegments @($rest[1..($rest.Length - 1)])
            $rows = @(Get-ScopedRows -Domain $rest[0] -NameSegments $segments)
            if ($json) { $rows | ConvertTo-Json -Depth 5 } else { Write-TableRows $rows }
        }
        'config-path' {
            if ($rest.Length -lt 2) { throw 'Usage: mycli workspace config-path <domain> <name...>' }
            $segments = ConvertTo-SafeSegments @($rest[1..($rest.Length - 1)])
            Get-WorkspaceConfigPath -Domain $rest[0] -NameSegments $segments
        }
        'config' {
            if ($rest.Length -lt 2) { throw 'Usage: mycli workspace config <domain> <name...>' }
            $segments = ConvertTo-SafeSegments @($rest[1..($rest.Length - 1)])
            $configPath = Get-WorkspaceConfigPath -Domain $rest[0] -NameSegments $segments
            if (-not (Test-Path -LiteralPath $configPath -PathType Leaf)) {
                Save-WorkspaceConfig -Domain $rest[0] -NameSegments $segments | Out-Null
            }
            if ($json) {
                Get-Content -LiteralPath $configPath -Raw
            } else {
                $configPath
            }
        }
        'ensure' {
            if ($rest.Length -eq 0) {
                $rows = @(Ensure-BaseWorkspace)
            } else {
                if ($rest.Length -lt 2) { throw 'Usage: mycli workspace ensure <domain> <name...>' }
                $segments = ConvertTo-SafeSegments @($rest[1..($rest.Length - 1)])
                $rows = @(Ensure-ScopedWorkspace -Domain $rest[0] -NameSegments $segments)
            }
            if ($json) { $rows | ConvertTo-Json -Depth 5 } else { $rows | ForEach-Object { "{0} {1}" -f ($(if ($_.created) { 'created' } else { 'exists ' })), $_.path } }
        }
        'ensure-package' {
            if ($rest.Length -lt 1) { throw 'Usage: mycli workspace ensure-package <package-path>' }
            $segments = ConvertTo-SafeSegments $rest
            $rows = @(Ensure-ScopedWorkspace -Domain 'mycli' -NameSegments $segments)
            if ($json) { $rows | ConvertTo-Json -Depth 5 } else { $rows | ForEach-Object { "{0} {1}" -f ($(if ($_.created) { 'created' } else { 'exists ' })), $_.path } }
        }
        'ensure-project' {
            if ($rest.Length -lt 1) { throw 'Usage: mycli workspace ensure-project <project-id-or-path>' }
            $segments = Resolve-ProjectName $rest
            $rows = @(Ensure-ScopedWorkspace -Domain 'projects' -NameSegments $segments)
            if ($json) { $rows | ConvertTo-Json -Depth 5 } else { $rows | ForEach-Object { "{0} {1}" -f ($(if ($_.created) { 'created' } else { 'exists ' })), $_.path } }
        }
        'ensure-skill' {
            if ($rest.Length -lt 1) { throw 'Usage: mycli workspace ensure-skill <skill-name-or-path>' }
            $segments = Resolve-SkillName $rest
            $rows = @(Ensure-ScopedWorkspace -Domain 'skills' -NameSegments $segments)
            if ($json) { $rows | ConvertTo-Json -Depth 5 } else { $rows | ForEach-Object { "{0} {1}" -f ($(if ($_.created) { 'created' } else { 'exists ' })), $_.path } }
        }
        default {
            throw "Unknown workspace command '$command'. Run: mycli workspace --help"
        }
    }
} catch {
    Write-Error $_.Exception.Message
    exit 1
}
