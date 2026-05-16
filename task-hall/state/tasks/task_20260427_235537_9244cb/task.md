# 子任务：五万字玄幻小说最终整合、README 与验收自检

## 背景

父任务 `task_20260427_204238_2c1cfd` 要求最终交付一份可直接阅读的完整原创中文玄幻小说 `novel.md`，以及 README/创作说明。前置子任务会产生 `planning.md` 与 `drafts\part-01.md`、`part-02.md`、`part-03.md`。本任务负责整合、轻量一致性修订、README 编写和验收报告。

## 目标

将前置规划和分批正文整合为最终可阅读的 `novel.md`，编写 `README.md`，并进行字数、章节、连续性和收束自检。

## 项目路径或上下文

- 父任务 ID：`task_20260427_204238_2c1cfd`
- 统一交付目录：`D:\agent_workspace\projects\xuanhuan-novel-workflow\deliverables\task_20260427_204238_2c1cfd`
- 前置文件：`planning.md`、`drafts\part-01.md`、`drafts\part-02.md`、`drafts\part-03.md`
- 最终产物：`novel.md`、`README.md`

## 任务范围

请完成：

1. 检查前置文件是否存在且可读；若缺失，报告 blocked，不要伪造完成。
2. 合并正文分批文件，去掉分批连续性备注中不应进入正文的部分，保留章节标题。
3. 在 `novel.md` 前部加入书名、简介、世界观设定、主要人物设定、章节目录，然后放完整正文。
4. 轻量修订明显错别字、重复标题、章节断裂、人名/地名/境界名不一致；不要大幅重写导致新矛盾。
5. 编写 `README.md`，包含书名、总字数估算、章节列表、世界观与主线概述、产物路径、自检结果。
6. 估算正文总字数；若明显低于 40,000 中文字，应在报告中标记不满足父任务验收，并建议继续补写。
7. 输出结构化任务报告。

## 明确不做什么

- 不要在前置正文严重缺失时伪造“已完成”。
- 不要改变父任务目标目录。
- 不要删除草稿文件。
- 不要执行代码构建；这是文档/创作整合任务。

## 交付物

- `D:\agent_workspace\projects\xuanhuan-novel-workflow\deliverables\task_20260427_204238_2c1cfd\novel.md`
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\deliverables\task_20260427_204238_2c1cfd\README.md`
- 任务报告，包含产物路径、字数估算、章节数量、自检结果、未完成项。

## 验收标准

- `novel.md` 可直接阅读，包含书名、简介、设定、人物、章节目录、完整正文和结尾。
- 正文总字数接近父任务要求，合理目标为 45,000-55,000 中文字；若不达标必须如实报告。
- 主线有开端、发展、高潮、结局，核心冲突解决。
- README 信息完整，产物路径明确。
- 报告不隐瞒问题。

## 推荐 agent 类型

`qa`

## 汇报方式

完成后通过：

```powershell
mycli task-hall task-link report <本子任务ID> <report.md> opencode/engineering-qa <session-id>
```

提交结构化报告。

## 状态对齐要求

开始前检查任务目录已有产物和 task-link 状态，避免重复整合。如果 `novel.md` 已存在，应先验证其是否来自本父任务和是否满足验收，再决定修订或报告。

## heartbeat 说明

heartbeat/recover 只是兜底，不是正常交付方式。正常完成、部分完成或受阻时，都必须使用 `task-link report` 汇报。
