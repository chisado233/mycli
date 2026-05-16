Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
[Console]::InputEncoding = [System.Text.UTF8Encoding]::new($false)
[Console]::OutputEncoding = [System.Text.UTF8Encoding]::new($false)
$OutputEncoding = [Console]::OutputEncoding

$script:WritingRoot = Split-Path -Parent $PSScriptRoot
$script:DefaultRoot = Join-Path $script:WritingRoot "asset-libraries"
$script:StateTemplateRoot = Join-Path $script:WritingRoot "templates\写作模板\人物势力状态表"
$script:WritingTemplateRoot = Join-Path $script:WritingRoot "templates\写作模板"
$script:Utf8NoBom = [System.Text.UTF8Encoding]::new($false)

function Fail([string]$Message) { Write-Error $Message; exit 1 }
function ReadText([string]$Path) { [System.IO.File]::ReadAllText($Path, $script:Utf8NoBom) }
function WriteText([string]$Path, [string]$Content) { $parent = Split-Path -Parent $Path; if ($parent -and -not (Test-Path -LiteralPath $parent)) { New-Item -ItemType Directory -Path $parent -Force | Out-Null }; [System.IO.File]::WriteAllText($Path, $Content, $script:Utf8NoBom) }
function EnsureDir([string]$Path) { if (-not (Test-Path -LiteralPath $Path)) { New-Item -ItemType Directory -Path $Path -Force | Out-Null } }
function CopyIfExists([string]$Source, [string]$Dest) { if (Test-Path -LiteralPath $Source) { Copy-Item -LiteralPath $Source -Destination $Dest -Force } }
function CopyChildrenIfExists([string]$SourceDir, [string]$DestDir) { if (Test-Path -LiteralPath $SourceDir) { EnsureDir $DestDir; Get-ChildItem -LiteralPath $SourceDir -Force | ForEach-Object { Copy-Item -LiteralPath $_.FullName -Destination $DestDir -Recurse -Force } } }
function CopyStateTemplate([string]$Name, [string]$Dest) { CopyIfExists (Join-Path $script:StateTemplateRoot $Name) $Dest }
function Norm([string]$Value) { if ([string]::IsNullOrWhiteSpace($Value)) { return "" }; return (($Value.ToLowerInvariant() -replace '[^\p{L}\p{Nd}]+', ' ').Trim()) }
function HasText([string]$Hay, [string]$Needle) { if ([string]::IsNullOrWhiteSpace($Needle)) { return $true }; return (Norm $Hay) -like "*$(Norm $Needle)*" }

$raw = @($args)
if ($raw.Count -gt 0 -and $raw[0] -eq 'asset-lib') { $raw = if ($raw.Count -gt 1) { @($raw[1..($raw.Count - 1)]) } else { @() } }
$raw = @($raw)
$known = @('help','init','libs','info','path','index','search','compose','chapter-context')
$action = 'help'; $actionIndex = -1
for ($i = 0; $i -lt $raw.Count; $i++) { if ([string]$raw[$i] -in $known) { $action = [string]$raw[$i]; $actionIndex = $i; break } }

