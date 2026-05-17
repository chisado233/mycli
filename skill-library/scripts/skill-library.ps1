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
$script:WorkspaceConfigModule = Join-Path (Split-Path -Parent $script:PackageRoot) "common\workspace-config.ps1"
. $script:WorkspaceConfigModule
$script:WorkspaceConfig = Get-MyCliWorkspaceConfig -PackagePath 'skill-library'
$script:RegistryPath = Join-Path ([string]$script:WorkspaceConfig.paths.config) "registry.json"
$script:ConfigPath = Join-Path $script:PackageRoot "cli.package.json"
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)
$script:Utf8WithBom = [System.Text.UTF8Encoding]::new($true)

function Write-SkillLibraryError {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Read-Utf8Text {
    param([string]$Path)

    try {
        return [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
    } catch {
        Write-SkillLibraryError "Failed to read UTF-8 text from '$Path'. $($_.Exception.Message)"
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
        Write-SkillLibraryError "Failed to write UTF-8 text to '$Path'. $($_.Exception.Message)"
    }
}

function Get-PackageConfigObject {
    if (-not (Test-Path -LiteralPath $script:ConfigPath)) {
        Write-SkillLibraryError "Package config not found at '$script:ConfigPath'."
    }

    try {
        return (Read-Utf8Text -Path $script:ConfigPath) | ConvertFrom-Json
    } catch {
        Write-SkillLibraryError "Failed to parse package config. $($_.Exception.Message)"
    }
}

function Get-DefaultSourceRoot {
    $config = Get-PackageConfigObject
    if (-not $config.source) {
        Write-SkillLibraryError "Package config does not define a source path."
    }
    return [string]$config.source
}

function Ensure-RegistryFile {
    if (-not (Test-Path -LiteralPath $script:RegistryPath)) {
        Write-Utf8Text -Path $script:RegistryPath -Content "[]`r`n"
    }
}

function Get-RegistryEntries {
    Ensure-RegistryFile

    try {
        $data = (Read-Utf8Text -Path $script:RegistryPath) | ConvertFrom-Json
    } catch {
        Write-SkillLibraryError "Failed to parse registry at '$script:RegistryPath'. $($_.Exception.Message)"
    }

    if ($null -eq $data) {
        return @()
    }

    if ($data -is [System.Array]) {
        return @($data)
    }

    return @($data)
}

function Save-RegistryEntries {
    param([object[]]$Entries)

    $json = @($Entries) | Sort-Object name, skillMdPath | ConvertTo-Json -Depth 10
    Write-Utf8Text -Path $script:RegistryPath -Content $json
}

function Get-FrontmatterValue {
    param(
        [string]$Frontmatter,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Frontmatter)) {
        return $null
    }

    $lines = @($Frontmatter -split "\r?\n")
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line -notmatch "^(?<indent>\s*)$([regex]::Escape($Name)):\s*(?<value>.*)$") {
            continue
        }

        $rawValue = $matches['value'].Trim()
        if ($rawValue -in @('|', '>')) {
            $baseIndent = $matches['indent'].Length
            $collected = New-Object System.Collections.Generic.List[string]
            for ($innerIndex = $index + 1; $innerIndex -lt $lines.Count; $innerIndex++) {
                $innerLine = $lines[$innerIndex]
                if ([string]::IsNullOrWhiteSpace($innerLine)) {
                    $collected.Add("")
                    continue
                }

                $innerIndent = ($innerLine.Length - $innerLine.TrimStart().Length)
                if ($innerIndent -le $baseIndent) {
                    break
                }

                $trimCount = [Math]::Min($innerLine.Length, $baseIndent + 2)
                $collected.Add($innerLine.Substring($trimCount))
            }

            if ($rawValue -eq '>') {
                return (($collected | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }) -join ' ').Trim()
            }

            return (($collected -join "`n").Trim())
        }

        if ([string]::IsNullOrWhiteSpace($rawValue)) {
            return ""
        }

        return $rawValue.Trim().Trim('"').Trim("'")
    }

    return $null
}

function Normalize-Text {
    param([string]$Value)

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return ""
    }

    return (($Value.ToLowerInvariant() -replace '[^\p{L}\p{Nd}]+', ' ').Trim())
}

