param(
    [Parameter(Position = 0)]
    [string]$Action = "help",

    [string]$Book = "",

    [string]$Out = "",

    [string]$Name = "",

    [switch]$CopyChapters,

    [switch]$Force,

    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$RemainingArgs
)

$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding
$PackageRoot = "D:\agent_workspace\capability-library\mycli\novel-writing"
$DeconstructionRoot = Join-Path $PackageRoot "deconstruction"
$ModuleDiscussion = "D:\agent_workspace\capability-library\skill-library\novel-writing\modules\deconstruction.md"

function Write-DeconstructionHelp {
    @"
novel-writing deconstruction

Commands:
  open
  show
  init --book <book-path> [--out <work-dir>] [--name <name>] [--copy-chapters] [--force]

Examples:
  mycli novel-writing deconstruction init --book "D:\agent_workspace\capability-library\mycli\novel-writing\collector\books\天命反派，开局拿下女帝师尊"
"@
}

function Get-OptionValue {
    param([string[]]$Args, [string]$Name, [string]$Default = "")
    for ($i = 0; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq $Name) {
            if ($i + 1 -ge $Args.Count) { throw "Missing value for $Name" }
            return $Args[$i + 1]
        }
    }
    return $Default
}

function Test-Flag { param([string[]]$Args, [string]$Name) return $Args -contains $Name }

function Convert-ToSafeName {
    param([string]$Name)
    $safe = $Name.Trim()
    foreach ($char in [System.IO.Path]::GetInvalidFileNameChars()) { $safe = $safe.Replace([string]$char, "_") }
    if (-not $safe) { throw "Name cannot be empty." }
    return $safe
}

function New-DirectoryIfMissing {
    param([string]$Path)
    if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path | Out-Null }
}

function Write-Utf8File {
    param([string]$Path, [string]$Content)
    New-DirectoryIfMissing (Split-Path -Parent $Path)
    Set-Content -LiteralPath $Path -Value $Content -Encoding UTF8
}

function Get-BookMeta {
    param([string]$BookPath)
    $catalogPath = Join-Path $BookPath "catalog.json"
    $title = Split-Path -Leaf $BookPath
    $chapterCount = 0
    if (Test-Path -LiteralPath $catalogPath) {
        $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
        if ($catalog.title) { $title = [string]$catalog.title }
        if ($catalog.chapterCount) { $chapterCount = [int]$catalog.chapterCount }
    }
    [pscustomobject]@{ Title = $title; ChapterCount = $chapterCount; CatalogPath = $catalogPath; ChaptersPath = Join-Path $BookPath "章节" }
}

function Add-InitialChapterContext {
    param([hashtable]$Request, [string]$BookPath)
    $catalogPath = Join-Path $BookPath "catalog.json"
    if (-not (Test-Path -LiteralPath $catalogPath)) { return }
    $catalog = Get-Content -LiteralPath $catalogPath -Raw -Encoding UTF8 | ConvertFrom-Json
    foreach ($chapter in @($catalog.chapters | Select-Object -First 15)) {
        $idx = [int]$chapter.index
        $labelPrefix = if ($idx -le 5) { "目标" } else { "下文" }
        $Request.context_files += @{ label = ("{0}{1:D3}" -f $labelPrefix, $idx); path = (Join-Path $BookPath ([string]$chapter.file)) }
    }
}