function GetOpt([string[]]$Tokens, [string[]]$Names, [string]$Default = '') { for ($i=0; $i -lt $Tokens.Count; $i++) { $t=[string]$Tokens[$i]; foreach($name in $Names){ if($t -eq $name -or $t -eq ($name -replace '^-{1,2}','-')){ if($i+1 -lt $Tokens.Count){ return [string]$Tokens[$i+1] } }; if($t.StartsWith("$name=")){ return $t.Substring($name.Length+1) } } }; return $Default }
function GetMultiOpt([string[]]$Tokens, [string[]]$Names) { $values=@(); for($i=0;$i -lt $Tokens.Count;$i++){ $t=[string]$Tokens[$i]; foreach($name in $Names){ if($t -eq $name -or $t -eq ($name -replace '^-{1,2}','-')){ if($i+1 -lt $Tokens.Count){ $values += [string]$Tokens[$i+1]; $i++ } } elseif($t.StartsWith("$name=")){ $values += $t.Substring($name.Length+1) } } }; return @($values) }
function HasFlag([string[]]$Tokens, [string[]]$Names) { foreach($t in $Tokens){ if([string]$t -in $Names){ return $true } }; return $false }
function Positional([string[]]$Tokens) { $r=@(); for($i=0;$i -lt $Tokens.Count;$i++){ $t=[string]$Tokens[$i]; if($t -in $known){ continue }; if($t.StartsWith('-')){ if($t -match '^(--?)(root|lib|query|kind|stage|chapter|from|to|out|name|force|include-default)(=.+)?$'){ if($t -notlike '*=*' -and $i+1 -lt $Tokens.Count){ $i++ } }; continue }; $r += $t }; return @($r) }
function GetRoot([string[]]$Tokens) { [System.IO.Path]::GetFullPath((GetOpt $Tokens @('--root','-root') $script:DefaultRoot)) }
function GetLib([string[]]$Tokens) { $lib=GetOpt $Tokens @('--lib','-lib') ''; if([string]::IsNullOrWhiteSpace($lib)){ $pos=@(Positional $Tokens); if($pos.Count -gt 0){ $lib=[string]$pos[0] } }; if([string]::IsNullOrWhiteSpace($lib)){ $lib='default' }; if($lib -match '[\\/:*?"<>|]'){ Fail "Invalid library name '$lib'." }; return $lib }
function LibPath([string[]]$Tokens) { Join-Path (GetRoot $Tokens) (GetLib $Tokens) }
function Rel([string]$Base,[string]$Path){ [System.IO.Path]::GetRelativePath($Base,$Path) -replace '\\','/' }

function KindFromRel([string]$Rel) { if($Rel -like 'assets/characters/*'){return 'character'}; if($Rel -like 'assets/factions/*'){return 'faction'}; if($Rel -like 'assets/planning/*'){return 'planning'}; if($Rel -like 'assets/worldview/*'){return 'worldview'}; if($Rel -like 'outlines/rough/*'){return 'rough-outline'}; if($Rel -like 'outlines/emotion/*'){return 'emotion-outline'}; if($Rel -like 'outlines/volume/*'){return 'volume-outline'}; if($Rel -like 'outlines/arc/*'){return 'arc-outline'}; if($Rel -like 'outlines/five-chapter/*'){return 'five-chapter-outline'}; if($Rel -like 'outlines/chapter-detail/*'){return 'chapter-detail'}; if($Rel -like 'drafts/chapters/*'){return 'chapter-draft'}; if($Rel -like 'states/*'){return 'state'}; if($Rel -like 'snapshots/*'){return 'snapshot'}; if($Rel -like 'logs/*'){return 'log'}; if($Rel -like 'inbox/*'){return 'inbox'}; if($Rel -like 'templates/*'){return 'template'}; return 'other' }
function StageFromRel([string]$Rel) { if($Rel -like 'assets/planning/*'){return 'planning'}; if($Rel -like 'assets/worldview/*'){return 'worldview'}; if($Rel -like 'outlines/rough/*'){return 'rough'}; if($Rel -like 'outlines/emotion/*'){return 'emotion'}; if($Rel -like 'outlines/volume/*' -or $Rel -like 'states/volume/*'){return 'volume'}; if($Rel -like 'outlines/arc/*' -or $Rel -like 'states/arc/*'){return 'arc'}; if($Rel -like 'outlines/five-chapter/*' -or $Rel -like 'states/five-chapter/*'){return 'five-chapter'}; if($Rel -like 'outlines/chapter-detail/*' -or $Rel -like 'states/chapter-interval/*'){return 'chapter'}; return '' }

