param(
    [Parameter(Position = 0)]
    [Alias("input", "input-file")]
    [string]$InputFile = "",
    [Alias("out")]
    [string]$OutRoot = "D:\agent_workspace\capability-library\mycli\novel-writing\collector\books",
    [string]$Title = "",
    [switch]$Overwrite,
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @()
)

$ErrorActionPreference = "Stop"

function Get-OptionValue {
    param([string[]]$Args, [string]$Name, [string]$Default = $null)
    for ($i = 0; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq $Name) {
            if ($i + 1 -ge $Args.Count) { throw "Missing value for option $Name" }
            return $Args[$i + 1]
        }
    }
    return $Default
}

function Get-SafeFileName {
    param([string]$Name, [string]$Fallback = "untitled")
    $safe = if ($Name) { $Name.Trim() } else { $Fallback }
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) {
        $safe = $safe.Replace($char, '_')
    }
    $safe = ($safe -replace '\s+', ' ').Trim().Trim('.')
    if (-not $safe) { $safe = $Fallback }
    if ($safe.Length -gt 80) { $safe = $safe.Substring(0, 80).Trim() }
    return $safe
}

function Split-NovelChapters {
    param([string]$Text)

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = $normalized -split "`n"
    $chapterTitlePattern = '^\s*(第\s*[零〇一二两三四五六七八九十百千万\d]+\s*[章节卷回部集][^\n]{0,100}|Chapter\s+\d+[^\n]{0,100}|CHAPTER\s+\d+[^\n]{0,100}|\d{1,5}[\.、]\s*[^\n]{1,100})\s*$'

    $chapters = New-Object System.Collections.Generic.List[object]
    $currentTitle = $null
    $currentLines = New-Object System.Collections.Generic.List[string]
    $prefaceLines = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        if ($line -match $chapterTitlePattern) {
            if ($null -ne $currentTitle) {
                $chapters.Add([pscustomobject]@{ title = $currentTitle.Trim(); content = (($currentLines.ToArray()) -join "`n").Trim() })
                $currentLines.Clear()
            }
            $currentTitle = $line.Trim()
            continue
        }

        if ($null -eq $currentTitle) { $prefaceLines.Add($line) } else { $currentLines.Add($line) }
    }

    if ($null -ne $currentTitle) {
        $chapters.Add([pscustomobject]@{ title = $currentTitle.Trim(); content = (($currentLines.ToArray()) -join "`n").Trim() })
    } elseif ($prefaceLines.Count -gt 0) {
        $chapters.Add([pscustomobject]@{ title = "全文"; content = (($prefaceLines.ToArray()) -join "`n").Trim() })
    }
    return @($chapters.ToArray())
}

$remaining = @($Rest)
$inputPath = Get-OptionValue -Args $remaining -Name "--input" -Default $InputFile
if (-not $inputPath) { $inputPath = Get-OptionValue -Args $remaining -Name "--input-file" -Default $InputFile }
$outRootValue = Get-OptionValue -Args $remaining -Name "--out" -Default $OutRoot
$titleValue = Get-OptionValue -Args $remaining -Name "--title" -Default $Title
if (-not $outRootValue) { $outRootValue = "D:\agent_workspace\capability-library\mycli\novel-writing\collector\books" }

if (-not $inputPath) { throw "Missing input file. Usage: tomato-export-md <book.txt> [--out <books-dir>] [--title <name>]" }
if (-not (Test-Path -LiteralPath $inputPath)) { throw "Input file not found: $inputPath" }

New-Item -ItemType Directory -Force -Path $outRootValue | Out-Null

$text = Get-Content -LiteralPath $inputPath -Raw -Encoding UTF8
$chapters = Split-NovelChapters -Text $text
if ($chapters.Count -eq 0) { throw "No chapters detected in: $inputPath" }

if (-not $titleValue) { $titleValue = [System.IO.Path]::GetFileNameWithoutExtension($inputPath) }
$safeTitle = Get-SafeFileName -Name $titleValue -Fallback "novel"
$bookDir = Join-Path $outRootValue $safeTitle
$chapterDir = Join-Path $bookDir "章节"

if ((Test-Path -LiteralPath $chapterDir) -and $Overwrite) {
    Remove-Item -LiteralPath $chapterDir -Recurse -Force
}
New-Item -ItemType Directory -Force -Path $chapterDir | Out-Null

$width = [Math]::Max(2, $chapters.Count.ToString().Length)
$catalog = New-Object System.Collections.Generic.List[object]
for ($i = 0; $i -lt $chapters.Count; $i++) {
    $chapter = $chapters[$i]
    $index = $i + 1
    $safeChapterTitle = Get-SafeFileName -Name $chapter.title -Fallback ("chapter-{0}" -f $index)
    $fileName = ("{0}-{1}.md" -f $index.ToString("D$width"), $safeChapterTitle)
    $path = Join-Path $chapterDir $fileName
    $body = "# $($chapter.title)`n`n$($chapter.content.Trim())`n"
    Set-Content -LiteralPath $path -Value $body -Encoding UTF8
    $catalog.Add([pscustomobject]@{ index = $index; title = $chapter.title; file = "章节/$fileName"; charCount = $chapter.content.Length })
}

$meta = [pscustomobject]@{
    title = $titleValue
    sourceFile = $inputPath
    exportedAt = (Get-Date).ToString("o")
    chapterCount = $chapters.Count
    chapters = @($catalog.ToArray())
}
$metaPath = Join-Path $bookDir "catalog.json"
$meta | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $metaPath -Encoding UTF8

[pscustomobject]@{
    status = "ok"
    title = $titleValue
    chapterCount = $chapters.Count
    output = $bookDir
    chapters = $chapterDir
    catalog = $metaPath
} | ConvertTo-Json -Depth 6
