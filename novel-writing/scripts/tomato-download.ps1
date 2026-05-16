param(
    [Parameter(Position = 0)]
    [Alias("book-id", "id")]
    [string]$BookId = "",
    [Alias("range-start")]
    [int]$RangeStart = 0,
    [Alias("range-end")]
    [int]$RangeEnd = 0,
    [string]$Addr = "127.0.0.1:18423",
    [Alias("out")]
    [string]$BooksRoot = "D:\agent_workspace\capability-library\mycli\novel-writing\collector\books",
    [Alias("no-export")]
    [switch]$NoExport,
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

$remaining = @($Rest)
if ($BookId -eq "tomato-download") {
    $BookId = ""
    if ($remaining.Count -gt 0) {
        $BookId = $remaining[0]
        $remaining = if ($remaining.Count -gt 1) { @($remaining[1..($remaining.Count - 1)]) } else { @() }
    }
}
$bookIdValue = Get-OptionValue -Args $remaining -Name "--book-id" -Default $BookId
if (-not $bookIdValue) { $bookIdValue = Get-OptionValue -Args $remaining -Name "--id" -Default $BookId }
$rangeStartValue = [int](Get-OptionValue -Args $remaining -Name "--range-start" -Default $RangeStart)
$rangeEndValue = [int](Get-OptionValue -Args $remaining -Name "--range-end" -Default $RangeEnd)
$booksRootValue = Get-OptionValue -Args $remaining -Name "--out" -Default $BooksRoot
$noExportValue = $NoExport -or ($remaining -contains "--no-export")
if (-not $Addr) { $Addr = "127.0.0.1:18423" }
if (-not $booksRootValue) { $booksRootValue = "D:\agent_workspace\capability-library\mycli\novel-writing\collector\books" }

if (-not $bookIdValue) { throw "Missing book id. Usage: mycli novel-writing collector tomato-download <book-id>" }

$startScript = Join-Path $PSScriptRoot "tomato-start.ps1"
$exportScript = Join-Path $PSScriptRoot "tomato-export-md.ps1"
$rawRoot = Join-Path $booksRootValue ".tomato-raw"
$baseUrl = "http://$Addr"

New-Item -ItemType Directory -Force -Path $booksRootValue | Out-Null
New-Item -ItemType Directory -Force -Path $rawRoot | Out-Null

if ($rangeStartValue -gt 0 -or $rangeEndValue -gt 0) {
    throw "Tomato Web UI reports full catalog totals for ranged jobs, and may reuse existing local records. For reliable chapter Markdown export, omit --range-start/--range-end and download/export the full book."
}

& $startScript -Addr $Addr -SavePath $rawRoot | Out-Null

$before = Get-Date
$bodyObj = [ordered]@{ book_id = $bookIdValue }
if ($rangeStartValue -gt 0 -or $rangeEndValue -gt 0) {
    if ($rangeStartValue -lt 1 -or $rangeEndValue -lt 1 -or $rangeStartValue -gt $rangeEndValue) {
        throw "Invalid range. Use --range-start N --range-end M, with 1 <= N <= M."
    }
    $bodyObj.range_start = $rangeStartValue
    $bodyObj.range_end = $rangeEndValue
}
$body = $bodyObj | ConvertTo-Json
$job = Invoke-RestMethod -Uri "$baseUrl/api/jobs" -Method Post -ContentType "application/json; charset=utf-8" -Body $body -TimeoutSec 15
$jobId = $job.id

$final = $null
for ($i = 0; $i -lt 1800; $i++) {
    Start-Sleep -Seconds 2
    $jobs = Invoke-RestMethod -Uri "$baseUrl/api/jobs?id=$jobId" -TimeoutSec 10
    $item = $jobs.items[0]
    if ($item.state -in @("done", "failed", "canceled")) {
        $final = $item
        break
    }
}
if (-not $final) { throw "Download job $jobId did not finish before timeout." }
if ($final.state -ne "done") { throw "Download job $jobId ended as $($final.state): $($final.message)" }

$txt = Get-ChildItem -LiteralPath $rawRoot -File -Filter "*.txt" -ErrorAction SilentlyContinue |
    Where-Object { $_.LastWriteTime -ge $before.AddSeconds(-5) } |
    Sort-Object LastWriteTime -Descending |
    Select-Object -First 1

if (-not $txt) {
    $txt = Get-ChildItem -LiteralPath $rawRoot -File -Filter "*.txt" -ErrorAction SilentlyContinue |
        Sort-Object LastWriteTime -Descending |
        Select-Object -First 1
}
if (-not $txt) { throw "Download finished but no txt file was found under $rawRoot" }

$result = [ordered]@{
    status = "ok"
    bookId = $bookIdValue
    jobId = $jobId
    title = $final.title
    chapterTotal = $final.progress.chapter_total
    savedChapters = $final.progress.saved_chapters
    rawText = $txt.FullName
}

if (-not $noExportValue) {
    $export = & $exportScript -InputFile $txt.FullName -OutRoot $booksRootValue -Overwrite | ConvertFrom-Json
    $result.markdownOutput = $export.output
    $result.markdownChapters = $export.chapters
    $result.markdownChapterCount = $export.chapterCount
}

[pscustomobject]$result | ConvertTo-Json -Depth 8
