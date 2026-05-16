$ErrorActionPreference = "Stop"
Set-StrictMode -Version Latest
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$script:MaterialRoot = "D:\agent_workspace\capability-library\mycli\novel-writing\material-library"
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Write-MaterialLibraryError {
    param([string]$Message)
    Write-Error $Message
    exit 1
}

function Read-Utf8Text {
    param([string]$Path)
    return [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom)
}

function Normalize-Text {
    param([string]$Value)
    if ([string]::IsNullOrWhiteSpace($Value)) { return "" }
    return (($Value.ToLowerInvariant() -replace '[^\p{L}\p{Nd}]+', ' ').Trim())
}

function Get-FrontmatterValue {
    param(
        [string]$Frontmatter,
        [string]$Name
    )

    if ([string]::IsNullOrWhiteSpace($Frontmatter)) { return $null }

    $lines = @($Frontmatter -split "\r?\n")
    for ($index = 0; $index -lt $lines.Count; $index++) {
        $line = $lines[$index]
        if ($line -notmatch "^(?<indent>\s*)$([regex]::Escape($Name)):\s*(?<value>.*)$") { continue }

        $rawValue = $matches['value'].Trim()
        if (-not [string]::IsNullOrWhiteSpace($rawValue)) {
            return $rawValue.Trim().Trim('"').Trim("'")
        }

        $baseIndent = $matches['indent'].Length
        $collected = New-Object System.Collections.Generic.List[string]
        for ($innerIndex = $index + 1; $innerIndex -lt $lines.Count; $innerIndex++) {
            $innerLine = $lines[$innerIndex]
            if ([string]::IsNullOrWhiteSpace($innerLine)) { continue }
            $innerIndent = ($innerLine.Length - $innerLine.TrimStart().Length)
            if ($innerIndent -le $baseIndent) { break }

            $trimmed = $innerLine.Trim()
            if ($trimmed -match '^[-*]\s+(?<item>.+)$') {
                $collected.Add($matches['item'].Trim().Trim('"').Trim("'"))
            } else {
                $collected.Add($trimmed.Trim('"').Trim("'"))
            }
        }
        return @($collected)
    }

    return $null
}