function InitLib([string[]]$Tokens) {
    $libPath=LibPath $Tokens; EnsureDir $libPath
    $dirs=@('assets\planning','assets\worldview','assets\characters','assets\factions','outlines\rough','outlines\emotion','outlines\volume','outlines\arc','outlines\five-chapter','outlines\chapter-detail','drafts\chapters','states\volume','states\arc','states\five-chapter','states\chapter-interval','snapshots','logs','inbox','tmp','composed-context','indexes','templates')
    foreach($d in $dirs){ EnsureDir (Join-Path $libPath $d) }
    CopyStateTemplate '00-动态资产库说明.md' (Join-Path $libPath 'README.md')
    CopyStateTemplate '01-资产总表模板.md' (Join-Path $libPath '01-资产总表.md')
    CopyStateTemplate '02-新增对象收件箱模板.md' (Join-Path $libPath 'inbox\新增对象收件箱.md')
    CopyStateTemplate '03-当前状态快照模板.md' (Join-Path $libPath 'snapshots\当前状态快照.md')
    CopyStateTemplate '07-状态变更日志模板.md' (Join-Path $libPath 'logs\状态变更日志.md')
    CopyStateTemplate '08-状态细化规则.md' (Join-Path $libPath '状态细化规则.md')
    CopyIfExists (Join-Path $script:WritingTemplateRoot '01_作品企划\00-作品企划总表.md') (Join-Path $libPath 'assets\planning\00-作品企划.md')
    CopyChildrenIfExists (Join-Path $script:WritingTemplateRoot '02_世界观') (Join-Path $libPath 'assets\worldview')
    CopyChildrenIfExists (Join-Path $script:WritingTemplateRoot '03_势力') (Join-Path $libPath 'assets\factions')
    CopyChildrenIfExists (Join-Path $script:WritingTemplateRoot '04_人物') (Join-Path $libPath 'assets\characters')
    $map=@{ '05_故事粗纲'='outlines\rough'; '06_情感线粗纲'='outlines\emotion'; '08_卷纲'='outlines\volume'; '10_小篇章纲'='outlines\arc'; '12_五章纲'='outlines\five-chapter'; '14_单章节细纲'='outlines\chapter-detail'; '15_章节写作'='drafts\chapters' }
    foreach($k in $map.Keys){ CopyChildrenIfExists (Join-Path $script:WritingTemplateRoot $k) (Join-Path $libPath $map[$k]) }
    $manifest=Join-Path $libPath 'asset-library.json'
    $meta=[ordered]@{ name=GetLib $Tokens; description='Novel writing dynamic asset library'; createdAt=(Get-Date).ToString('s'); updatedAt=(Get-Date).ToString('s'); version=2; layout='writing-dynamic-assets-v2'; includes=@('planning','worldview','characters','factions','outlines','states','snapshots','logs','inbox') }
    WriteText $manifest ($meta | ConvertTo-Json -Depth 8)
    IndexLib $Tokens | Out-Null
    Write-Output "Initialized asset library: $libPath"
}

function ListLibs([string[]]$Tokens){ $root=GetRoot $Tokens; if(-not(Test-Path -LiteralPath $root)){ Write-Output "No asset library root found: $root"; return }; Get-ChildItem -LiteralPath $root -Directory | Sort-Object Name | ForEach-Object { if(Test-Path -LiteralPath (Join-Path $_.FullName 'asset-library.json')){ Write-Output ("{0}`n  Path: {1}" -f $_.Name,$_.FullName) } } }
function GetRecords([string[]]$Tokens){ $libPath=LibPath $Tokens; if(-not(Test-Path -LiteralPath $libPath)){ Fail "Library not found: $libPath. Run init first." }; $kind=GetOpt $Tokens @('--kind','-kind') 'any'; $stage=GetOpt $Tokens @('--stage','-stage') ''; $queries=@(GetMultiOpt $Tokens @('--query','-query')); $chapter=GetOpt $Tokens @('--chapter','-chapter') ''; $from=GetOpt $Tokens @('--from','-from') ''; $to=GetOpt $Tokens @('--to','-to') ''; $patterns=@(); if($chapter){$n=[int]$chapter; $patterns+=@("第 $n 章",("第{0}章" -f $n),("ch{0:D3}" -f $n),("{0:D3}" -f $n),"chapter $n")}; if($from -and $to){$f=[int]$from;$t=[int]$to;$patterns+=@(("ch{0:D3}-ch{1:D3}" -f $f,$t),("ch{0:D3}-{1:D3}" -f $f,$t),"第 $f-$t 章",("第{0}-{1}章" -f $f,$t),"$f-$t")}; $records=@(); foreach($file in @(Get-ChildItem -LiteralPath $libPath -Recurse -File -Filter '*.md' | Sort-Object FullName)){ $rel=Rel $libPath $file.FullName; if($rel -like 'composed-context/*'){continue}; $k=KindFromRel $rel; $s=StageFromRel $rel; if($kind -ne 'any' -and $kind -ne $k){continue}; if($stage -and -not(HasText "$rel $s" $stage)){continue}; $body=ReadText $file.FullName; $hay="$rel`n$body"; $ok=$true; foreach($q in $queries){ if(-not(HasText $hay $q)){ $ok=$false; break } }; if($ok -and $patterns.Count -gt 0){ $ok=$false; foreach($p in $patterns){ if(HasText $hay $p){$ok=$true;break} } }; if($ok){ $records += [pscustomobject]@{ kind=$k; stage=$s; relativePath=$rel; path=$file.FullName; excerpt=(($body -split "\r?\n" | Where-Object {$_.Trim()} | Select-Object -First 8) -join "`n"); content=$body } } }; return @($records) }

