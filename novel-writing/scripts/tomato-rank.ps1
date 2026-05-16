param(
    [Parameter(ValueFromRemainingArguments = $true)]
    [string[]]$Rest = @()
)

$ErrorActionPreference = "Stop"

function Get-OptionValue {
    param(
        [Parameter(Position = 0)] [string[]]$Args,
        [Parameter(Position = 1)] [string]$Name,
        [Parameter(Position = 2)] [string]$Default = $null
    )
    for ($i = 0; $i -lt $Args.Count; $i++) {
        if ($Args[$i] -eq $Name) {
            if ($i + 1 -ge $Args.Count) { throw "Missing value for option $Name" }
            return $Args[$i + 1]
        }
    }
    return $Default
}

function Test-OptionPresent {
    param([string[]]$Args, [string]$Name)
    return @($Args | Where-Object { $_ -eq $Name }).Count -gt 0
}

function Get-NumberOption {
    param(
        [Parameter(Position = 0)] [string[]]$Args,
        [Parameter(Position = 1)] [string]$Name,
        [Parameter(Position = 2)] [Nullable[double]]$Default = $null
    )
    $raw = Get-OptionValue -Args $Args -Name $Name -Default $null
    if ($null -eq $raw -or [string]$raw -eq "") { return $Default }
    $n = 0.0
    if (-not [double]::TryParse([string]$raw, [ref]$n)) { throw "Invalid numeric value for ${Name}: $raw" }
    return $n
}

function ConvertTo-Number {
    param($Value, [double]$Default = 0)
    if ($null -eq $Value) { return $Default }
    $s = ([string]$Value).Trim()
    if (-not $s) { return $Default }
    $n = 0.0
    if ([double]::TryParse($s, [ref]$n)) { return $n }
    return $Default
}

function Convert-ChineseHotTextToNumber {
    param($Value)
    if ($null -eq $Value) { return 0 }
    $s = ([string]$Value).Trim()
    if (-not $s) { return 0 }
    $m = [regex]::Match($s, '(?<num>\d+(?:\.\d+)?)\s*(?<unit>万|亿)?')
    if (-not $m.Success) { return 0 }
    $num = [double]$m.Groups['num'].Value
    $unit = $m.Groups['unit'].Value
    if ($unit -eq '亿') { return [int64]($num * 100000000) }
    if ($unit -eq '万') { return [int64]($num * 10000) }
    return [int64]$num
}

function Format-FilterValue {
    param($Value)
    if ($null -eq $Value) { return "" }
    if ($Value -is [double] -or $Value -is [int] -or $Value -is [long]) { return [string]$Value }
    return [string]$Value
}

function Test-Range {
    param($Value, $Min, $Max)
    if ($null -ne $Min -and $Value -lt $Min) { return $false }
    if ($null -ne $Max -and $Value -gt $Max) { return $false }
    return $true
}

function Test-TextContainsAny {
    param([string]$Text, [string[]]$Needles)
    if (-not $Needles -or $Needles.Count -eq 0) { return $true }
    foreach ($n in $Needles) {
        if ($Text -like "*$n*") { return $true }
    }
    return $false
}

function Test-TextExcludesAll {
    param([string]$Text, [string[]]$Needles)
    if (-not $Needles -or $Needles.Count -eq 0) { return $true }
    foreach ($n in $Needles) {
        if ($Text -like "*$n*") { return $false }
    }
    return $true
}

function Get-LogScore {
    param([double]$Value, [double]$Weight)
    if ($Value -le 0) { return 0 }
    return [Math]::Log10($Value + 1) * $Weight
}

function Get-StringField {
    param($Object, [string]$Name, [string]$Default = "")
    if ($null -eq $Object) { return $Default }
    $prop = $Object.PSObject.Properties[$Name]
    if ($null -eq $prop -or $null -eq $prop.Value) { return $Default }
    return [string]$prop.Value
}