function Get-TextExcerpt {
    param([string]$Body)
    if ([string]::IsNullOrWhiteSpace($Body)) { return "" }

    $paragraphs = @($Body -split "(\r?\n){2,}" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
    foreach ($paragraph in $paragraphs) {
        if ($paragraph -match '^```') { continue }
        $lines = @($paragraph -split "\r?\n" | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        if (-not $lines -or $lines.Count -eq 0) { continue }

        if ($lines[0] -match '^#') {
            if ($lines.Count -gt 1) {
                $candidate = ($lines[1..($lines.Count - 1)] -join ' ').Trim()
                if ($candidate) { return $candidate.Substring(0, [Math]::Min(180, $candidate.Length)) }
            }
            continue
        }

        $candidate = ($lines -join ' ').Trim()
        if ($candidate) { return $candidate.Substring(0, [Math]::Min(180, $candidate.Length)) }
    }
    return ""
}

function Get-ScalarValue {
    param($Value)
    if ($Value -is [array]) { return [string]($Value -join ' ') }
    return [string]$Value
}

function Get-MaterialRecords {
    if (-not (Test-Path -LiteralPath $script:MaterialRoot -PathType Container)) {
        Write-MaterialLibraryError "Material library root not found: $script:MaterialRoot"
    }

    $files = @(
        Get-ChildItem -LiteralPath $script:MaterialRoot -File -Filter '*.md' -Recurse |
            Where-Object { $_.Name -notin @('README.md', 'TAG-GUIDE.md') } |
            Sort-Object FullName
    )

    foreach ($file in $files) {
        $raw = Read-Utf8Text -Path $file.FullName
        $frontmatter = ""
        $body = $raw
        if ($raw -match "(?s)\A---\r?\n(.*?)\r?\n---\r?\n?(.*)\z") {
            $frontmatter = $matches[1]
            $body = $matches[2]
        }

        $name = Get-ScalarValue (Get-FrontmatterValue -Frontmatter $frontmatter -Name "name")
        if ([string]::IsNullOrWhiteSpace($name)) { $name = [System.IO.Path]::GetFileNameWithoutExtension($file.Name) }

        $description = Get-ScalarValue (Get-FrontmatterValue -Frontmatter $frontmatter -Name "description")
        if ([string]::IsNullOrWhiteSpace($description)) { $description = Get-TextExcerpt -Body $body }

        $source = Get-ScalarValue (Get-FrontmatterValue -Frontmatter $frontmatter -Name "source")
        if ([string]::IsNullOrWhiteSpace($source)) { $source = "未知" }

        $tagValue = Get-FrontmatterValue -Frontmatter $frontmatter -Name "tag"
        $tags = @()
        if ($tagValue -is [array]) {
            $tags = @($tagValue | ForEach-Object { [string]$_ } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
        } elseif (-not [string]::IsNullOrWhiteSpace([string]$tagValue)) {
            $tags = @(([string]$tagValue).Split(',') | ForEach-Object { $_.Trim() } | Where-Object { $_ })
        }

        $relativePath = [System.IO.Path]::GetRelativePath($script:MaterialRoot, $file.FullName)
        $category = $relativePath.Split([System.IO.Path]::DirectorySeparatorChar, [System.IO.Path]::AltDirectorySeparatorChar)[0]

        [pscustomobject]@{
            name = $name
            description = $description
            source = $source
            tag = @($tags)
            category = $category
            path = $file.FullName
            relativePath = $relativePath
            bodyExcerpt = Get-TextExcerpt -Body $body
            searchableText = (($name, $description, $source, $category, $relativePath, $body) -join "`n")
        }
    }
}

function Get-NGramTokens {
    param([string]$Value)
    $text = (Normalize-Text -Value $Value) -replace '\s+', ''
    if ([string]::IsNullOrWhiteSpace($text)) { return @() }
    if ($text.Length -lt 2) { return @($text.ToCharArray() | ForEach-Object { [string]$_ }) }
    $tokens = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt ($text.Length - 1); $index++) { $tokens.Add($text.Substring($index, 2)) }
    return @($tokens)
}

function Get-RoughTextScore {
    param(
        [object]$Record,
        [string]$Query
    )

    $needle = Normalize-Text -Value $Query
    if (-not $needle) { return 0 }

    $name = Normalize-Text -Value $Record.name
    $description = Normalize-Text -Value $Record.description
    $source = Normalize-Text -Value $Record.source
    $category = Normalize-Text -Value $Record.category
    $path = Normalize-Text -Value $Record.relativePath
    $body = Normalize-Text -Value $Record.searchableText

    $score = 0
    if ($name -eq $needle) { $score += 1200 }
    elseif ($name -like "*$needle*") { $score += 950 }
    if ($description -like "*$needle*") { $score += 650 }
    if ($source -like "*$needle*") { $score += 600 }
    if ($category -like "*$needle*") { $score += 300 }
    if ($path -like "*$needle*") { $score += 220 }
    if ($body -like "*$needle*") { $score += 120 }
    if ($score -gt 0) { return $score }

    $queryTokens = @(Get-NGramTokens -Value $needle)
    $bodyTokens = @(Get-NGramTokens -Value (($Record.name, $Record.description, $Record.source, $Record.bodyExcerpt) -join ' '))
    if ($queryTokens.Count -eq 0 -or $bodyTokens.Count -eq 0) { return -1 }

    $bodySet = @{}
    foreach ($token in $bodyTokens) { $bodySet[$token] = $true }
    $matched = 0
    foreach ($token in $queryTokens) { if ($bodySet.ContainsKey($token)) { $matched += 1 } }
    $ratio = $matched / [double]$queryTokens.Count
    if ($ratio -lt 0.5) { return -1 }
    return [Math]::Round($ratio * 80)
}

function Test-ExactTags {
    param(
        [object]$Record,
        [string[]]$RequiredTags
    )
    if ($RequiredTags.Count -eq 0) { return $true }
    $normalizedRecordTags = @($Record.tag | ForEach-Object { Normalize-Text -Value ([string]$_) })
    foreach ($requiredTag in $RequiredTags) {
        if ($normalizedRecordTags -notcontains (Normalize-Text -Value $requiredTag)) { return $false }
    }
    return $true
}

function Test-SourceMatch {
    param(
        [object]$Record,
        [string[]]$Sources,
        [string[]]$SourceContains
    )
    $recordSource = Normalize-Text -Value $Record.source
    foreach ($source in $Sources) {
        if ($recordSource -ne (Normalize-Text -Value $source)) { return $false }
    }
    foreach ($sourcePart in $SourceContains) {
        $needle = Normalize-Text -Value $sourcePart
        if ($needle -and $recordSource -notlike "*$needle*") { return $false }
    }
    return $true
}

function Get-SearchScore {
    param(
        [object]$Record,
        [string[]]$TextQueries,
        [string[]]$RequiredTags,
        [string]$Category,
        [string[]]$Sources,
        [string[]]$SourceContains
    )

    if (-not (Test-ExactTags -Record $Record -RequiredTags $RequiredTags)) { return -1 }
    if (-not (Test-SourceMatch -Record $Record -Sources $Sources -SourceContains $SourceContains)) { return -1 }
    if (-not [string]::IsNullOrWhiteSpace($Category)) {
        if ((Normalize-Text -Value $Record.category) -ne (Normalize-Text -Value $Category)) { return -1 }
    }

    if ($TextQueries.Count -eq 0) { return 1 }
    $score = 0
    foreach ($query in $TextQueries) {
        $queryScore = Get-RoughTextScore -Record $Record -Query $query
        if ($queryScore -lt 0) { return -1 }
        $score += $queryScore
    }
    return $score
}

function Show-MaterialRecords {
    param(
        [object[]]$Records,
        [bool]$AsJson
    )

    if ($AsJson) {
        $Records | Select-Object name, description, source, tag, category, relativePath, path, bodyExcerpt | ConvertTo-Json -Depth 8
        return
    }

    if (-not $Records -or $Records.Count -eq 0) {
        Write-Output "No matching materials."
        return
    }

    foreach ($record in $Records) {
        Write-Output $record.name
        Write-Output ("  Description: {0}" -f $record.description)
        Write-Output ("  Source: {0}" -f $record.source)
        Write-Output ("  Tags: {0}" -f (@($record.tag) -join ', '))
        Write-Output ("  Category: {0}" -f $record.category)
        Write-Output ("  Path: {0}" -f $record.path)
        if ($record.bodyExcerpt) { Write-Output ("  Body: {0}" -f $record.bodyExcerpt) }
        Write-Output ""
    }
}

function Invoke-SearchCommand {
    param([string[]]$SearchArgs)

    $asJson = $false
    $limit = 20
    $requiredTags = New-Object System.Collections.Generic.List[string]
    $sources = New-Object System.Collections.Generic.List[string]
    $sourceContains = New-Object System.Collections.Generic.List[string]
    $category = ""
    $textQueries = New-Object System.Collections.Generic.List[string]

    $argList = if ($null -eq $SearchArgs) { @() } else { @($SearchArgs) }
    $argList = @(Repair-DashedArgs -ArgList $argList -KnownOptions @('--json', '--tag', '--category', '--limit', '--text', '--source', '--source-contains', '--work'))
    $optionNames = @('--json', '--tag', '--category', '--limit', '--text', '--source', '--source-contains', '--work')
    for ($index = 0; $index -lt (Get-ItemCount $argList); $index++) {
        $arg = $argList[$index]
        switch ($arg) {
            '--json' { $asJson = $true; continue }
            '--tag' {
                if ($index + 1 -ge (Get-ItemCount $argList)) { Write-MaterialLibraryError "--tag requires a value." }
                $index += 1; $requiredTags.Add($argList[$index]); continue
            }
            '--category' {
                if ($index + 1 -ge (Get-ItemCount $argList)) { Write-MaterialLibraryError "--category requires a value." }
                $index += 1; $category = $argList[$index]; continue
            }
            '--source' {
                if ($index + 1 -ge (Get-ItemCount $argList)) { Write-MaterialLibraryError "--source requires a value." }
                $index += 1; $sources.Add($argList[$index]); continue
            }
            '--work' {
                if ($index + 1 -ge (Get-ItemCount $argList)) { Write-MaterialLibraryError "--work requires a value." }
                $index += 1; $sourceContains.Add($argList[$index]); continue
            }
            '--source-contains' {
                if ($index + 1 -ge (Get-ItemCount $argList)) { Write-MaterialLibraryError "--source-contains requires a value." }
                $index += 1; $sourceContains.Add($argList[$index]); continue
            }
            '--text' {
                if ($index + 1 -ge (Get-ItemCount $argList)) { Write-MaterialLibraryError "--text requires a value." }
                $index += 1; $textQueries.Add($argList[$index]); continue
            }
            '--limit' {
                if ($index + 1 -ge (Get-ItemCount $argList)) { Write-MaterialLibraryError "--limit requires a value." }
                $index += 1
                if (-not [int]::TryParse($argList[$index], [ref]$limit)) { Write-MaterialLibraryError "--limit requires an integer." }
                continue
            }
            default {
                $keywordParts = New-Object System.Collections.Generic.List[string]
                $keywordParts.Add($arg)
                while (($index + 1) -lt (Get-ItemCount $argList) -and $optionNames -notcontains $argList[$index + 1]) {
                    $index += 1
                    $keywordParts.Add($argList[$index])
                }
                $textQueries.Add(($keywordParts -join ' '))
            }
        }
    }

    $records = @(Get-MaterialRecords)
    $scored = @($records | ForEach-Object {
        $score = Get-SearchScore -Record $_ -TextQueries @($textQueries) -RequiredTags @($requiredTags) -Category $category -Sources @($sources) -SourceContains @($sourceContains)
        if ($score -ge 0) { [pscustomobject]@{ record = $_; score = $score } }
    } | Where-Object { $null -ne $_ } | Sort-Object -Property @(
        @{ Expression = { $_.score }; Descending = $true },
        @{ Expression = { $_.record.category }; Descending = $false },
        @{ Expression = { $_.record.name }; Descending = $false }
    ))
    if ($limit -gt 0) { $scored = @($scored | Select-Object -First $limit) }
    Show-MaterialRecords -Records @($scored | ForEach-Object { $_.record }) -AsJson $asJson
}

function New-ValueCountRows {
    param([object[]]$Values)
    return @($Values | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) } | Group-Object | Sort-Object Count, Name -Descending | ForEach-Object {
        [pscustomobject]@{ value = $_.Name; count = $_.Count }
    })
}

