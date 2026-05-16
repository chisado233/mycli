[CmdletBinding()]
param(
    [string]$Action = "help",

    [string]$Lib = "",

    [string]$Root = "",

    [string[]]$Query = @(),

    [string]$Kind = "",

    [string]$Stage = "",

    [string]$Chapter = "",

    [string]$From = "",

    [string]$To = "",

    [string]$Out = "",

    [switch]$Json,

    [switch]$IncludeContent,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$CommandArgs
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$script:WritingRoot = Split-Path -Parent $PSScriptRoot
$script:DefaultRoot = Join-Path $script:WritingRoot "asset-libraries"
$script:TemplateRoot = Join-Path $script:WritingRoot "templates\写作模板\人物势力状态表"
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Write-AssetLibError {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Read-Utf8Text {
    param([string]$Path)
    try { return [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom) }
    catch { Write-AssetLibError "Failed to read '$Path'. $($_.Exception.Message)" }
}

function Write-Utf8Text {
    param([string]$Path, [string]$Content)
    try {
        $parent = Split-Path -Parent $Path
        if ($parent -and -not (Test-Path -LiteralPath $parent)) {
            New-Item -ItemType Directory -Path $parent -Force | Out-Null
        }
        [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom)
    } catch {
        Write-AssetLibError "Failed to write '$Path'. $($_.Exception.Message)"
    }
}

function Normalize-Text {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return (($Value.ToLowerInvariant() -replace '[^\p{L}\p{Nd}]+', ' ').Trim())
}

function Test-ContainsText {
    param([string]$Haystack, [string]$Needle)
    if ([string]::IsNullOrWhiteSpace($Needle)) { return $true }
    return ((Normalize-Text $Haystack) -like "*$(Normalize-Text $Needle)*")
}

function Get-OptionValues {
    param([string[]]$Args, [string]$Name)
    if ($null -eq $Args) { $Args = @() }
    $values = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Args.Count; $i++) {
        $token = [string]$Args[$i]
        if ($token -eq $Name -or $token -eq "-$($Name.TrimStart('-'))") {
            if ($i + 1 -ge $Args.Count) { Write-AssetLibError "Missing value for $Name." }
            $values.Add($Args[$i + 1])
            $i++
        } elseif ($token.StartsWith("$Name=")) {
            $values.Add($token.Substring($Name.Length + 1))
        } elseif ($token.StartsWith("-$($Name.TrimStart('-'))=")) {
            $short = "-$($Name.TrimStart('-'))"
            $values.Add($token.Substring($short.Length + 1))
        }
    }
    return @($values)
}

function Get-PositionalValues {
    param([string[]]$Args)
    if ($null -eq $Args) { return @() }
    $values = New-Object System.Collections.Generic.List[string]
    for ($i = 0; $i -lt $Args.Count; $i++) {
        $token = [string]$Args[$i]
        if ($token.StartsWith("-")) {
            if ($token -match '^(--)?(root|lib|query|kind|stage|chapter|from|to|out)(=.+)?$') {
                if ($token -notlike "*=*" -and $i + 1 -lt $Args.Count) { $i++ }
            }
            continue
        }
        $values.Add($token)
    }
    return @($values)
}

function Get-OptionValue {
    param([string[]]$Args, [string]$Name, [string]$Default = "")
    $values = @(Get-OptionValues -Args $Args -Name $Name)
    if ($values.Count -eq 0) { return $Default }
    return [string]$values[-1]
}

function Has-Flag {
    param([string[]]$Args, [string]$Name)
    if ($null -eq $Args) { return $false }
    return @($Args | Where-Object { $_ -eq $Name }).Count -gt 0
}

function Get-LibRoot {
    param([string[]]$Args)
    $root = Get-OptionValue -Args $Args -Name "--root" -Default $script:DefaultRoot
    return [System.IO.Path]::GetFullPath($root)
}

function Get-LibName {
    param([string[]]$Args)
    $lib = Get-OptionValue -Args $Args -Name "--lib" -Default "default"
    if ($lib -eq "default") {
        $positionals = @(Get-PositionalValues -Args $Args)
        if ($positionals.Count -gt 0) { $lib = [string]$positionals[0] }
    }
    if ([string]::IsNullOrWhiteSpace($lib)) { $lib = "default" }
    if ($lib -match '[\\/:*?"<>|]') { Write-AssetLibError "Invalid library name '$lib'." }
    return $lib
}

function Get-LibPath {
    param([string[]]$Args)
    return (Join-Path (Get-LibRoot -Args $Args) (Get-LibName -Args $Args))
}

function Ensure-Directory {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Copy-TemplateIfExists {
    param([string]$TemplateName, [string]$Destination)
    $source = Join-Path $script:TemplateRoot $TemplateName
    if (Test-Path -LiteralPath $source) {
        Copy-Item -LiteralPath $source -Destination $Destination -Force
    }
}

function Invoke-Init {
    param([string[]]$Args)
    $libPath = Get-LibPath -Args $Args
    Ensure-Directory $libPath

    $dirs = @(
        "assets\characters",
        "assets\factions",
        "states\volume",
        "states\arc",
        "states\five-chapter",
        "states\chapter-interval",
        "snapshots",
        "logs",
        "inbox",
        "composed-context"
    )
    foreach ($dir in $dirs) { Ensure-Directory (Join-Path $libPath $dir) }

    Copy-TemplateIfExists "00-动态资产库说明.md" (Join-Path $libPath "README.md")
    Copy-TemplateIfExists "01-资产总表模板.md" (Join-Path $libPath "01-资产总表.md")
    Copy-TemplateIfExists "02-新增对象收件箱模板.md" (Join-Path $libPath "inbox\新增对象收件箱.md")
    Copy-TemplateIfExists "03-当前状态快照模板.md" (Join-Path $libPath "snapshots\当前状态快照.md")
    Copy-TemplateIfExists "07-状态变更日志模板.md" (Join-Path $libPath "logs\状态变更日志.md")
    Copy-TemplateIfExists "08-状态细化规则.md" (Join-Path $libPath "状态细化规则.md")

    $metaPath = Join-Path $libPath "asset-library.json"
    if (-not (Test-Path -LiteralPath $metaPath)) {
        $meta = [ordered]@{
            name = Get-LibName -Args $Args
            description = "Novel writing dynamic asset library"
            createdAt = (Get-Date).ToString("s")
            version = 1
        } | ConvertTo-Json -Depth 5
        Write-Utf8Text -Path $metaPath -Content $meta
    }

    Write-Output "Initialized asset library: $libPath"
}

function Invoke-Libs {
    param([string[]]$Args)
    $root = Get-LibRoot -Args $Args
    if (-not (Test-Path -LiteralPath $root)) {
        Write-Output "No asset library root found: $root"
        return
    }
    Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name | ForEach-Object {
        $meta = Join-Path $_.FullName "asset-library.json"
        if (Test-Path -LiteralPath $meta) { Write-Output ("{0}`n  Path: {1}" -f $_.Name, $_.FullName) }
    }
}

function Invoke-Info {
    param([string[]]$Args)
    $libPath = Get-LibPath -Args $Args
    if (-not (Test-Path -LiteralPath $libPath)) { Write-AssetLibError "Library not found: $libPath" }
    $files = @(Get-ChildItem -LiteralPath $libPath -Recurse -File -Filter "*.md")
    Write-Output "Asset library: $(Get-LibName -Args $Args)"
    Write-Output "Path: $libPath"
    Write-Output "Markdown files: $($files.Count)"
    foreach ($group in $files | Group-Object { Get-KindFromPath -LibPath $libPath -Path $_.FullName } | Sort-Object Name) {
        Write-Output ("  {0}: {1}" -f $group.Name, $group.Count)
    }
}

function Get-KindFromPath {
    param([string]$LibPath, [string]$Path)
    $rel = [System.IO.Path]::GetRelativePath($LibPath, $Path)
    $norm = $rel -replace '\\','/'
    if ($norm -like 'assets/characters/*') { return 'character' }
    if ($norm -like 'assets/factions/*') { return 'faction' }
    if ($norm -like 'states/*') { return 'state' }
    if ($norm -like 'snapshots/*') { return 'snapshot' }
    if ($norm -like 'logs/*') { return 'log' }
    if ($norm -like 'inbox/*') { return 'inbox' }
    return 'other'
}

function Get-StageFromPath {
    param([string]$LibPath, [string]$Path)
    $rel = [System.IO.Path]::GetRelativePath($LibPath, $Path) -replace '\\','/'
    if ($rel -like 'states/volume/*') { return 'volume' }
    if ($rel -like 'states/arc/*') { return 'arc' }
    if ($rel -like 'states/five-chapter/*') { return 'five-chapter' }
    if ($rel -like 'states/chapter-interval/*') { return 'chapter-interval' }
    return ''
}

function Get-ChapterPatterns {
    param([string[]]$Args)
    $patterns = New-Object System.Collections.Generic.List[string]
    $chapter = Get-OptionValue -Args $Args -Name "--chapter" -Default ""
    if ($chapter) {
        $n = [int]$chapter
        $patterns.Add("第 $n 章")
        $patterns.Add("第$n章")
        $patterns.Add(("ch{0:D3}" -f $n))
        $patterns.Add(("{0:D3}" -f $n))
        $patterns.Add("chapter $n")
    }
    $from = Get-OptionValue -Args $Args -Name "--from" -Default ""
    $to = Get-OptionValue -Args $Args -Name "--to" -Default ""
    if ($from -and $to) {
        $f = [int]$from; $t = [int]$to
        $patterns.Add(("ch{0:D3}-ch{1:D3}" -f $f, $t))
        $patterns.Add(("ch{0:D3}-{1:D3}" -f $f, $t))
        $patterns.Add("第 $f-$t 章")
        $patterns.Add("第$f-$t章")
        $patterns.Add("$f-$t")
    }
    return @($patterns)
}

function Find-Records {
    param([string[]]$Args)
    $libPath = Get-LibPath -Args $Args
    if (-not (Test-Path -LiteralPath $libPath)) { Write-AssetLibError "Library not found: $libPath. Run init first." }

    $kind = Get-OptionValue -Args $Args -Name "--kind" -Default "any"
    $stage = Get-OptionValue -Args $Args -Name "--stage" -Default ""
    $queries = @(Get-OptionValues -Args $Args -Name "--query")
    $chapterPatterns = @(Get-ChapterPatterns -Args $Args)

    $files = @(Get-ChildItem -LiteralPath $libPath -Recurse -File -Filter "*.md" | Sort-Object FullName)
    $records = New-Object System.Collections.Generic.List[object]
    foreach ($file in $files) {
        $path = $file.FullName
        $rel = [System.IO.Path]::GetRelativePath($libPath, $path)
        $fileKind = Get-KindFromPath -LibPath $libPath -Path $path
        $fileStage = Get-StageFromPath -LibPath $libPath -Path $path
        if ($kind -ne "any" -and $kind -ne $fileKind) { continue }
        if ($stage -and -not (Test-ContainsText "$rel $fileStage" $stage)) { continue }
        $body = Read-Utf8Text -Path $path
        $haystack = "$rel`n$body"
        $matched = $true
        foreach ($q in $queries) {
            if (-not (Test-ContainsText $haystack $q)) { $matched = $false; break }
        }
        if ($matched -and $chapterPatterns.Count -gt 0) {
            $chapterMatched = $false
            foreach ($p in $chapterPatterns) {
                if (Test-ContainsText $haystack $p) { $chapterMatched = $true; break }
            }
            if (-not $chapterMatched) { $matched = $false }
        }
        if (-not $matched) { continue }
        $excerpt = (($body -split "\r?\n" | Where-Object { $_.Trim() } | Select-Object -First 8) -join "`n")
        $records.Add([pscustomobject]@{ kind=$fileKind; stage=$fileStage; path=$path; relativePath=$rel; excerpt=$excerpt; content=$body })
    }
    return @($records)
}

function Invoke-Search {
    param([string[]]$Args)
    $records = @(Find-Records -Args $Args)
    if (Has-Flag -Args $Args -Name "--json") {
        $records | Select-Object kind, stage, relativePath, path, excerpt | ConvertTo-Json -Depth 5
        return
    }
    if ($records.Count -eq 0) { Write-Output "No matching asset records."; return }
    $includeContent = Has-Flag -Args $Args -Name "--include-content"
    foreach ($record in $records) {
        Write-Output ("[{0}] {1}" -f $record.kind, $record.relativePath)
        Write-Output ("  Path: {0}" -f $record.path)
        if ($record.stage) { Write-Output ("  Stage: {0}" -f $record.stage) }
        if ($includeContent) {
            Write-Output "  --- excerpt ---"
            Write-Output $record.excerpt
        }
    }
}

function Invoke-Compose {
    param([string[]]$Args)
    $records = @(Find-Records -Args $Args)
    if ($records.Count -eq 0) { Write-AssetLibError "No matching records to compose." }
    $libPath = Get-LibPath -Args $Args
    $out = Get-OptionValue -Args $Args -Name "--out" -Default ""
    if (-not $out) {
        $stamp = Get-Date -Format "yyyyMMdd-HHmmss"
        $out = Join-Path $libPath "composed-context\context-$stamp.md"
    }

    $title = "# 动态资产库合成上下文`n"
    $meta = @"

## 合成信息

- 子库：$(Get-LibName -Args $Args)
- 子库路径：$libPath
- 生成时间：$(Get-Date -Format s)
- 命中数量：$($records.Count)

---

"@
    $parts = New-Object System.Collections.Generic.List[string]
    $parts.Add($title + $meta)
    foreach ($record in $records) {
        $parts.Add("## [$($record.kind)] $($record.relativePath)`n`n来源：`$($record.path)`n`n```markdown`n$($record.content)`n```n")
    }
    Write-Utf8Text -Path $out -Content ($parts -join "`n---`n")
    Write-Output $out
}

function Show-Help {
@"
novel-writing writing asset-lib

Usage:
  mycli novel-writing writing asset-lib init --lib <name> [--root <path>]
  mycli novel-writing writing asset-lib libs [--root <path>]
  mycli novel-writing writing asset-lib info --lib <name> [--root <path>]
  mycli novel-writing writing asset-lib path --lib <name> [--root <path>]
  mycli novel-writing writing asset-lib search --lib <name> [--query <text>] [--kind <kind>] [--chapter <n>] [--from <n> --to <n>] [--json]
  mycli novel-writing writing asset-lib compose --lib <name> [--query <text>] [--kind <kind>] [--chapter <n>] [--out <path>]

Kinds:
  any, character, faction, state, snapshot, log, inbox, other
"@ | Write-Output
}

if ($null -eq $CommandArgs) { $CommandArgs = @() } else { $CommandArgs = @($CommandArgs) }
if ($MyInvocation.UnboundArguments -and $MyInvocation.UnboundArguments.Count -gt 0) {
    $CommandArgs = @($CommandArgs) + @($MyInvocation.UnboundArguments | ForEach-Object { [string]$_ })
}

$boundArgs = New-Object System.Collections.Generic.List[string]
if ($Lib) { $boundArgs.Add("--lib"); $boundArgs.Add($Lib) }
if ($Root) { $boundArgs.Add("--root"); $boundArgs.Add($Root) }
if ($Query) { foreach ($q in $Query) { if ($q) { $boundArgs.Add("--query"); $boundArgs.Add($q) } } }
if ($Kind) { $boundArgs.Add("--kind"); $boundArgs.Add($Kind) }
if ($Stage) { $boundArgs.Add("--stage"); $boundArgs.Add($Stage) }
if ($Chapter) { $boundArgs.Add("--chapter"); $boundArgs.Add($Chapter) }
if ($From) { $boundArgs.Add("--from"); $boundArgs.Add($From) }
if ($To) { $boundArgs.Add("--to"); $boundArgs.Add($To) }
if ($Out) { $boundArgs.Add("--out"); $boundArgs.Add($Out) }
if ($Json) { $boundArgs.Add("--json") }
if ($IncludeContent) { $boundArgs.Add("--include-content") }
$CommandArgs = @($CommandArgs) + @($boundArgs)

if ($Action -and $Action -ne "help" -and $Action -notin @('init','libs','info','path','search','compose')) {
    $CommandArgs = @([string]$Action) + @($CommandArgs)
}

if ($CommandArgs.Count -gt 0 -and $CommandArgs[0] -eq "asset-lib") {
    $CommandArgs = if ($CommandArgs.Count -gt 1) { @($CommandArgs[1..($CommandArgs.Count - 1)]) } else { @() }
}

$knownActions = @('help','init','libs','info','path','search','compose')
$tokens = @()
if ($Action -and $Action -ne 'help') { $tokens += [string]$Action }
$tokens += @($CommandArgs)

$action = $null
$actionIndex = -1
for ($i = 0; $i -lt $tokens.Count; $i++) {
    $token = [string]$tokens[$i]
    if ($token -in $knownActions) {
        $action = $token
        $actionIndex = $i
        break
    }
}

if (-not $action) {
    Show-Help
    exit 0
}

$remaining = @()
if ($actionIndex -ge 0 -and $actionIndex + 1 -lt $tokens.Count) {
    $remaining = @($tokens[($actionIndex + 1)..($tokens.Count - 1)])
}

switch ($action) {
    "help" { Show-Help }
    "init" { Invoke-Init -Args $remaining }
    "libs" { Invoke-Libs -Args $remaining }
    "info" { Invoke-Info -Args $remaining }
    "path" { Write-Output (Get-LibPath -Args $remaining) }
    "search" { Invoke-Search -Args $remaining }
    "compose" { Invoke-Compose -Args $remaining }
    default { Write-AssetLibError "Unknown asset-lib action '$action'. Use: help, init, libs, info, path, search, compose." }
}
