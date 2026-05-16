param(
    [Parameter(Position = 0)]
    [string]$Action = "help",

    [string]$InputFile = "",
    [string]$Out = "",
    [string]$Title = "",
    [string]$Author = "",
    [string]$Platform = "fanqie"
)

$RemainingArgs = @($args)

$ErrorActionPreference = "Stop"

function Show-Usage {
    @"
novel-writing collector

Commands:
  inspect --input <file>
      Inspect a local text/markdown novel export and preview detected chapters.

  import-text --input <file> --out <dir> [--title <title>] [--author <author>] [--platform fanqie]
      Import a local text/markdown novel export into a structured novel project.

Examples:
  mycli novel-writing collector inspect --input D:\agent_workspace\tmp\novel-import\fanqie-first-book\raw\book.txt
  mycli novel-writing collector import-text --input D:\agent_workspace\tmp\novel-import\fanqie-first-book\raw\book.txt --out D:\agent_workspace\tmp\novel-import\fanqie-first-book --title "示例小说"
"@
}

function Get-OptionValue {
    param(
        [string[]]$Args,
        [string]$Name,
        [string]$Default = $null
    )

    for ($i = 0; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq $Name) {
            if ($i + 1 -ge $Args.Count) {
                throw "Missing value for option $Name"
            }
            return $Args[$i + 1]
        }
    }

    return $Default
}

function Read-NovelText {
    param([string]$Path)

    if (-not $Path) {
        throw "Missing required option --input <file>."
    }
    if (-not (Test-Path -LiteralPath $Path)) {
        throw "Input file not found: $Path"
    }

    return Get-Content -LiteralPath $Path -Raw
}

function Get-SafeFileName {
    param([string]$Name)

    $invalid = [System.IO.Path]::GetInvalidFileNameChars()
    $safe = $Name
    foreach ($char in $invalid) {
        $safe = $safe.Replace($char, '_')
    }
    return $safe.Trim()
}

function Split-NovelChapters {
    param([string]$Text)

    $normalized = $Text -replace "`r`n", "`n" -replace "`r", "`n"
    $lines = $normalized -split "`n"
    $chapterTitlePattern = '^\s*(第[零〇一二两三四五六七八九十百千万\d]+[章节卷回部集][^\n]{0,80}|Chapter\s+\d+[^\n]{0,80}|CHAPTER\s+\d+[^\n]{0,80}|\d{1,5}[\.、]\s*[^\n]{1,80})\s*$'

    $chapters = New-Object System.Collections.Generic.List[object]
    $currentTitle = $null
    $currentLines = New-Object System.Collections.Generic.List[string]
    $prefaceLines = New-Object System.Collections.Generic.List[string]

    foreach ($line in $lines) {
        if ($line -match $chapterTitlePattern) {
            if ($null -ne $currentTitle) {
                $chapters.Add([pscustomobject]@{
                    title = $currentTitle.Trim()
                    content = (($currentLines.ToArray()) -join "`n").Trim()
                })
                $currentLines.Clear()
            } elseif ($prefaceLines.Count -gt 0 -and (($prefaceLines.ToArray()) -join "`n").Trim().Length -gt 0) {
                $chapters.Add([pscustomobject]@{
                    title = "卷首说明"
                    content = (($prefaceLines.ToArray()) -join "`n").Trim()
                })
                $prefaceLines.Clear()
            }

            $currentTitle = $line.Trim()
            continue
        }

        if ($null -eq $currentTitle) {
            $prefaceLines.Add($line)
        } else {
            $currentLines.Add($line)
        }
    }

    if ($null -ne $currentTitle) {
        $chapters.Add([pscustomobject]@{
            title = $currentTitle.Trim()
            content = (($currentLines.ToArray()) -join "`n").Trim()
        })
    } elseif ($prefaceLines.Count -gt 0) {
        $chapters.Add([pscustomobject]@{
            title = "全文"
            content = (($prefaceLines.ToArray()) -join "`n").Trim()
        })
    }

    return @($chapters.ToArray())
}

function Inspect-NovelText {
    param([string[]]$Args)

    $inputPath = Get-OptionValue -Args $Args -Name "--input"
    if (-not $inputPath) {
        $inputPath = $InputFile
    }
    $text = Read-NovelText -Path $inputPath
    $chapters = Split-NovelChapters -Text $text

    [pscustomobject]@{
        input = $inputPath
        length = $text.Length
        chapterCount = $chapters.Count
        previewTitles = @($chapters | Select-Object -First 10 | ForEach-Object { $_.title })
    } | ConvertTo-Json -Depth 6
}