function Get-ItemCount {
    param($Value)
    if ($null -eq $Value) { return 0 }
    return @($Value).Count
}

function Repair-DashedArgs {
    param(
        [object[]]$ArgList,
        [string[]]$KnownOptions
    )

    $items = @($ArgList)
    $repaired = New-Object System.Collections.Generic.List[string]
    for ($index = 0; $index -lt (Get-ItemCount $items); $index++) {
        $current = [string]$items[$index]
        if ($current -eq '-' -and ($index + 1) -lt (Get-ItemCount $items)) {
            $combined = '-' + [string]$items[$index + 1]
            if ($KnownOptions -contains $combined) {
                $repaired.Add($combined)
                $index += 1
                continue
            }
        }
        $repaired.Add($current)
    }
    return @($repaired)
}

function Invoke-InfoCommand {
    param([string[]]$InfoArgs)

    $asJson = $false
    $section = "all"
    $categoryFilter = ""
    $infoArgList = if ($null -eq $InfoArgs) { @() } else { @($InfoArgs) }
    $infoArgList = @(Repair-DashedArgs -ArgList $infoArgList -KnownOptions @('--json', '--section', '--category'))
    for ($index = 0; $index -lt (Get-ItemCount $infoArgList); $index++) {
        switch ($infoArgList[$index]) {
            '--json' { $asJson = $true; continue }
            '--section' {
                if ($index + 1 -ge (Get-ItemCount $infoArgList)) { Write-MaterialLibraryError "--section requires a value." }
                $index += 1; $section = $infoArgList[$index]; continue
            }
            '--category' {
                if ($index + 1 -ge (Get-ItemCount $infoArgList)) { Write-MaterialLibraryError "--category requires a value." }
                $index += 1; $categoryFilter = $infoArgList[$index]; continue
            }
            default { Write-MaterialLibraryError "Unknown info option '$($infoArgList[$index])'." }
        }
    }

    $records = @(Get-MaterialRecords)
    if ($categoryFilter) { $records = @($records | Where-Object { (Normalize-Text -Value $_.category) -eq (Normalize-Text -Value $categoryFilter) }) }

    $categories = @(New-ValueCountRows -Values @($records | ForEach-Object { $_.category }))
    $sources = @(New-ValueCountRows -Values @($records | ForEach-Object { $_.source }))
    $tags = @(New-ValueCountRows -Values @($records | ForEach-Object { $_.tag }))
    $tagsByCategory = @($records | Group-Object category | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ category = $_.Name; tags = @(New-ValueCountRows -Values @($_.Group | ForEach-Object { $_.tag })) }
    })
    $sourcesByCategory = @($records | Group-Object category | Sort-Object Name | ForEach-Object {
        [pscustomobject]@{ category = $_.Name; sources = @(New-ValueCountRows -Values @($_.Group | ForEach-Object { $_.source })) }
    })

    $info = [pscustomobject]@{
        materialRoot = $script:MaterialRoot
        materialCount = $records.Count
        categories = $categories
        sources = $sources
        tags = $tags
        tagsByCategory = $tagsByCategory
        sourcesByCategory = $sourcesByCategory
    }

    if ($asJson) {
        switch ($section) {
            'categories' { $categories | ConvertTo-Json -Depth 8; return }
            'sources' { $sources | ConvertTo-Json -Depth 8; return }
            'tags' { $tags | ConvertTo-Json -Depth 8; return }
            'tags-by-category' { $tagsByCategory | ConvertTo-Json -Depth 10; return }
            'sources-by-category' { $sourcesByCategory | ConvertTo-Json -Depth 10; return }
            default { $info | ConvertTo-Json -Depth 10; return }
        }
    }

    Write-Output "Material Library Info"
    Write-Output "---------------------"
    Write-Output ("Root: {0}" -f $script:MaterialRoot)
    Write-Output ("Materials: {0}" -f $records.Count)
    Write-Output ""

    if ($section -in @('all', 'categories')) {
        Write-Output "Categories"
        Write-Output "----------"
        if ((Get-ItemCount $categories) -eq 0) { Write-Output "(none)" } else { $categories | ForEach-Object { Write-Output ("{0} ({1})" -f $_.value, $_.count) } }
        Write-Output ""
    }
    if ($section -in @('all', 'sources')) {
        Write-Output "Sources"
        Write-Output "-------"
        if ((Get-ItemCount $sources) -eq 0) { Write-Output "(none)" } else { $sources | ForEach-Object { Write-Output ("{0} ({1})" -f $_.value, $_.count) } }
        Write-Output ""
    }
    if ($section -in @('all', 'tags')) {
        Write-Output "Tags"
        Write-Output "----"
        if ((Get-ItemCount $tags) -eq 0) { Write-Output "(none)" } else { $tags | ForEach-Object { Write-Output ("{0} ({1})" -f $_.value, $_.count) } }
        Write-Output ""
    }
    if ($section -in @('all', 'tags-by-category')) {
        Write-Output "Tags By Category"
        Write-Output "----------------"
        if ((Get-ItemCount $tagsByCategory) -eq 0) { Write-Output "(none)" }
        foreach ($group in $tagsByCategory) {
            Write-Output $group.category
            if ((Get-ItemCount $group.tags) -eq 0) { Write-Output "  (none)" } else { $group.tags | ForEach-Object { Write-Output ("  {0} ({1})" -f $_.value, $_.count) } }
        }
    }
}