function IndexLib([string[]]$Tokens){ $libPath=LibPath $Tokens; if(-not(Test-Path -LiteralPath $libPath)){ Fail "Library not found: $libPath" }; $records=@(); foreach($file in @(Get-ChildItem -LiteralPath $libPath -Recurse -File -Filter '*.md' | Sort-Object FullName)){ $rel=Rel $libPath $file.FullName; if($rel -like 'composed-context/*'){continue}; $body=ReadText $file.FullName; $title=(($body -split "\r?\n" | Where-Object { $_ -match '^#\s+' } | Select-Object -First 1) -replace '^#\s+',''); $records += [ordered]@{ kind=KindFromRel $rel; stage=StageFromRel $rel; title=$title; relativePath=$rel; path=$file.FullName; updatedAt=$file.LastWriteTime.ToString('s') } }; $index=[ordered]@{ library=GetLib $Tokens; generatedAt=(Get-Date).ToString('s'); count=$records.Count; records=$records }; $out=Join-Path $libPath 'indexes\asset-index.json'; WriteText $out ($index | ConvertTo-Json -Depth 10); Write-Output $out }
function InfoLib([string[]]$Tokens){ $libPath=LibPath $Tokens; if(-not(Test-Path -LiteralPath $libPath)){ Fail "Library not found: $libPath" }; $files=@(Get-ChildItem -LiteralPath $libPath -Recurse -File -Filter '*.md'); Write-Output "Asset library: $(GetLib $Tokens)"; Write-Output "Path: $libPath"; Write-Output "Markdown files: $($files.Count)"; foreach($g in $files | Group-Object { KindFromRel (Rel $libPath $_.FullName) } | Sort-Object Name){ Write-Output ("  {0}: {1}" -f $g.Name,$g.Count) } }
function SearchLib([string[]]$Tokens){ $records=@(GetRecords $Tokens); if(HasFlag $Tokens @('--json','-json')){ $records | Select-Object kind,stage,relativePath,path,excerpt | ConvertTo-Json -Depth 5; return }; if($records.Count -eq 0){Write-Output 'No matching asset records.'; return}; $include=HasFlag $Tokens @('--include-content','-include-content'); foreach($r in $records){ Write-Output ("[{0}] {1}" -f $r.kind,$r.relativePath); Write-Output ("  Path: {0}" -f $r.path); if($r.stage){Write-Output ("  Stage: {0}" -f $r.stage)}; if($include){Write-Output '  --- excerpt ---'; Write-Output $r.excerpt} } }
function ComposeOut([string[]]$Tokens){ $records=@(GetRecords $Tokens); if($records.Count -eq 0){ Fail 'No matching records to compose.' }; $libPath=LibPath $Tokens; $out=GetOpt $Tokens @('--out','-out') ''; if(-not$out){$out=Join-Path $libPath ("composed-context\context-{0}.md" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))}; $sb=New-Object System.Text.StringBuilder; [void]$sb.AppendLine('# 动态资产库合成上下文'); [void]$sb.AppendLine(); [void]$sb.AppendLine('## 合成信息'); [void]$sb.AppendLine("- 子库：$(GetLib $Tokens)"); [void]$sb.AppendLine("- 子库路径：$libPath"); [void]$sb.AppendLine("- 生成时间：$(Get-Date -Format s)"); [void]$sb.AppendLine("- 命中数量：$($records.Count)"); $order=@('planning','worldview','character','faction','rough-outline','emotion-outline','volume-outline','arc-outline','five-chapter-outline','chapter-detail','state','snapshot','log','inbox','chapter-draft','other'); foreach($r in $records | Sort-Object @{Expression={$order.IndexOf($_.kind)}}, relativePath){ [void]$sb.AppendLine('---'); [void]$sb.AppendLine("## [$($r.kind)] $($r.relativePath)"); [void]$sb.AppendLine(); [void]$sb.AppendLine("来源：$($r.path)"); [void]$sb.AppendLine(); [void]$sb.AppendLine('```markdown'); [void]$sb.AppendLine($r.content); [void]$sb.AppendLine('```'); [void]$sb.AppendLine() }; WriteText $out $sb.ToString(); Write-Output $out }
function ComposeRecords([object[]]$Records,[string[]]$Tokens,[string]$Title,[string]$OutPrefix){ if($Records.Count -eq 0){ Fail 'No matching records to compose.' }; $libPath=LibPath $Tokens; $out=GetOpt $Tokens @('--out','-out') ''; if(-not$out){$out=Join-Path $libPath ("composed-context\$OutPrefix-{0}.md" -f (Get-Date -Format 'yyyyMMdd-HHmmss'))}; $sb=New-Object System.Text.StringBuilder; [void]$sb.AppendLine("# $Title"); [void]$sb.AppendLine(); [void]$sb.AppendLine('## 合成信息'); [void]$sb.AppendLine("- 子库：$(GetLib $Tokens)"); [void]$sb.AppendLine("- 子库路径：$libPath"); [void]$sb.AppendLine("- 生成时间：$(Get-Date -Format s)"); [void]$sb.AppendLine("- 命中数量：$($Records.Count)"); [void]$sb.AppendLine(); [void]$sb.AppendLine('## 使用建议'); [void]$sb.AppendLine('- 写章节前优先阅读：作品企划、世界观、相关人物/势力、当前快照、章节相关状态、章节细纲。'); [void]$sb.AppendLine('- 若正文实际偏离大纲，写完后更新状态变更日志和下一章节间状态。'); $order=@('planning','worldview','character','faction','rough-outline','emotion-outline','volume-outline','arc-outline','five-chapter-outline','chapter-detail','state','snapshot','log','inbox','chapter-draft','other'); foreach($r in $Records | Sort-Object @{Expression={$order.IndexOf($_.kind)}}, relativePath){ [void]$sb.AppendLine('---'); [void]$sb.AppendLine("## [$($r.kind)] $($r.relativePath)"); [void]$sb.AppendLine(); [void]$sb.AppendLine("来源：$($r.path)"); [void]$sb.AppendLine(); [void]$sb.AppendLine('```markdown'); [void]$sb.AppendLine($r.content); [void]$sb.AppendLine('```'); [void]$sb.AppendLine() }; WriteText $out $sb.ToString(); Write-Output $out }
function MergeRecords([object[]]$A,[object[]]$B){ $map=@{}; foreach($r in @($A)+@($B)){ if($null -ne $r -and -not $map.ContainsKey($r.path)){ $map[$r.path]=$r } }; return @($map.Values) }
function ChapterContext([string[]]$Tokens){ $chapter=GetOpt $Tokens @('--chapter','-chapter') ''; if(-not$chapter){ Fail 'chapter-context requires --chapter <n>.' }; $lib=GetLib $Tokens; $root=GetRoot $Tokens; $base=@('--lib',$lib,'--root',$root); $records=@(); foreach($k in @('planning','worldview','snapshot')){ $records=MergeRecords $records (GetRecords (@($base)+@('--kind',$k))) }; foreach($k in @('chapter-detail','state','chapter-draft','log')){ $records=MergeRecords $records (GetRecords (@($base)+@('--kind',$k,'--chapter',$chapter))) }; $queries=@(GetMultiOpt $Tokens @('--query','-query')); foreach($q in $queries){ foreach($k in @('character','faction','rough-outline','emotion-outline','volume-outline','arc-outline','five-chapter-outline','chapter-detail','state','snapshot','log','inbox')){ $records=MergeRecords $records (GetRecords (@($base)+@('--kind',$k,'--query',$q))) } }; ComposeRecords $records $Tokens ("第 $chapter 章写作上下文") 'chapter-context' }

