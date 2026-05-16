# 子任务：五万字玄幻小说整体设定与章节规划

## 背景

父任务 `task_20260427_204238_2c1cfd` 要求在 `D:\agent_workspace\projects\xuanhuan-novel-workflow` 交付一部约五万字、结构完整、可直接阅读的原创中文玄幻小说，并附 README/创作说明。前任 `opencode/middle-builder` 已提交 blocked 报告，明确没有产出小说正文、世界观、人物设定、章节大纲或 README。本任务是工程部 Leader 拆出的第一阶段 watched 子任务，用于为后续正文写作提供统一创作蓝本。

## 目标

产出原创中文玄幻小说的完整创作蓝本，包含书名、简介、主题基调、世界观、修炼体系、主要人物、主要势力、核心冲突、完整章节大纲和写作连续性约束，供后续子任务按同一设定写作约五万字正文。

## 项目路径或上下文

- 父任务 ID：`task_20260427_204238_2c1cfd`
- 父任务目录：`D:\agent_workspace\capability-library\mycli\task-hall\state\tasks\task_20260427_204238_2c1cfd`
- 目标项目目录：`D:\agent_workspace\projects\xuanhuan-novel-workflow`
- 建议产物目录：`D:\agent_workspace\projects\xuanhuan-novel-workflow\deliverables\task_20260427_204238_2c1cfd`
- 本阶段建议产物：`planning.md`

## 任务范围

请完成：

1. 书名和 200-400 字简介。
2. 世界观设定：天地规则、地理格局、历史背景、核心奇观或独特设定。
3. 修炼体系：境界名、每个境界能力边界、突破代价或限制。
4. 主要人物设定：主角、2-4 名重要配角、主要反派；包含动机、弧光、关系。
5. 主要势力和核心冲突。
6. 18-24 章章节大纲：每章给出标题、剧情功能、关键事件、人物变化、悬念/承接。
7. 写作一致性表：人名、地名、境界名、道具名、禁用/慎用事项。
8. 分批写作建议：将正文分成 3-4 个连续批次，每批约 12k-18k 中文字，并标明每批覆盖章节。

## 明确不做什么

- 不要求在本任务写完整五万字正文。
- 不要改写或借用已有知名小说、影视、游戏、动漫剧情。
- 不要写露骨色情、极端血腥、现实仇恨煽动内容。
- 不要只给泛泛模板；必须给后续写作者可直接执行的细节。

## 交付物

- `D:\agent_workspace\projects\xuanhuan-novel-workflow\deliverables\task_20260427_204238_2c1cfd\planning.md`
- 任务报告，说明规划产物路径、章节数量、预计全文字数、是否可供后续正文写作。

## 验收标准

- 规划文件完整覆盖书名、简介、世界观、人物、势力、修炼体系、章节大纲。
- 章节大纲不少于 18 章，不多于 24 章，并形成完整开端、发展、高潮、结局。
- 设定具有原创组合，不明显照搬已有作品。
- 后续正文写作 agent 可仅凭该规划继续写作，不需要重新发明主线。
- 报告包含产物路径、完成项、自检结果和未完成项。

## 推荐 agent 类型

`middle-builder`（本任务以文档创作为主，不涉及代码构建；需要较强长文规划能力）。

## 汇报方式

完成后通过：

```powershell
mycli task-hall task-link report <本子任务ID> <report.md> opencode/middle-builder <session-id>
```

提交结构化报告。不要只在对话里回复。

## 状态对齐要求

开始前必须检查：

- 本子任务的任务目录与 task-link 状态；
- 目标目录 `D:\agent_workspace\projects\xuanhuan-novel-workflow\deliverables\task_20260427_204238_2c1cfd` 是否已有 `planning.md` 或同类产物；
- 父任务目录是否已有更新报告。

如果已存在可复用产物，请接续完善，不要重复生成冲突版本。

## heartbeat 说明

heartbeat/recover 只是兜底，不是正常交付方式。正常完成、部分完成或受阻时，都必须使用 `task-link report` 汇报。
