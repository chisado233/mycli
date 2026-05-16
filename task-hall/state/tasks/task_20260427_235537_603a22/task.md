# 子任务：五万字玄幻小说正文第一批写作

## 背景

父任务 `task_20260427_204238_2c1cfd` 要求交付约五万字完整原创中文玄幻小说。该父任务已由工程部 Leader 拆分为规划、正文分批写作、整合验收等阶段。本任务负责正文第一批写作：承接规划文件，写出小说开端与第一阶段发展，保证可直接并入最终 `novel.md`。

## 目标

基于规划产物写作小说正文第一批，建议覆盖第 1-6 章或规划中第一批对应章节，产出约 12,000-16,000 中文字的连续正文。

## 项目路径或上下文

- 父任务 ID：`task_20260427_204238_2c1cfd`
- 目标项目目录：`D:\agent_workspace\projects\xuanhuan-novel-workflow`
- 统一交付目录：`D:\agent_workspace\projects\xuanhuan-novel-workflow\deliverables\task_20260427_204238_2c1cfd`
- 必须优先读取规划文件：`planning.md`（如果尚不存在，应读取 task-link/父任务状态，必要时报告 blocked，不要凭空写出冲突设定）
- 建议产物：`drafts\part-01.md`

## 任务范围

请完成：

1. 阅读 `planning.md` 中的世界观、人物、境界、章节大纲和写作一致性表。
2. 写作正文第一批：小说开端、主角出场、核心困境、世界观初显、第一阶段冲突引爆。
3. 每章保持章节标题，正文连续，风格统一。
4. 在文末附简短“本批连续性备注”：已使用设定、伏笔、下一批需承接事项。
5. 保存到 `drafts\part-01.md`。

## 明确不做什么

- 不要重写 `planning.md` 的核心设定；如发现严重问题，在报告中说明。
- 不要写全书结局；本批只负责开端和第一阶段发展。
- 不要只给大纲、片段或摘要；必须写正文。
- 不要抄袭已有小说桥段或角色设定。

## 交付物

- `D:\agent_workspace\projects\xuanhuan-novel-workflow\deliverables\task_20260427_204238_2c1cfd\drafts\part-01.md`
- 任务报告，包含字数估算、覆盖章节、产物路径、自检结果。

## 验收标准

- 正文约 12,000-16,000 中文字，至少覆盖规划中的第一批章节。
- 开端清晰，主角目标/困境明确，有阶段性钩子。
- 与 `planning.md` 的人名、地名、境界名、主线方向一致。
- 无明显断章、重复段落、设定自相矛盾。
- 报告说明未完成项；若因规划缺失无法写作，应明确 blocked 原因。

## 推荐 agent 类型

`middle-builder`

## 汇报方式

完成后通过：

```powershell
mycli task-hall task-link report <本子任务ID> <report.md> opencode/middle-builder <session-id>
```

提交结构化报告。

## 状态对齐要求

开始前检查任务目录已有产物和 task-link 状态，避免重复施工。若 `part-01.md` 已存在，应先确认是否需要续写/修订，而不是覆盖。

## heartbeat 说明

heartbeat/recover 只是兜底，不是正常交付方式。正常完成、部分完成或受阻时，都必须使用 `task-link report` 汇报。
