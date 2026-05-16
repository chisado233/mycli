# 子任务：五万字玄幻小说正文第二批写作

## 背景

父任务 `task_20260427_204238_2c1cfd` 要求交付约五万字完整原创中文玄幻小说。本任务负责正文中段写作，承接 `planning.md` 和第一批正文 `drafts\part-01.md`，推进主线发展、人物成长和中段冲突升级。

## 目标

写作小说正文第二批，建议覆盖第 7-13 章或规划中第二批对应章节，产出约 14,000-18,000 中文字的连续正文。

## 项目路径或上下文

- 父任务 ID：`task_20260427_204238_2c1cfd`
- 统一交付目录：`D:\agent_workspace\projects\xuanhuan-novel-workflow\deliverables\task_20260427_204238_2c1cfd`
- 必读文件：`planning.md`、`drafts\part-01.md`
- 建议产物：`drafts\part-02.md`

## 任务范围

请完成：

1. 阅读规划和第一批正文，提取已发生事件、伏笔、人物状态。
2. 写作正文第二批：中段历练、势力冲突扩大、主角能力成长、重要配角关系推进、阶段反转。
3. 保持章节标题与规划一致；如需要微调章节切分，应在备注中说明原因。
4. 文末附“连续性备注”：承接了哪些伏笔、制造了哪些待解决问题、下一批必须接住什么。
5. 保存到 `drafts\part-02.md`。

## 明确不做什么

- 不要推翻第一批正文既成事实。
- 不要提前草率解决终局冲突。
- 不要只写大纲或摘要。
- 不要引入大量无法在五万字内收束的新势力/人物。

## 交付物

- `D:\agent_workspace\projects\xuanhuan-novel-workflow\deliverables\task_20260427_204238_2c1cfd\drafts\part-02.md`
- 任务报告，包含字数估算、覆盖章节、产物路径、自检结果。

## 验收标准

- 正文约 14,000-18,000 中文字。
- 能自然承接 `part-01.md`，没有明显断裂。
- 中段冲突升级明显，主角成长线推进。
- 设定、人名、地名、境界名与规划一致。
- 报告包含自检结果和未完成项说明。

## 推荐 agent 类型

`middle-builder`

## 汇报方式

完成后通过：

```powershell
mycli task-hall task-link report <本子任务ID> <report.md> opencode/middle-builder <session-id>
```

提交结构化报告。

## 状态对齐要求

开始前检查任务目录、task-link 状态、`planning.md`、`part-01.md` 与目标 `part-02.md` 是否已有内容，避免重复施工或覆盖他人成果。

## heartbeat 说明

heartbeat/recover 只是兜底，不是正常交付方式。正常完成、部分完成或受阻时，都必须使用 `task-link report` 汇报。