function ConvertTo-RankedItem {
    param($Item, [string]$Keyword)

    $raw = $Item.raw
    $bookId = Get-StringField -Object $Item -Name "book_id"
    if (-not $bookId) { $bookId = Get-StringField -Object $raw -Name "book_id" }

    $title = Get-StringField -Object $Item -Name "title"
    if (-not $title) { $title = Get-StringField -Object $raw -Name "book_name" }
    $author = Get-StringField -Object $Item -Name "author"
    if (-not $author) { $author = Get-StringField -Object $raw -Name "author" }

    $readAll = ConvertTo-Number (Get-StringField -Object $raw -Name "read_count_all")
    $readNow = ConvertTo-Number (Get-StringField -Object $raw -Name "read_count")
    $readTextNumber = Convert-ChineseHotTextToNumber (Get-StringField -Object $raw -Name "read_cnt_text")
    $shelf = ConvertTo-Number (Get-StringField -Object $raw -Name "shelf_cnt_history")
    $score = ConvertTo-Number (Get-StringField -Object $raw -Name "score")
    $wordNumber = ConvertTo-Number (Get-StringField -Object $raw -Name "word_number")
    $chapters = ConvertTo-Number (Get-StringField -Object $raw -Name "serial_count")
    if ($chapters -eq 0) { $chapters = ConvertTo-Number (Get-StringField -Object $raw -Name "chapter_number") }
    $status = Get-StringField -Object $raw -Name "creation_status"
    $updateStatus = Get-StringField -Object $raw -Name "update_status"

    $hot = 0.0
    $hot += Get-LogScore -Value $readAll -Weight 32
    $hot += Get-LogScore -Value $shelf -Weight 23
    $hot += Get-LogScore -Value ([Math]::Max($readNow, $readTextNumber)) -Weight 18
    $hot += $score * 7
    $hot += Get-LogScore -Value $wordNumber -Weight 4
    if ($updateStatus -eq "1") { $hot += 8 }
    if ($status -eq "1") { $hot += 3 } else { $hot += 6 }
    if ($chapters -gt 0 -and $chapters -lt 80) { $hot -= 12 }
    if ($score -gt 0 -and $score -lt 7.0) { $hot -= 10 }

    [pscustomobject]@{
        book_id = $bookId
        title = $title
        author = $author
        keyword = $Keyword
        hot_score = [Math]::Round($hot, 2)
        rating = $score
        read_count_all = [int64]$readAll
        current_read_count = [int64]([Math]::Max($readNow, $readTextNumber))
        shelf_count = [int64]$shelf
        word_number = [int64]$wordNumber
        chapters = [int]$chapters
        category = Get-StringField -Object $raw -Name "category"
        tags = Get-StringField -Object $raw -Name "tags"
        status = if ($status -eq "1") { "serializing" } elseif ($status -eq "0") { "completed" } else { $status }
        latest_chapter = Get-StringField -Object $raw -Name "last_chapter_title"
        abstract = Get-StringField -Object $raw -Name "abstract"
    }
}

$remaining = @($Rest)
if ($remaining.Count -gt 0 -and $remaining[0] -eq "tomato-rank") {
    $remaining = if ($remaining.Count -gt 1) { @($remaining[1..($remaining.Count - 1)]) } else { @() }
}

$defaultKeywords = ""
if ($remaining.Count -gt 0 -and $remaining[0] -notlike "--*") {
    $defaultKeywords = $remaining[0]
    $remaining = if ($remaining.Count -gt 1) { @($remaining[1..($remaining.Count - 1)]) } else { @() }
}