switch($action){
 'help' { @"
novel-writing writing asset-lib

动态资产库用于管理小说写作过程中产生的中间资产；它不是素材图书馆。
一个子库通常对应一本小说/一个实验版本，里面包含作品企划、世界观、人物、势力、各级大纲、章节细纲、章节正文、状态快照和变更日志。

Usage:
  mycli novel-writing writing asset-lib init --lib <name>
  mycli novel-writing writing asset-lib libs
  mycli novel-writing writing asset-lib info --lib <name>
  mycli novel-writing writing asset-lib path --lib <name>
  mycli novel-writing writing asset-lib index --lib <name>
  mycli novel-writing writing asset-lib search --lib <name> [--query <text>] [--kind <kind>] [--chapter <n>]
  mycli novel-writing writing asset-lib compose --lib <name> [--query <text>] [--kind <kind>] [--chapter <n>] [--out <path>]
  mycli novel-writing writing asset-lib chapter-context --lib <name> --chapter <n> [--query <text>] [--out <path>]

Core workflow:
  1. 初始化子库：
     mycli novel-writing writing asset-lib init --lib 我的小说

  2. 填写/维护子库中的中间资产：
     assets/planning/          作品企划
     assets/worldview/         世界观
     assets/characters/        人物
     assets/factions/          势力
     outlines/rough/           故事粗纲
     outlines/emotion/         情感线粗纲
     outlines/volume/          卷纲
     outlines/arc/             小篇章纲
     outlines/five-chapter/    五章纲
     outlines/chapter-detail/  单章节细纲
     states/                   动态状态
     snapshots/                当前状态快照
     logs/                     状态变更日志
     inbox/                    新增人物势力收件箱

  3. 生成/刷新索引：
     mycli novel-writing writing asset-lib index --lib 我的小说

  4. 检索写作资产：
     mycli novel-writing writing asset-lib search --lib 我的小说 --query 苏清雪
     mycli novel-writing writing asset-lib search --lib 我的小说 --kind faction --query 天剑宗
     mycli novel-writing writing asset-lib search --lib 我的小说 --kind worldview
     mycli novel-writing writing asset-lib search --lib 我的小说 --kind volume-outline
     mycli novel-writing writing asset-lib search --lib 我的小说 --chapter 6

  5. 合成上下文 Markdown：
     mycli novel-writing writing asset-lib compose --lib 我的小说 --query 苏清雪 --query 天剑宗

  6. 一键生成章节写作上下文：
     mycli novel-writing writing asset-lib chapter-context --lib 我的小说 --chapter 6 --query 苏清雪 --query 天剑宗

Search options:
  --lib <name>              子库名。必备；不填时使用 default。
  --root <path>             动态资产库根目录。默认是 writing/asset-libraries。
  --query <text>            文本检索，可重复。会匹配路径和 Markdown 正文。
  --kind <kind>             按资产类型过滤。
  --stage <stage>           按阶段/颗粒度过滤，如 planning/worldview/volume/arc/five-chapter/chapter。
  --chapter <n>             匹配某章相关文件。
  --from <n> --to <n>       匹配章节区间。
  --json                    输出 JSON。
  --include-content         search 时显示内容摘录。
  --out <path>              compose/chapter-context 输出路径。不填则输出到 composed-context/。

Kinds include: planning, worldview, character, faction, rough-outline, emotion-outline, volume-outline, arc-outline, five-chapter-outline, chapter-detail, state, snapshot, log, inbox, chapter-draft, template, other.
"@ | Write-Output }
 'init' { InitLib $raw }
 'libs' { ListLibs $raw }
 'info' { InfoLib $raw }
 'path' { Write-Output (LibPath $raw) }
 'index' { IndexLib $raw }
 'search' { SearchLib $raw }
 'compose' { ComposeOut $raw }
 'chapter-context' { ChapterContext $raw }
 default { Fail "Unknown asset-lib action '$action'." }
}
