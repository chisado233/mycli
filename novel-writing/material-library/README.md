# novel-writing material-library

## Summary

素材图书馆模块。用于讨论和后续实现人物原型、职业资料、新闻案件、场景灵感、对白片段、桥段梗等内容素材的存储、检索与项目引用。

## Literary Requirements for AI Writers

本素材图书馆不是“设定条目仓库”，而是供后续 AI 写作者调用的文学素材库。写入素材时，应让另一个 AI 在阅读后能够直接感知人物、场面、情绪和叙事张力，而不是只得到抽象标签。

### 基本原则

- **文学性优先于资料性**：素材可以有结构，但不能只剩设定表。要保留画面、气味、动作、语气、心理暗流与叙事节奏。
- **具体优先于概括**：不要只写“他很冷漠”，要写他如何冷漠：他说话是否短促，眼神是否回避，是否习惯用行动代替解释。
- **可写性优先于炫设定**：任何设定都应服务于章节、场景、冲突、人物选择或情绪变化。
- **冲突优先于静态信息**：优秀素材应暗含矛盾：欲望与恐惧、亲近与防备、规则与例外、表面身份与真实动机。
- **语言要有质感**：避免过度模板化、网文梗堆砌和空泛形容词。允许简洁，但要准确、有画面、有情绪温度。
- **来源必须可追溯**：YAML 中必须填写 `source`。原创写 `原创`；来自作品、案例、片段、风格模仿或拆解时，尽量写成 `作者名《作品名》` 或至少写作品名；不确定则写 `未知`，不要留空。

### YAML 基础模板

```yaml
---
name: 素材名称
description: 一句话说明这个素材的用途、内容或价值。
source: 原创 / 作者名《作品名》 / 作品名 / 未知
tag:
  - 大类
  - 具体类型
  - 功能或情绪
---
```

`source` 用于记录素材出自的作品或来源，方便后续 AI 判断语境、风格、版权边界和可迁移方式。

### 每条素材应尽量回答

- 这个素材可以放进什么样的故事段落？
- 它制造什么情绪：压迫、暧昧、悲壮、轻松、诡异、爽快，还是失落？
- 它推动什么：人物关系、主线冲突、伏笔、世界认知、爽点释放，还是性格揭示？
- 它最有文学价值的细节是什么：一句话、一个动作、一个沉默、一个场景意象，还是一次选择？
- 如果另一个 AI 要扩写它，应该抓住哪种语气和节奏？

### 禁止写成这样

```markdown
主角很强，很冷静，很聪明。这里可以打脸敌人，读者会很爽。
```

这类描述过于抽象，缺少文学可用性。

### 推荐写成这样

```markdown
他没有立刻反驳，只把碎裂的茶盏扶正，指腹沾着血，却像是在擦去桌上一点无关紧要的灰。等众人的笑声落下，他才抬眼，说：“你们刚才押的是我的命，还是自己的？”

这一桥段适合先抑后扬式打脸。爽点不来自吼叫，而来自克制后的反击；人物性格应呈现为冷静、记仇、善于等对方把话说死。
```

### 面向 AI 的写作提示

素材正文应尽量提供“可复现的写法线索”：

- **叙事视角**：适合第一人称、第三人称近景、群像旁观，还是反派视角？
- **语言风格**：冷峻、华丽、克制、口语、古典、诡异、热血、讽刺？
- **节奏建议**：慢慢压迫、快速爆发、先静后动、连续反转、留白收束？
- **意象建议**：雨、雪、灯火、刀痕、香气、尘土、月光、旧物、伤口等可反复使用的文学意象。
- **可扩写钩子**：一句台词、一个动作、一个误会、一个未说出口的念头。

## Source

`D:\agent_workspace\capability-library\skill-library\novel-writing\modules\material-library.md`

## Command List

- `open`
- `show`
- `search`
- `info`

## Full Command Reference

### `open`

打印素材图书馆模块讨论文件路径。

```powershell
mycli novel-writing material-library open
```

用途：快速定位原始模块说明文件。

---

### `show`

显示素材图书馆模块讨论笔记内容。

```powershell
mycli novel-writing material-library show
```

用途：查看素材图书馆模块的设计讨论与背景说明。

---

### `search`

搜索素材图书馆中的正式 `.md` 素材文件。

```powershell
mycli novel-writing material-library search [text...] [--text <text>] [--tag <tag>] [--source <source>] [--work <work>] [--source-contains <text>] [--category <category>] [--limit <n>] [--json]
```

参数：

- `[text...]`：裸文本粗搜。会在素材 `name`、`description`、`source`、分类、相对路径和正文中搜索。
- `--text <text>`：显式文字粗搜。可重复使用；多个文字条件为 AND。
- `--tag <tag>`：精确 tag 过滤。可重复使用；多个 tag 为 AND。
- `--source <source>`：精确 source 过滤。适合查 `原创` 或完整来源，如 `作者名《作品名》`。
- `--work <work>`：作品/source 粗搜；等价于 source 包含搜索。适合只知道作品名的一部分。
- `--source-contains <text>`：source 包含搜索，比 `--source` 更宽松。
- `--category <category>`：精确一级分类过滤，例如 `人物设定`、`场景`、`文学风格收集`。
- `--limit <n>`：限制结果数量。默认 `20`；`0` 表示全部结果。
- `--json`：输出 JSON，便于脚本或其他 AI 继续处理。