$keywordsValue = Get-OptionValue -Args $remaining -Name "--keywords" -Default $defaultKeywords
$limitValue = [int](Get-OptionValue -Args $remaining -Name "--limit" -Default 30)
$addrValue = Get-OptionValue -Args $remaining -Name "--addr" -Default "127.0.0.1:18423"
$outValue = Get-OptionValue -Args $remaining -Name "--out" -Default "D:\agent_workspace\capability-library\mycli\novel-writing\collector\books\_rankings"
$minRating = Get-NumberOption -Args $remaining -Name "--min-rating"
$maxRating = Get-NumberOption -Args $remaining -Name "--max-rating"
$minShelf = Get-NumberOption -Args $remaining -Name "--min-shelf"
$maxShelf = Get-NumberOption -Args $remaining -Name "--max-shelf"
$minCurrentRead = Get-NumberOption -Args $remaining -Name "--min-current-read"
$maxCurrentRead = Get-NumberOption -Args $remaining -Name "--max-current-read"
$minTotalRead = Get-NumberOption -Args $remaining -Name "--min-total-read"
$maxTotalRead = Get-NumberOption -Args $remaining -Name "--max-total-read"
$minWords = Get-NumberOption -Args $remaining -Name "--min-words"
$maxWords = Get-NumberOption -Args $remaining -Name "--max-words"
$minChapters = Get-NumberOption -Args $remaining -Name "--min-chapters"
$maxChapters = Get-NumberOption -Args $remaining -Name "--max-chapters"
$minHotScore = Get-NumberOption -Args $remaining -Name "--min-hot-score"
$maxHotScore = Get-NumberOption -Args $remaining -Name "--max-hot-score"
$statusFilterRaw = Get-OptionValue -Args $remaining -Name "--status" -Default ""
$includeRaw = Get-OptionValue -Args $remaining -Name "--include" -Default ""
$excludeRaw = Get-OptionValue -Args $remaining -Name "--exclude" -Default ""
$allMatches = Test-OptionPresent -Args $remaining -Name "--all"

if (-not $keywordsValue) {
    $keywordsValue = "玄幻,修仙,都市,系统,神豪,重生,末世,历史,悬疑,多女主"
}
if ($limitValue -le 0) { $limitValue = 30 }
if (-not $addrValue) { $addrValue = "127.0.0.1:18423" }
if (-not $outValue) { $outValue = "D:\agent_workspace\capability-library\mycli\novel-writing\collector\books\_rankings" }

$startScript = Join-Path $PSScriptRoot "tomato-start.ps1"
$rawRoot = "D:\agent_workspace\capability-library\mycli\novel-writing\collector\books\.tomato-raw"
& $startScript -Addr $addrValue -SavePath $rawRoot | Out-Null