function Get-TextExcerpt {
    param([string]$Body)

    if ([string]::IsNullOrWhiteSpace($Body)) {
        return ""
    }

    $paragraphs = @($Body -split "(\r?\n){2,}" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($paragraph in $paragraphs) {
        if ($paragraph -match '^```') {
            continue
        }

        $lines = @($paragraph -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if (-not $lines -or $lines.Count -eq 0) {
            continue
        }

        if ($lines[0] -match '^#') {
            if ($lines.Count -gt 1) {
                $candidate = ($lines[1..($lines.Count - 1)] -join ' ').Trim()
                if ($candidate) {
                    return ($candidate.Substring(0, [Math]::Min(220, $candidate.Length)))
                }
            }
            continue
        }

        $candidate = ($lines -join ' ').Trim()
        if ($candidate) {
            return ($candidate.Substring(0, [Math]::Min(220, $candidate.Length)))
        }
    }

    $fallback = (($Body -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -and ($_ -notmatch '^---$') -and ($_ -notmatch '^#') } | Select-Object -First 6) -join ' ').Trim()
    if (-not $fallback) {
        return ""
    }

    return ($fallback.Substring(0, [Math]::Min(220, $fallback.Length)))
}

function Get-SkillMetadataFromFile {
    param([string]$SkillFilePath)

    $raw = Read-Utf8Text -Path $SkillFilePath
    $frontmatter = ""
    $body = $raw

    if ($raw -match "(?s)\A---\r?\n(.*?)\r?\n---\r?\n?(.*)\z") {
        $frontmatter = $matches[1]
        $body = $matches[2]
    }

    $name = $null
    $description = $null

    $name = Get-FrontmatterValue -Frontmatter $frontmatter -Name "name"
    $description = Get-FrontmatterValue -Frontmatter $frontmatter -Name "description"

    if (-not $name) {
        $name = Split-Path -Leaf (Split-Path -Parent $SkillFilePath)
    }
    if (-not $description) {
        $description = Get-TextExcerpt -Body $body
    }

    $bodySummary = Get-TextExcerpt -Body $body
    $skillRootPath = Split-Path -Parent $SkillFilePath

    return [ordered]@{
        name = [string]$name
        description = [string]$description
        bodySummary = [string]$bodySummary
        skillMdPath = [string]$SkillFilePath
        skillRootPath = [string]$skillRootPath
    }
}

function Get-SkillFilesFromPath {
    param([string]$TargetPath)

    if (-not (Test-Path -LiteralPath $TargetPath)) {
        Write-SkillLibraryError "Target path '$TargetPath' does not exist."
    }

    $item = Get-Item -LiteralPath $TargetPath
    if ($item.PSIsContainer) {
        $files = @(
            Get-ChildItem -LiteralPath $TargetPath -Recurse -File |
                Where-Object { $_.Name -ieq 'SKILL.md' } |
                Select-Object -ExpandProperty FullName
        )
        return @($files | Sort-Object -Unique)
    }

    if ($item.Name -ine "SKILL.md") {
        Write-SkillLibraryError "File path '$TargetPath' is not a SKILL.md file."
    }

    return @($item.FullName)
}

function Initialize-RegistryIfNeeded {
    $entries = @(Get-RegistryEntries)
    if ($entries.Count -gt 0) {
        return $entries
    }

    $defaultSource = Get-DefaultSourceRoot
    $skillFiles = @(Get-SkillFilesFromPath -TargetPath $defaultSource)
    if ($skillFiles.Count -eq 0) {
        Save-RegistryEntries -Entries @()
        return @()
    }

    $built = @($skillFiles | ForEach-Object { Get-SkillMetadataFromFile -SkillFilePath $_ })
    Save-RegistryEntries -Entries $built
    return $built
}

function Get-NGramTokens {
    param([string]$Value)

    $text = ($Value -replace '\s+', '')
    if ([string]::IsNullOrWhiteSpace($text)) {
        return @()
    }

    if ($text.Length -lt 2) {
        return @($text.ToCharArray() | ForEach-Object { [string]$_ })
    }

    $tokens = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt ($text.Length - 1); $index++) {
        $tokens.Add($text.Substring($index, 2))
    }
    return @($tokens)
}

function Get-ApproximateScore {
    param(
        [string]$Source,
        [string]$Target
    )

    $sourceTokens = @(Get-NGramTokens -Value $Source)
    $targetTokens = @(Get-NGramTokens -Value $Target)

    if ($sourceTokens.Count -eq 0 -or $targetTokens.Count -eq 0) {
        return 0
    }

    $targetPool = New-Object System.Collections.Generic.List[string]
    foreach ($token in $targetTokens) {
        $targetPool.Add([string]$token)
    }

    $matchedCount = 0
    foreach ($token in $sourceTokens) {
        $matchIndex = $targetPool.IndexOf([string]$token)
        if ($matchIndex -ge 0) {
            $matchedCount += 1
            $targetPool.RemoveAt($matchIndex)
        }
    }

    $denominator = [Math]::Max($sourceTokens.Count, $targetTokens.Count)
    if ($denominator -eq 0) {
        return 0
    }

    return [Math]::Round(($matchedCount / [double]$denominator) * 500)
}

