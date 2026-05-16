# novel-writing writing

## Summary

小说写作流程中的中间资产工作区。这里的动态资产库不同于素材图书馆：它管理的是写作过程中产生的人物、势力、区间状态、当前快照、状态变更日志和新增对象收件箱。

## Command List

- `asset-lib`

## Writing Agents

阶段 agent 位于：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\writing\agents
```

常用企划阶段 agent：

- `01-作品企划-agent.md`：从零发散多个作品企划方向，负责选题、卖点、题材创新、初始主方案候选。
- `01b-作品企划编辑-agent.md`：专门编辑已有作品企划，负责按千束反馈把旧稿/候选稿整理成简洁、可入库的正式企划。
- `02-世界观-agent.md`：根据已入库作品企划从零生成世界观候选稿。
- `02b-世界观编辑-agent.md`：专门编辑已有世界观候选稿，负责按千束反馈压缩冗余、修冲突、补缺口，并整理成可入库世界观版本。

推荐流程：

1. 用 `01-作品企划-agent.md` 生成多个方向或初稿。
2. 千束反馈/拍板后，用 `01b-作品企划编辑-agent.md` 把旧稿、候选稿和反馈整合为编辑稿；默认只传作品企划模板，不需要传 `00-通用写作流程规则.md`。
3. 人审通过后，再把编辑稿合并/覆盖到 `assets/planning/00-作品企划.md`。
4. 正式企划通过后，进入世界观、势力、人物和大纲阶段。

世界观阶段推荐流程：

1. 用 `02-世界观-agent.md` 根据正式企划生成世界观候选稿。
2. 千束反馈/拍板后，用 `02b-世界观编辑-agent.md` 编辑候选稿；默认只传正式企划、世界观候选稿和 `02_世界观` 模板，不需要传 `00-通用写作流程规则.md`。
3. 人审通过后，再把编辑稿拆分/合并到 `assets/worldview/`。

`01b-作品企划编辑-agent.md` 的典型用途：

- 将 `tmp/` 中的企划候选整理成正式稿。
- 根据千束反馈修改 `assets/planning/00-作品企划.md`。
- 合并多个企划候选，收敛成一个主方案。
- 按 `writing/templates/写作模板/01_作品企划/00-作品企划总表.md` 的字段输出，避免冗余扩写。

`02b-世界观编辑-agent.md` 的典型用途：

- 将 `tmp/` 中的世界观候选整理成正式稿。
- 根据千束反馈修改世界观规则、地图、力量体系、资源体系。
- 压缩过长世界观设定，保留真正能服务冲突、升级和章节推进的内容。
- 按 `writing/templates/写作模板/02_世界观/` 的字段输出，避免写成设定百科。

## Command Details

### asset-lib

管理写作过程动态资产库，并支持按章节/人物/势力/状态检索，以及把章节写作需要的上下文合成为一个 Markdown 文件。

默认资产库根目录：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\writing\asset-libraries
```

支持多个子库，每个子库通常对应一本小说、一个实验项目或一个版本分支。

子库现在纳入写作流程中的主要中间资产：

- 作品企划：`assets/planning/`
- 世界观：`assets/worldview/`
- 人物：`assets/characters/`
- 势力：`assets/factions/`
- 故事粗纲：`outlines/rough/`
- 情感线粗纲：`outlines/emotion/`
- 卷纲：`outlines/volume/`
- 小篇章纲：`outlines/arc/`
- 五章纲：`outlines/five-chapter/`
- 单章节细纲：`outlines/chapter-detail/`
- 章节正文：`drafts/chapters/`
- 动态状态：`states/`
- 当前快照：`snapshots/`
- 状态日志：`logs/`
- 新增对象收件箱：`inbox/`
- 临时中间产物：`tmp/`

#### 初始化子库

```powershell
mycli novel-writing writing asset-lib init --lib my-novel
```

可指定根目录：

```powershell
mycli novel-writing writing asset-lib init --root D:\path\asset-libraries --lib my-novel
```

#### 列出子库

```powershell
mycli novel-writing writing asset-lib libs
```

#### 查看子库信息

```powershell
mycli novel-writing writing asset-lib info --lib my-novel
```

#### 搜索资产

```powershell
mycli novel-writing writing asset-lib search --lib my-novel --query 苏清雪
mycli novel-writing writing asset-lib search --lib my-novel --kind character --query 圣女
mycli novel-writing writing asset-lib search --lib my-novel --kind faction --query 天剑宗
mycli novel-writing writing asset-lib search --lib my-novel --chapter 6
mycli novel-writing writing asset-lib search --lib my-novel --from 5 --to 7 --kind state
mycli novel-writing writing asset-lib search --lib my-novel --kind planning
mycli novel-writing writing asset-lib search --lib my-novel --kind worldview
mycli novel-writing writing asset-lib search --lib my-novel --kind volume-outline --query 第1卷
```

#### 生成索引

```powershell
mycli novel-writing writing asset-lib index --lib my-novel
```

#### 合成章节上下文 Markdown

```powershell
mycli novel-writing writing asset-lib compose --lib my-novel --chapter 6 --query 苏清雪 --query 天剑宗
```

默认输出到：

```text
<lib>\composed-context\context-时间戳.md
```

也可以指定输出路径：

```powershell
mycli novel-writing writing asset-lib compose --lib my-novel --chapter 6 --query 苏清雪 --out D:\tmp\chapter-006-context.md
```

#### 一键生成章节上下文

```powershell
mycli novel-writing writing asset-lib chapter-context --lib my-novel --chapter 6 --query 苏清雪 --query 天剑宗
```

#### 打印子库路径

```powershell
mycli novel-writing writing asset-lib path --lib my-novel
```
