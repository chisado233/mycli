# 子任务：五万字玄幻小说正文第三批写作与结局收束

## 背景

父任务 `task_20260427_204238_2c1cfd` 要求交付约五万字完整原创中文玄幻小说。本任务负责正文后段和结局，承接 `planning.md`、`drafts\part-01.md`、`drafts\part-02.md`，完成高潮、核心冲突解决和结尾收束。

## 目标

写作小说正文第三批，建议覆盖第 14-20/24 章或规划中最后一批对应章节，产出约 16,000-22,000 中文字的连续正文，使全书具备完整结局。

## 项目路径或上下文

- 父任务 ID：`task_20260427_204238_2c1cfd`
- 统一交付目录：`D:\agent_workspace\projects\xuanhuan-novel-workflow\deliverables\task_20260427_204238_2c1cfd`
- 必读文件：`planning.md`、`drafts\part-01.md`、`drafts\part-02.md`
- 建议产物：`drafts\part-03.md`

## 任务范围

请完成：

1. 阅读前置规划和前两批正文，梳理未解决伏笔、人物状态、反派目标、终局条件。
2. 写作正文第三批：危机爆发、终局对抗、主角关键选择、核心冲突解决、主要人物结局。
3. 结尾必须收束父任务要求的主线，不能停在未完待续。
4. 文末附“全书收束备注”：已解决冲突、保留的非关键余味、供整合者检查的事项。
5. 保存到 `drafts\part-03.md`。

## 明确不做什么

- 不要留下主线未完成或明显断尾。
- 不要推翻前两批正文既成事实。
- 不要只写大纲、摘要或结局说明。
- 不要依赖续集才能解释核心冲突。

## 交付物

- `D:\agent_workspace\projects\xuanhuan-novel-workflow\deliverables\task_20260427_204238_2c1cfd\drafts\part-03.md`
- 任务报告，包含字数估算、覆盖章节、产物路径、自检结果和收束情况。

## 验收标准

- 正文约 16,000-22,000 中文字。
- 能自然承接 `part-02.md`，完成高潮和结局。
- 主角成长线闭环，核心冲突有明确解决。
- 人名、地名、境界名与前文基本一致。
- 报告明确说明结局是否收束、是否存在关键未完成项。

## 推荐 agent 类型

`middle-builder`

## 汇报方式

完成后通过：

```powershell
mycli task-hall task-link report <本子任务ID> <report.md> opencode/middle-builder <session-id>
```

提交结构化报告。

## 状态对齐要求

开始前检查任务目录、task-link 状态、规划和前两批正文是否存在。若前置产物缺失，应报告 blocked 或只做可安全接续的部分，不要凭空覆盖主线。

## heartbeat 说明

heartbeat/recover 只是兜底，不是正常交付方式。正常完成、部分完成或受阻时，都必须使用 `task-link report` 汇报。
