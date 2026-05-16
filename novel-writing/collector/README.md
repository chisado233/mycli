# novel-writing collector

## Summary

小说平台采集模块。当前首选平台为 **番茄小说**，用于讨论和后续实现番茄小说公开信息的采集、整理、清洗与拆书输入格式。

## Source

`D:\agent_workspace\capability-library\skill-library\novel-writing\modules\collector.md`

## Command List

- `open`
- `show`
- `inspect`
- `import-text`
- `tomato-start`
- `tomato-download`
- `tomato-export-md`
- `tomato-rank`

## Target Platform

### 番茄小说

首期围绕番茄小说平台设计采集链路，优先处理用户提供的合法输入，例如：

- 番茄小说作品链接
- 用户手动保存的公开页面内容
- 用户拥有合法使用权的章节文本或导出文件

### 采集范围边界

优先支持：

- 作品基础信息：书名、作者、简介、封面、分类、标签、状态、字数等公开信息
- 目录信息：卷、章节标题、章节顺序、更新时间等公开目录信息
- 榜单/推荐位/标签页等公开列表信息（后续能力）
- 用户提供的章节正文整理、清洗、归档

不做或暂不做：

- 绕过登录、验证码、风控或反爬机制
- 采集付费、未公开或需要特殊权限的正文内容
- 高频请求、批量压测或任何可能影响平台服务的行为

## Proposed Output

番茄小说采集结果建议统一落到某个小说项目目录中，供拆书模块继续使用：

```text
<novel-project>/
  source/
    fanqie/
      work.json          # 作品元信息
      catalog.json       # 目录结构
      chapters/          # 用户提供或合法导出的正文清洗结果
        0001.md
        0002.md
  analysis-input/
    deconstruction.md    # 给拆书模块的输入摘要
```

其中 `work.json` 和 `catalog.json` 应尽量保留原始字段与标准化字段，方便后续复查来源。

## Usage Examples

```powershell
mycli novel-writing collector open
mycli novel-writing collector show
mycli novel-writing collector inspect D:\agent_workspace\tmp\novel-import\fanqie-first-book\raw\book.txt
mycli novel-writing collector import-text D:\agent_workspace\tmp\novel-import\fanqie-first-book\raw\book.txt D:\agent_workspace\tmp\novel-import\fanqie-first-book

# 启动番茄小说下载器 Web UI，并把原始下载目录配置到 collector\books\.tomato-raw
mycli novel-writing collector tomato-start

# 下载一本番茄小说，并自动导出为：collector\books\小说名\章节\01-章节名.md
mycli novel-writing collector tomato-download 7467634647355100222

# 将已有 Tomato txt 手动切分为 Markdown 章节
mycli novel-writing collector tomato-export-md D:\path\book.txt

# 按搜索结果中的阅读、书架、评分、在读等字段做粗略热度筛选
mycli novel-writing collector tomato-rank --keywords "修仙,神豪,都市,系统" --limit 20
```

## Tomato Downloader Integration

本包已接入本地 `Tomato-Novel-Downloader-main` 下载器，默认用于番茄小说采集。

### 默认目录

以后番茄小说默认落到：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\collector\books
```

目录结构：

```text
books\
  .tomato-raw\                 # 下载器原始 txt 与缓存目录
  小说名\
    catalog.json                # Markdown 章节索引
    章节\
      01-章节名.md
      02-章节名.md