function Show-Usage {
@"
novel-writing material-library command runner

Usage:
  mycli novel-writing material-library search [text...] [--text <text>] [--tag <tag>] [--source <source>] [--work <work>] [--category <category>] [--limit <n>] [--json]
  mycli novel-writing material-library info [--section categories|sources|tags|tags-by-category|sources-by-category] [--category <category>] [--json]

Search semantics:
  --tag              Exact tag match after normalization. Repeatable. AND condition.
  --source           Exact source match after normalization. Repeatable. AND condition.
  --work             Rough source/work search; alias of --source-contains.
  --source-contains  Source contains text after normalization.
  --text or bare text Rough text search in name, description, source, path, category, and body.
  --category         Exact category folder match after normalization.

Examples:
  mycli novel-writing material-library search 打脸
  mycli novel-writing material-library search --tag 人物设定 --tag 反派
  mycli novel-writing material-library search --source 原创 --tag 场景
  mycli novel-writing material-library search --work 红楼梦 --text 语言风格
  mycli novel-writing material-library info --section tags-by-category
"@ | Write-Output
}

$commandArgs = @($args)
$action = if ($commandArgs.Count -gt 0) { $commandArgs[0] } else { 'help' }
$remainingArgs = if ($commandArgs.Count -gt 1) { @($commandArgs[1..($commandArgs.Count - 1)]) } else { @() }

switch ($action) {
    { $_ -in @('search', 'find') } { Invoke-SearchCommand -SearchArgs $remainingArgs }
    { $_ -in @('info', 'index', 'inspect') } { Invoke-InfoCommand -InfoArgs $remainingArgs }
    { $_ -in @('--help', '-h', 'help') } { Show-Usage }
    default { Write-MaterialLibraryError "Unknown material-library action '$action'. Available actions: search, info, help." }
}