function Import-NovelText {
    param([string[]]$Args)

    $inputPath = Get-OptionValue -Args $Args -Name "--input"
    $outDir = Get-OptionValue -Args $Args -Name "--out"
    if (-not $inputPath) {
        $inputPath = $InputFile
    }
    if (-not $outDir) {
        $outDir = $Out
    }
    if (-not $outDir) {
        throw "Missing required option --out <dir>."
    }

    $titleDefault = if ($Title) { $Title } else { [System.IO.Path]::GetFileNameWithoutExtension($inputPath) }
    $authorDefault = if ($Author) { $Author } else { "" }
    $platformDefault = if ($Platform) { $Platform } else { "fanqie" }
    $title = Get-OptionValue -Args $Args -Name "--title" -Default $titleDefault
    $author = Get-OptionValue -Args $Args -Name "--author" -Default $authorDefault
    $platform = Get-OptionValue -Args $Args -Name "--platform" -Default $platformDefault

    $text = Read-NovelText -Path $inputPath
    $chapters = Split-NovelChapters -Text $text
    if ($chapters.Count -eq 0) {
        throw "No text content detected in input file: $inputPath"
    }

    $sourceRoot = Join-Path $outDir "source"
    $platformRoot = Join-Path $sourceRoot $platform
    $chaptersRoot = Join-Path $platformRoot "chapters"
    $analysisRoot = Join-Path $outDir "analysis-input"

    New-Item -ItemType Directory -Force -Path $chaptersRoot | Out-Null
    New-Item -ItemType Directory -Force -Path $analysisRoot | Out-Null

    $catalogItems = New-Object System.Collections.Generic.List[object]
    $totalChars = 0

    for ($i = 0; $i -lt $chapters.Count; $i++) {
        $chapter = $chapters[$i]
        $index = $i + 1
        $fileName = ("{0:D4}.md" -f $index)
        $chapterPath = Join-Path $chaptersRoot $fileName
        $content = "# $($chapter.title)`n`n$($chapter.content.Trim())`n"
        Set-Content -LiteralPath $chapterPath -Value $content -Encoding UTF8

        $charCount = $chapter.content.Length
        $totalChars += $charCount
        $catalogItems.Add([pscustomobject]@{
            index = $index
            title = $chapter.title
            file = "chapters/$fileName"
            charCount = $charCount
        })
    }

    $now = (Get-Date).ToString("o")
    $work = [pscustomobject]@{
        title = $title
        author = $author
        platform = $platform
        sourceType = "local-user-provided-text"
        sourceInput = $inputPath
        importedAt = $now
        chapterCount = $chapters.Count
        charCount = $totalChars
        notes = "由用户从手机端合法下载/复制/导出的本地文本导入；未绕过登录、风控或付费限制。"
    }
    $catalog = [pscustomobject]@{
        title = $title
        platform = $platform
        importedAt = $now
        chapterCount = $chapters.Count
        chapters = @($catalogItems.ToArray())
    }

    $workPath = Join-Path $platformRoot "work.json"
    $catalogPath = Join-Path $platformRoot "catalog.json"
    $deconstructionPath = Join-Path $analysisRoot "deconstruction.md"

    $work | ConvertTo-Json -Depth 8 | Set-Content -LiteralPath $workPath -Encoding UTF8
    $catalog | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $catalogPath -Encoding UTF8

    $preview = @($catalogItems | Select-Object -First 20 | ForEach-Object { "- $($_.index). $($_.title)（$($_.charCount) 字）" }) -join "`n"
    $deconstruction = @"
# $title 拆书输入

## 来源

- 平台：$platform
- 输入文件：`$inputPath`
- 导入时间：$now
- 章节数：$($chapters.Count)
- 总字数估算：$totalChars

## 目录预览

$preview

## 后续建议

1. 先抽样检查 `source/$platform/chapters/` 中的章节切分是否准确。
2. 如章节标题识别有误，调整原始文本中的章节标题格式后重新导入。
3. 确认无误后，将本文件交给 novel-writing deconstruction 模块继续拆书。
"@
    Set-Content -LiteralPath $deconstructionPath -Value $deconstruction -Encoding UTF8

    [pscustomobject]@{
        status = "ok"
        title = $title
        chapterCount = $chapters.Count
        charCount = $totalChars
        output = $outDir
        work = $workPath
        catalog = $catalogPath
        chapters = $chaptersRoot
        deconstructionInput = $deconstructionPath
    } | ConvertTo-Json -Depth 6
}

switch ($Action) {
    "help" { Show-Usage }
    "--help" { Show-Usage }
    "inspect" { Inspect-NovelText -Args $RemainingArgs }
    "import-text" { Import-NovelText -Args $RemainingArgs }
    default {
        throw "Unknown collector action '$Action'. Available actions: inspect, import-text."
    }
}