```

### 命令说明

#### `tomato-start`

启动 Tomato Novel Downloader Web UI，并确保下载器配置为：

- 原始保存目录：`books\.tomato-raw`
- 输出格式：`txt`
- 不生成有声书
- 不下载段评
- 单下载任务串行执行

```powershell
mycli novel-writing collector tomato-start
mycli novel-writing collector tomato-start --restart
mycli novel-writing collector tomato-start --addr 127.0.0.1:18423
```

默认 Web UI 地址：

```text
http://127.0.0.1:18423/
```

#### `tomato-download`

按 book_id 下载小说，并在下载完成后自动把 txt 拆成每章一个 Markdown 文件。

```powershell
mycli novel-writing collector tomato-download <book_id>
mycli novel-writing collector tomato-download <book_id> --no-export
```

`cli.package.json` 中保留了 `--range-start/--range-end` 参数描述，但当前封装默认拒绝范围下载：Tomato Web UI 在已有本地记录时可能复用全量记录，且 API 进度会按全目录统计。为保证 “小说名/章节/编号-章节名.md” 导出稳定，默认使用全本下载/导出。

输出示例：

```text
books\第一投资人，天命之女养成计划\章节\001-第1章 要不给她打一针.md
```

编号宽度会按章节总数自动调整：少于 100 章时类似 `01-...md`，几百章时类似 `001-...md`。

#### `tomato-export-md`

把已有 txt 文件重新切分为 Markdown 章节。

```powershell
mycli novel-writing collector tomato-export-md D:\path\book.txt
mycli novel-writing collector tomato-export-md D:\path\book.txt --title 小说名 --overwrite
```

#### `tomato-rank`

用下载器 Web UI 的搜索 API 做低频搜索，然后按搜索结果里的公开字段粗筛高热度小说。

```powershell
mycli novel-writing collector tomato-rank
mycli novel-writing collector tomato-rank --keywords "修仙,神豪,都市,系统" --limit 30
mycli novel-writing collector tomato-rank --keywords "玄幻脑洞,都市脑洞,多女主" --out D:\agent_workspace\tmp\tomato-rank
mycli novel-writing collector tomato-rank --keywords "修仙,神豪" --min-rating 8.5 --min-shelf 1000000 --min-current-read 50000 --min-words 1000000 --all
```

默认报告目录：

```text
books\_rankings\
  tomato-hot-YYYYMMDD-HHMMSS.md
  tomato-hot-YYYYMMDD-HHMMSS.json