示例：

```powershell
mycli novel-writing material-library search 打脸
mycli novel-writing material-library search --text 语言风格
mycli novel-writing material-library search --tag 人物设定 --tag 反派
mycli novel-writing material-library search --source 原创
mycli novel-writing material-library search --work 红楼梦
mycli novel-writing material-library search --category 文学风格收集 --tag 冷峻
mycli novel-writing material-library search --tag 场景 --limit 50
mycli novel-writing material-library search --tag 人物设定 --json
```

检索语义：

- `--tag`、`--source`、`--category` 是精确过滤。
- 裸文本、`--text`、`--work`、`--source-contains` 是粗搜。
- 精确过滤和粗搜可以组合使用。
- 多个过滤条件默认是 AND。

---

### `info`

查看素材库当前已有的分类、source 和 tag，便于后续进行精确检索。

```powershell
mycli novel-writing material-library info [--section categories|sources|tags|tags-by-category|sources-by-category] [--category <category>] [--json]
```

参数：

- `--section categories`：只显示已有一级分类及数量。
- `--section sources`：只显示已有 `source` 及数量。
- `--section tags`：只显示已有 tag 及数量。
- `--section tags-by-category`：按一级分类显示 tag。
- `--section sources-by-category`：按一级分类显示 source。
- `--category <category>`：只统计某个一级分类下的信息。
- `--json`：输出 JSON。

示例：

```powershell
mycli novel-writing material-library info
mycli novel-writing material-library info --section categories
mycli novel-writing material-library info --section sources
mycli novel-writing material-library info --section tags
mycli novel-writing material-library info --section tags-by-category
mycli novel-writing material-library info --section sources-by-category
mycli novel-writing material-library info --category 人物设定 --section tags
mycli novel-writing material-library info --json
```

推荐检索流程：

```powershell
mycli novel-writing material-library info --section tags-by-category
mycli novel-writing material-library info --section sources
mycli novel-writing material-library search --tag <精确tag> --source <精确source>
```

## Usage Examples

```powershell
mycli novel-writing material-library open
mycli novel-writing material-library show
mycli novel-writing material-library search 打脸
mycli novel-writing material-library search 信任 --tag 情感线推进
mycli novel-writing material-library search --category 场景 --tag 战斗场景 --json
mycli novel-writing material-library search --source 原创 --tag 人物设定
mycli novel-writing material-library search --work 红楼梦 --text 语言风格
mycli novel-writing material-library info --section tags-by-category
```

## Material Search

`search` 会递归搜索本素材图书馆中的正式 `.md` 素材文件，默认跳过各目录说明文件与 `TAG-GUIDE.md`。

检索逻辑分为两层：

1. **精确过滤**：`--tag`、`--source`、`--category` 用归一化后的精确匹配，适合已经知道素材库内有哪些 tag/source/category 时使用。
2. **文字粗搜**：裸关键词或 `--text` 会在 `name`、`description`、`source`、一级分类、相对路径和正文中做粗略检索，并按匹配位置打分排序。

搜索范围包括：

- YAML `name`
- YAML `description`
- YAML `source`
- YAML `tag`
- 一级分类目录名
- 相对路径
- Markdown 正文

## Current Material Categories

- 场景
- 爽点
- 伏笔
- 人物设定
- 力量体系
- 世界设定
- 完整故事概要
- 灵活记录
- 情感线推进
- 文学风格收集

用法：

```powershell
mycli novel-writing material-library search [text...] [--text <text>] [--tag <tag>] [--source <source>] [--work <work>] [--category <category>] [--limit <n>] [--json]
```

说明：

- 裸关键词和 `--text` 都是文字粗搜；多个文字条件是 AND 条件。
- 多个 `--tag` 是 AND 条件，且是精确 tag 匹配。
- `--source` 是精确 source 匹配，例如 `--source 原创`。
- `--work` 是作品/source 包含搜索，适合只知道作品名的一部分，例如 `--work 红楼梦`。
- `--category` 是一级分类目录精确匹配，例如 `--category 人物设定`。
- `--limit` 默认 `20`，传 `0` 表示全部结果。
- `--json` 输出结构化结果，便于后续脚本消费。

## Material Info

`info` 用于查看素材库当前已有的可精确检索值，类似素材库内部的检索帮助。

用法：

```powershell
mycli novel-writing material-library info [--section categories|sources|tags|tags-by-category|sources-by-category] [--category <category>] [--json]
```

示例：

```powershell
mycli novel-writing material-library info
mycli novel-writing material-library info --section sources
mycli novel-writing material-library info --section tags-by-category
mycli novel-writing material-library info --category 人物设定 --section tags
mycli novel-writing material-library info --json
```

建议流程：

1. 先用 `info --section tags-by-category` 查看某类素材已有 tag。
2. 再用 `search --tag <精确tag>` 进行精确过滤。
3. 如果只记得作品来源，用 `info --section sources` 或 `search --work <作品名>`。
4. 如果不确定 tag/source，用裸关键词或 `--text` 粗搜。