New-Item -ItemType Directory -Force -Path $outValue | Out-Null
$baseUrl = "http://$addrValue"
$keywords = @($keywordsValue -split '[,，;；]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
if ($keywords.Count -eq 0) { throw "No keywords provided." }

$byId = @{}
foreach ($kw in $keywords) {
    $encoded = [System.Uri]::EscapeDataString($kw)
    $resp = Invoke-RestMethod -Uri "$baseUrl/api/search?q=$encoded" -TimeoutSec 30
    foreach ($item in @($resp.items)) {
        $ranked = ConvertTo-RankedItem -Item $item -Keyword $kw
        if (-not $ranked.book_id) { continue }
        if (-not $byId.ContainsKey($ranked.book_id) -or $ranked.hot_score -gt $byId[$ranked.book_id].hot_score) {
            $byId[$ranked.book_id] = $ranked
        }
    }
    Start-Sleep -Milliseconds 800
}

$statusFilters = @($statusFilterRaw -split '[,，;；]' | ForEach-Object { $_.Trim().ToLowerInvariant() } | Where-Object { $_ })
$includeTerms = @($includeRaw -split '[,，;；]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })
$excludeTerms = @($excludeRaw -split '[,，;；]' | ForEach-Object { $_.Trim() } | Where-Object { $_ })

$filteredItems = @($byId.Values | Where-Object {
    $it = $_
    $text = @($it.title, $it.author, $it.category, $it.tags, $it.abstract) -join " `n"
    (Test-Range -Value $it.rating -Min $minRating -Max $maxRating) -and
    (Test-Range -Value $it.shelf_count -Min $minShelf -Max $maxShelf) -and
    (Test-Range -Value $it.current_read_count -Min $minCurrentRead -Max $maxCurrentRead) -and
    (Test-Range -Value $it.read_count_all -Min $minTotalRead -Max $maxTotalRead) -and
    (Test-Range -Value $it.word_number -Min $minWords -Max $maxWords) -and
    (Test-Range -Value $it.chapters -Min $minChapters -Max $maxChapters) -and
    (Test-Range -Value $it.hot_score -Min $minHotScore -Max $maxHotScore) -and
    (($statusFilters.Count -eq 0) -or ($statusFilters -contains ([string]$it.status).ToLowerInvariant())) -and
    (Test-TextContainsAny -Text $text -Needles $includeTerms) -and
    (Test-TextExcludesAll -Text $text -Needles $excludeTerms)
})

$sortedItems = @($filteredItems | Sort-Object -Property hot_score, read_count_all, shelf_count -Descending)
$rankedItems = if ($allMatches) { $sortedItems } else { @($sortedItems | Select-Object -First $limitValue) }
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$jsonPath = Join-Path $outValue "tomato-hot-$stamp.json"
$mdPath = Join-Path $outValue "tomato-hot-$stamp.md"

$result = [pscustomobject]@{
    generated_at = (Get-Date).ToString("o")
    keywords = $keywords
    limit = $limitValue
    returned_all_matches = $allMatches
    total_candidates = $byId.Count
    filtered_count = $filteredItems.Count
    filters = [pscustomobject]@{
        min_rating = $minRating; max_rating = $maxRating
        min_shelf = $minShelf; max_shelf = $maxShelf
        min_current_read = $minCurrentRead; max_current_read = $maxCurrentRead
        min_total_read = $minTotalRead; max_total_read = $maxTotalRead
        min_words = $minWords; max_words = $maxWords
        min_chapters = $minChapters; max_chapters = $maxChapters
        min_hot_score = $minHotScore; max_hot_score = $maxHotScore
        status = $statusFilters
        include = $includeTerms
        exclude = $excludeTerms
    }
    scoring = "hot_score = total reads + shelf history + current readers + rating + word count + status/update bonuses; for rough screening only"
    items = @($rankedItems)
}
$result | ConvertTo-Json -Depth 10 | Set-Content -LiteralPath $jsonPath -Encoding UTF8

$lines = New-Object System.Collections.Generic.List[string]
$lines.Add("# 番茄小说热度筛选报告")
$lines.Add("")
$lines.Add("- 生成时间：$($result.generated_at)")
$lines.Add("- 关键词：$($keywords -join ', ')")
$lines.Add("- 原始候选数：$($byId.Count)")
$lines.Add("- 筛选命中数：$($filteredItems.Count)")
$lines.Add("- 返回结果数：$($rankedItems.Count)")
$lines.Add("- 说明：热度分是粗筛指标，不等于平台官方榜单。")
$lines.Add("- 筛选：评分 $minRating~$maxRating；书架 $minShelf~$maxShelf；在读 $minCurrentRead~$maxCurrentRead；总阅读 $minTotalRead~$maxTotalRead；字数 $minWords~$maxWords；章节 $minChapters~$maxChapters；热度 $minHotScore~$maxHotScore；状态 $($statusFilters -join ',')；包含 $($includeTerms -join ',')；排除 $($excludeTerms -join ',')")
$lines.Add("")
$lines.Add("| 排名 | 热度分 | 书名 | 作者 | book_id | 评分 | 总阅读 | 在读/当前 | 书架 | 字数 | 章节 | 分类/标签 |")
$lines.Add("|---:|---:|---|---|---|---:|---:|---:|---:|---:|---:|---|")
$rank = 1
foreach ($it in $rankedItems) {
    $safeTitle = ($it.title -replace '\|', '\|')
    $safeAuthor = ($it.author -replace '\|', '\|')
    $tag = ((@($it.category, $it.tags) | Where-Object { $_ }) -join ' / ') -replace '\|', '\|'
    $lines.Add("| $rank | $($it.hot_score) | $safeTitle | $safeAuthor | $($it.book_id) | $($it.rating) | $($it.read_count_all) | $($it.current_read_count) | $($it.shelf_count) | $($it.word_number) | $($it.chapters) | $tag |")
    $rank++
}
$lines.Add("")
$lines.Add("## 下载示例")
$lines.Add("")
$lines.Add('```powershell')
$lines.Add("mycli novel-writing collector tomato-download <book_id>")
$lines.Add('```')
$lines | Set-Content -LiteralPath $mdPath -Encoding UTF8

[pscustomobject]@{
    status = "ok"
    count = $rankedItems.Count
    totalCandidates = $byId.Count
    filteredCount = $filteredItems.Count
    markdown = $mdPath
    json = $jsonPath
    items = @($rankedItems)
} | ConvertTo-Json -Depth 8