```

热度分是粗筛指标，不是番茄官方榜单。当前参考字段包括：

- `read_count_all`：累计阅读
- `shelf_cnt_history`：加入书架历史
- `read_count` / `read_cnt_text`：当前阅读/在读文本
- `score`：评分
- `word_number`、章节数、连载/完结与更新状态

##### 参数总览

`tomato-rank` 的基本模式是：先按 `--keywords` 低频搜索，得到一批候选书；再对候选书做本地筛选；最后把筛选命中的书按 `hot_score`、累计阅读、书架数降序排序并返回。

```powershell
mycli novel-writing collector tomato-rank [--keywords <关键词列表>] [筛选参数...] [--limit <n>|--all] [--out <dir>]
```

###### 搜索与输出参数

```powershell
--keywords <text>
```

- 作用：设置搜索关键词，多个关键词用英文/中文逗号或分号分隔。
- 默认：`玄幻,修仙,都市,系统,神豪,重生,末世,历史,悬疑,多女主`
- 示例：

```powershell
mycli novel-writing collector tomato-rank --keywords "修仙,神豪,都市脑洞"
```

```powershell
--limit <n>
```

- 作用：最多返回前 `n` 条筛选结果。
- 默认：`30`
- 注意：如果加了 `--all`，则不按 `--limit` 截断。

```powershell
--all
```

- 作用：返回所有筛选命中的结果。
- 适合：你想把筛选后的完整候选集交给后续分析，而不是只看前几十名。

```powershell
--out <dir>
```

- 作用：设置报告输出目录。
- 默认：`D:\agent_workspace\capability-library\mycli\novel-writing\collector\books\_rankings`
- 输出文件：
  - `tomato-hot-YYYYMMDD-HHMMSS.md`
  - `tomato-hot-YYYYMMDD-HHMMSS.json`

###### 数值范围筛选参数

所有范围筛选都支持只写最小值、只写最大值，或同时写最小/最大值。

```powershell
--min-rating <n>
--max-rating <n>
```

- 作用：按评分范围筛选。
- 字段来源：搜索结果 `score`。
- 示例：只要评分不低于 8.5：

```powershell
mycli novel-writing collector tomato-rank --keywords "修仙" --min-rating 8.5
```

```powershell
--min-shelf <n>
--max-shelf <n>
```

- 作用：按加入书架历史数量筛选。
- 字段来源：`shelf_cnt_history`。
- 适合：找长期被大量读者收藏/追读过的书。
- 示例：书架历史至少 100 万：

```powershell
mycli novel-writing collector tomato-rank --keywords "神豪" --min-shelf 1000000
```

```powershell
--min-current-read <n>
--max-current-read <n>
```

- 作用：按当前阅读/在读数量筛选。
- 字段来源：优先取 `read_count` 与解析后的 `read_cnt_text` 中较大值。
- 适合：找当前仍然有热度的书。
- 示例：在读不少于 5 万：

```powershell
mycli novel-writing collector tomato-rank --keywords "都市" --min-current-read 50000
```

```powershell
--min-total-read <n>
--max-total-read <n>
```

- 作用：按累计阅读数筛选。
- 字段来源：`read_count_all`。
- 适合：找历史大爆款或排除过小样本。
- 示例：累计阅读不少于 1000 万：

```powershell
mycli novel-writing collector tomato-rank --keywords "玄幻" --min-total-read 10000000
```

```powershell
--min-words <n>
--max-words <n>
```

- 作用：按字数筛选。
- 字段来源：`word_number`。
- 适合：控制拆书体量，例如只看 100 万字以上、500 万字以下。
- 示例：100 万字到 300 万字：

```powershell
mycli novel-writing collector tomato-rank --keywords "修仙" --min-words 1000000 --max-words 3000000
```

```powershell
--min-chapters <n>
--max-chapters <n>
```

- 作用：按章节数筛选。
- 字段来源：优先 `serial_count`，没有则取 `chapter_number`。
- 适合：排除短篇、断更早期作品，或限制超长篇。
- 示例：章节数 300 到 1500：

```powershell
mycli novel-writing collector tomato-rank --keywords "系统" --min-chapters 300 --max-chapters 1500
```

```powershell
--min-hot-score <n>
--max-hot-score <n>
```

- 作用：按本工具计算的粗略热度分筛选。
- `hot_score` 不是官方分数，只用于候选粗排。
- 示例：只看热度分 550 以上：

```powershell
mycli novel-writing collector tomato-rank --keywords "都市,神豪" --min-hot-score 550
```

###### 状态与文本筛选参数

```powershell
--status <completed|serializing|raw-code>
```

- 作用：按完结/连载状态筛选。
- 可用值：
  - `completed`：完结
  - `serializing`：连载
  - 也可传搜索结果里的原始状态码
- 支持逗号分隔多个值。
- 示例：只看完结书：

```powershell
mycli novel-writing collector tomato-rank --keywords "修仙" --status completed
```

```powershell
--include <关键词列表>
```

- 作用：标题、作者、分类、标签、简介中只要包含任一关键词就保留。
- 多个关键词用逗号/分号分隔。
- 示例：只保留带“多女主”或“系统”的结果：

```powershell
mycli novel-writing collector tomato-rank --keywords "玄幻" --include "多女主,系统"
```

```powershell
--exclude <关键词列表>
```

- 作用：标题、作者、分类、标签、简介中只要包含任一关键词就排除。
- 多个关键词用逗号/分号分隔。
- 示例：排除“女频/言情/古代言情”倾向结果：

```powershell
mycli novel-writing collector tomato-rank --keywords "修仙" --exclude "言情,古代言情,女频"
```

##### 常用筛选组合

找高评分、高书架、高当前热度、百万字以上的候选：

```powershell
mycli novel-writing collector tomato-rank --keywords "修仙,神豪" --min-rating 8.5 --min-shelf 1000000 --min-current-read 50000 --min-words 1000000 --all
```

找完结、长篇、评分较高的修仙书：

```powershell
mycli novel-writing collector tomato-rank --keywords "修仙" --status completed --min-rating 8.8 --min-words 1500000 --min-chapters 500 --all
```

找当前仍有热度的都市/神豪候选，并排除短篇：

```powershell
mycli novel-writing collector tomato-rank --keywords "都市,神豪" --min-current-read 100000 --min-words 1000000 --min-chapters 300 --all
```

找中等体量、适合快速拆书的候选：

```powershell
mycli novel-writing collector tomato-rank --keywords "玄幻脑洞,都市脑洞" --min-rating 8.0 --min-words 800000 --max-words 2500000 --min-shelf 200000 --all
```

##### 返回结果说明

命令会直接输出 JSON，核心字段如下：

```json
{
  "status": "ok",
  "count": 5,
  "totalCandidates": 38,
  "filteredCount": 12,
  "markdown": "...tomato-hot-YYYYMMDD-HHMMSS.md",
  "json": "...tomato-hot-YYYYMMDD-HHMMSS.json",
  "items": [
    {
      "book_id": "...",
      "title": "...",
      "author": "...",
      "hot_score": 600.42,
      "rating": 9.6,
      "read_count_all": 27332745,
      "current_read_count": 537000,
      "shelf_count": 9993947,
      "word_number": 1899187,
      "chapters": 627,
      "category": "...",
      "tags": "...",
      "status": "completed",
      "latest_chapter": "...",
      "abstract": "..."
    }
  ]
}
```

- `totalCandidates`：搜索 API 返回并去重后的候选总数。
- `filteredCount`：经过筛选条件后命中的总数。
- `count`：本次实际返回的数量；如果没加 `--all`，会受 `--limit` 截断。
- `items`：筛选后的小说列表，后续下载可直接取其中的 `book_id`。

##### 筛选参数速查

```powershell
--min-rating <n> / --max-rating <n>                 # 评分范围
--min-shelf <n> / --max-shelf <n>                   # 加入书架历史数量范围
--min-current-read <n> / --max-current-read <n>      # 在读/当前阅读数量范围
--min-total-read <n> / --max-total-read <n>          # 累计阅读范围
--min-words <n> / --max-words <n>                   # 字数范围
--min-chapters <n> / --max-chapters <n>             # 章节数范围
--min-hot-score <n> / --max-hot-score <n>           # 热度分范围
--status completed|serializing                      # 完结/连载过滤，可逗号分隔
--include "关键词1,关键词2"                         # 标题/作者/分类/标签/简介包含任一词
--exclude "关键词1,关键词2"                         # 排除包含任一词的结果
--all                                                # 返回所有命中，不按 --limit 截断
```

命令返回 JSON 中 `items` 就是筛选后的完整结果（若未加 `--all`，最多返回 `--limit` 条）；同时报告文件会保存 Markdown 和 JSON 版本。

筛到候选后，可以用：

```powershell
mycli novel-writing collector tomato-download <book_id>
```

下载并拆成 Markdown 章节。

### 注意

- 该集成只使用下载器自身的 Web UI/API，不修改下载器源码。
- 请仅下载你有合法使用权的公开内容。
- 默认不做高并发下载；不要调高并发或批量压测平台接口。
- 原始 txt 保留在 `.tomato-raw`，Markdown 章节是后续拆书/分析的默认输入。

## Local Phone-to-PC Import Flow

首期跑通一本小说时，优先采用“手机端合法下载/复制/导出，电脑端本地导入”的流程：

1. 在手机端番茄小说 App 中获取用户有权使用的文本内容。
2. 将可读的 `.txt` 或 `.md` 文件传到电脑，例如：

   ```text
   D:\agent_workspace\tmp\novel-import\fanqie-first-book\raw\book.txt
   ```

3. 先检查章节识别效果：

   ```powershell
   mycli novel-writing collector inspect D:\agent_workspace\tmp\novel-import\fanqie-first-book\raw\book.txt
   ```

4. 再导入为结构化小说项目：

   ```powershell
   mycli novel-writing collector import-text D:\agent_workspace\tmp\novel-import\fanqie-first-book\raw\book.txt D:\agent_workspace\tmp\novel-import\fanqie-first-book
   ```

导入后会生成：

```text
<out>/
  source/
    fanqie/
      work.json
      catalog.json
      chapters/
        0001.md
        0002.md
  analysis-input/
    deconstruction.md
```

## Next Implementation Notes

后续实现番茄小说采集命令时，建议先增加只读、低风险能力：

1. `parse-url`：解析番茄小说作品链接，提取作品标识。
2. `normalize-input`：把用户提供的页面文本、HTML 或章节文件整理成统一中间格式。
3. `export-project`：输出到小说项目目录，生成 `work.json`、`catalog.json` 与拆书输入草稿。

若需要真实访问网络页面，应默认限速、缓存、可重试，并明确记录来源 URL、采集时间与用户输入来源。