function Get-SearchScore {
    param(
        [object]$Entry,
        [string]$Keyword
    )

    $needle = Normalize-Text -Value $Keyword
    $name = Normalize-Text -Value $Entry.name
    $description = Normalize-Text -Value $Entry.description

    if (-not $needle) {
        return 0
    }

    if ($name -eq $needle) { return 1000 }
    if ($name -like "*$needle*") { return 850 }
    if ($description -like "*$needle*") { return 700 }

    $nameParts = @($name -split ' ' | Where-Object { $_ })
    foreach ($part in $nameParts) {
        if ($part -like "$needle*") {
            return 650
        }
    }

    return (Get-ApproximateScore -Source $name -Target $needle)
}

function Show-SkillEntries {
    param([object[]]$Entries)

    if (-not $Entries -or $Entries.Count -eq 0) {
        Write-Output "No registered skills."
        return
    }

    foreach ($entry in $Entries | Sort-Object name, skillMdPath) {
        Write-Output $entry.name
        Write-Output ("  Summary: {0}" -f $entry.description)
        if ($entry.bodySummary) {
            Write-Output ("  Body: {0}" -f $entry.bodySummary)
        }
        Write-Output ("  Path: {0}" -f $entry.skillRootPath)
    }
}

function Invoke-SkillsCommand {
    $entries = @(Initialize-RegistryIfNeeded)
    Show-SkillEntries -Entries $entries
}

function Invoke-SearchCommand {
    param([string[]]$SearchArgs)

    if (-not $SearchArgs -or $SearchArgs.Count -eq 0) {
        Write-SkillLibraryError "Usage: mycli skill-library search <keyword>"
    }

    $keyword = ($SearchArgs -join ' ').Trim()
    $entries = @(Initialize-RegistryIfNeeded)
    if ($entries.Count -eq 0) {
        Write-Output "No registered skills."
        return
    }

    $scored = @($entries | ForEach-Object {
        [pscustomobject]@{
            entry = $_
            score = Get-SearchScore -Entry $_ -Keyword $keyword
        }
    } | Sort-Object -Property @(
        @{ Expression = { $_.score }; Descending = $true },
        @{ Expression = { $_.entry.name }; Descending = $false }
    ))

    $directMatches = @($scored | Where-Object { $_.score -ge 700 })
    if ($directMatches.Count -gt 0) {
        Write-Output ("Found {0} matching skill(s) for '{1}':" -f $directMatches.Count, $keyword)
        Show-SkillEntries -Entries @($directMatches | ForEach-Object { $_.entry })
        return
    }

    $approximate = @($scored | Where-Object { $_.score -gt 0 } | Select-Object -First 8)
    if ($approximate.Count -eq 0) {
        Write-Output ("No skills matched '{0}'." -f $keyword)
        return
    }

    Write-Output ("No direct match for '{0}'. Similar skills:" -f $keyword)
    Show-SkillEntries -Entries @($approximate | ForEach-Object { $_.entry })
}

function Invoke-RegisterCommand {
    param([string[]]$RegisterArgs)

    $targetPath = if ($RegisterArgs -and $RegisterArgs.Count -gt 0) { $RegisterArgs[0] } else { Get-DefaultSourceRoot }
    $skillFiles = @(Get-SkillFilesFromPath -TargetPath $targetPath)
    if ($skillFiles.Count -eq 0) {
        Write-Output ("No SKILL.md files found under '{0}'." -f $targetPath)
        return
    }

    $existing = @{}
    foreach ($entry in @(Get-RegistryEntries)) {
        $existing[[string]$entry.skillMdPath] = $entry
    }

    $registeredEntries = @()
    foreach ($skillFile in $skillFiles) {
        $entry = Get-SkillMetadataFromFile -SkillFilePath $skillFile
        $existing[$entry.skillMdPath] = [pscustomobject]$entry
        $registeredEntries += [pscustomobject]$entry
    }

    Save-RegistryEntries -Entries @($existing.Values)

    Write-Output ("Registered {0} skill(s) from '{1}'." -f $registeredEntries.Count, $targetPath)
    Show-SkillEntries -Entries $registeredEntries
}

if (-not $CommandArgs -or $CommandArgs.Count -eq 0) {
    @"
skill-library command runner

Usage:
  mycli skill-library skills
  mycli skill-library search <keyword>
  mycli skill-library register [path]
"@ | Write-Output
    exit 0
}

$action = $CommandArgs[0]
$remaining = if ($CommandArgs.Count -gt 1) { @($CommandArgs[1..($CommandArgs.Count - 1)]) } else { @() }

switch ($action) {
    "skills" { Invoke-SkillsCommand }
    "search" { Invoke-SearchCommand -SearchArgs $remaining }
    "register" { Invoke-RegisterCommand -RegisterArgs $remaining }
    default {
        Write-SkillLibraryError "Unknown skill-library action '$action'."
    }
}