function New-DeconstructionWorkspace {
    param([string[]]$Args)
    $bookPath = $Book
    if (-not $bookPath -and $Args.Count -gt 0) {
        $firstArg = [string]$Args[0]
        if ($firstArg -ne "init" -and -not $firstArg.StartsWith("--")) { $bookPath = $firstArg }
    }
    if (-not $bookPath) { $bookPath = Get-OptionValue $Args "--book" }
    if (-not $bookPath) { $bookPath = Get-OptionValue $Args "-b" }
    if (-not $bookPath) { throw "Usage: mycli novel-writing deconstruction init --book <book-path> [--out <work-dir>] [--name <name>] [--copy-chapters] [--force]" }
    $bookPath = (Resolve-Path -LiteralPath $bookPath).Path
    $meta = Get-BookMeta $bookPath
    if (-not (Test-Path -LiteralPath $meta.ChaptersPath -PathType Container)) { throw "Book chapters directory not found: $($meta.ChaptersPath)" }

    $name = if ($Name) { $Name } else { Get-OptionValue $Args "--name" $meta.Title }
    $out = if ($Out) { $Out } else { Get-OptionValue $Args "--out" }
    if (-not $out) { $out = Join-Path $DeconstructionRoot (Convert-ToSafeName $name) }
    $out = [System.IO.Path]::GetFullPath($out)
    $force = [bool]$Force -or (Test-Flag $Args "--force")
    $copyChapters = [bool]$CopyChapters -or (Test-Flag $Args "--copy-chapters")
    if ((Test-Path -LiteralPath $out) -and -not $force) { throw "Deconstruction workspace already exists: $out. Use --force." }

    $dirs = @(
        "00-项目说明", "00-项目说明\运行记录", "01-原文\章节", "01-原文\目录",
        "02-请求\批次素材拆解", "02-请求\阶段汇总", "02-请求\文风拆解", "02-请求\全书统一", "02-请求\最终审核",
        "03-输出\批次拆解", "03-输出\阶段汇总", "03-输出\文风拆解", "03-输出\全书统一", "03-输出\最终审核",
        "04-索引\批次索引", "04-索引\阶段索引", "04-索引\全书索引",
        "05-精选入库候选\场景", "05-精选入库候选\爽点", "05-精选入库候选\伏笔", "05-精选入库候选\人物设定", "05-精选入库候选\情感线推进",
        "05-精选入库候选\力量体系", "05-精选入库候选\世界设定", "05-精选入库候选\完整故事概要", "05-精选入库候选\文学风格收集", "05-精选入库候选\灵活记录",
        "06-agent-runs", "07-临时工作区"
    )
    foreach ($dir in $dirs) { New-DirectoryIfMissing (Join-Path $out $dir) }
    if (Test-Path -LiteralPath $meta.CatalogPath) { Copy-Item -LiteralPath $meta.CatalogPath -Destination (Join-Path $out "01-原文\目录\catalog.json") -Force }

    $sourceInfo = @{ title = $meta.Title; chapterCount = $meta.ChapterCount; sourceBookPath = $bookPath; sourceChaptersPath = $meta.ChaptersPath; localChaptersPath = (Join-Path $out "01-原文\章节"); chapterMode = if ($copyChapters) { "copy" } else { "reference" }; createdAt = (Get-Date).ToString("o") }
    Write-Utf8File (Join-Path $out "00-项目说明\source.json") ($sourceInfo | ConvertTo-Json -Depth 6)

    if ($copyChapters) {
        Copy-Item -LiteralPath (Join-Path $meta.ChaptersPath "*") -Destination (Join-Path $out "01-原文\章节") -Recurse -Force
    } else {
        $pointer = @"
# 原文章节位置

本项目默认不复制原文章节，避免占用空间和产生多份原文。

原文章节目录：

````text
$($meta.ChaptersPath)
````

调度 agent 生成 request 时，应把上面的原文章节文件作为 `context_files` 传入。

如需要复制原文章节到本项目，重新执行：

````powershell
mycli novel-writing deconstruction init --book "$bookPath" --out "$out" --copy-chapters --force
````
"@
        Write-Utf8File (Join-Path $out "01-原文\章节\README.md") $pointer
    }

    $readme = @"
# $($meta.Title) 拆书工作区

## 书籍信息

- 书名：$($meta.Title)
- 章节数：$($meta.ChapterCount)
- 原书目录：`$bookPath`
- 原文章节：`$($meta.ChaptersPath)`
- 章节模式：$(if ($copyChapters) { "已复制到本工作区 01-原文\\章节" } else { "引用原 collector 章节目录" })

## 目录结构

````text
00-项目说明/          项目说明、source.json、运行记录
01-原文/              章节目录与 catalog 副本或指针
02-请求/              各类 request.json
03-输出/              batch、阶段汇总、文风拆解、全书统一、最终审核
04-索引/              批次/阶段/全书索引
05-精选入库候选/      全书统一后筛出的 material-library 候选
06-agent-runs/        llm-call 原始运行记录
07-临时工作区/        临时文件
````

## 推荐流程

1. 5 章一批跑 `03A-章节批量粗拆agent.md`。
2. 每 50 章跑阶段汇总。
3. 每 50 章或每卷跑文风拆解。
4. 全书完成后跑全书统一。
5. 只审核最终汇总与入库候选，不对每个小批次单独审核。

## 主要调度手册

````text
D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\00-使用者如何拆书.md
````
"@
    Write-Utf8File (Join-Path $out "README.md") $readme

    $plan = @"
# 拆书计划

## 默认批次规则

- 高质量素材拆解：5 章一批。
- 上下文：目标前 10 章 + 目标 5 章 + 目标后 10 章。
- 阶段汇总：每 50 章或每卷一次。
- 文风拆解：每 50 章或每卷一次。
- 审核：只审核最终汇总层和正式入库候选。

## 第一轮实验建议

````text
目标章节：001-005
上下文：001-015
输出目录：03-输出\批次拆解\batch-001-005
request：02-请求\批次素材拆解\batch-001-005.json
````

## 后续批次

````text
006-010，上下文 001-020
011-015，上下文 001-025
016-020，上下文 006-030
...
````
"@
    Write-Utf8File (Join-Path $out "00-项目说明\拆书计划.md") $plan

    $batchRequest = @{
        task_type = "001-005章素材库分类拆书"; model = "MoreCode/gpt-5.5"; max_tokens = 70000; temperature = 0.2
        prompt = @{ path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\agent\03A-章节批量粗拆agent.md" }
        user_prompt = "请对第001-005章进行素材库分类版高质量拆书。目标范围：001-005。上下文范围：001-015。只输出目标范围 001-005 的正式拆解和素材；006-015 只作为上下文参考。必须按 material-library 分类输出多文件。每条高价值素材必须包含 YAML、source、source_range、tag、status、merge_policy、原文证据、写法解析、可复用变体、禁止照搬点。最后必须输出质量自检。"
        project = $out; base_dir = $out; target = "03-输出\批次拆解\batch-001-005\_raw.md"; output_dir = (Join-Path $out "06-agent-runs"); split_output_files = $true; split_output_base = (Join-Path $out "03-输出\批次拆解\batch-001-005")
        context_files = @(
            @{ label = "调度规则"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\00-使用者如何拆书.md" },
            @{ label = "素材库总规则"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\01-素材库总规则.md" },
            @{ label = "场景素材模板"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\02-场景素材模板.md" },
            @{ label = "爽点素材模板"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\03-爽点素材模板.md" },
            @{ label = "伏笔素材模板"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\04-伏笔素材模板.md" },
            @{ label = "人物设定素材模板"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\05-人物设定素材模板.md" },
            @{ label = "情感线推进模板"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\06-情感线推进模板.md" },
            @{ label = "力量体系素材模板"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\07-力量体系素材模板.md" },
            @{ label = "世界设定素材模板"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\08-世界设定素材模板.md" },
            @{ label = "完整故事概要模板"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\09-完整故事概要模板.md" },
            @{ label = "文学风格收集模板"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\10-文学风格收集模板.md" },
            @{ label = "灵活记录模板"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\11-灵活记录模板.md" },
            @{ label = "剧情内容拆解模板"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\12-剧情内容拆解模板.md" },
            @{ label = "质量自检模板"; path = "D:\agent_workspace\capability-library\mycli\novel-writing\prompts\拆书\模板\15-质量自检模板.md" }
        )
    }
    Add-InitialChapterContext $batchRequest $bookPath
    $firstRequestPath = Join-Path $out "02-请求\批次素材拆解\batch-001-005.json"
    Write-Utf8File $firstRequestPath ($batchRequest | ConvertTo-Json -Depth 10)

    [pscustomobject]@{ ok = $true; workspace = $out; book = $bookPath; title = $meta.Title; chapterCount = $meta.ChapterCount; firstRequest = $firstRequestPath; runCommand = "D:\agent_workspace\capability-library\mycli\mycli.ps1 novel-writing agent run `"$firstRequestPath`"" } | ConvertTo-Json -Depth 6
}

switch ($Action) {
    "help" { Write-DeconstructionHelp }
    "--help" { Write-DeconstructionHelp }
    "open" { Write-Output $ModuleDiscussion }
    "show" { Get-Content -LiteralPath $ModuleDiscussion -Raw }
    "init" { New-DeconstructionWorkspace $RemainingArgs }
    default {
        if ($RemainingArgs.Count -gt 0 -and $RemainingArgs[0] -eq "init") {
            $rest = if ($RemainingArgs.Count -gt 1) { $RemainingArgs[1..($RemainingArgs.Count - 1)] } else { @() }
            New-DeconstructionWorkspace (@($Action) + $rest)
        } else {
            throw "Unknown action '$Action'. Available actions: help, open, show, init."
        }
    }
}
