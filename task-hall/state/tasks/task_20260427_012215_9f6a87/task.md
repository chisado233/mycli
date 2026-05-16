# 玄幻小说工作流真实链路验证：世界观与升级体系实跑

## 背景

工程部正在将 `xuanhuan-novel-workflow` 从 prototype 推进到经过真实多 agent 链路验证的可复用工作流。本任务是首轮真实 builder 验证之一，用于验证 B 阶段“世界与规则底盘”是否能通过 task-hall/task-link 产出可用资产。

项目路径：`D:\agent_workspace\projects\xuanhuan-novel-workflow`

示例小说项目路径：`D:\agent_workspace\projects\xuanhuan-novel-workflow\example-project`

重要参考：

- `D:\agent_workspace\projects\xuanhuan-novel-workflow\README.md`
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\workflow\design.md`
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\workflow\top-agent.md`
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\templates\task-worldbuilding.md`
- 已有 canon：`example-project\canon\story-brief.md`、`style-guide.md`、`cast-ledger.md`

## 目标

基于已有 story brief / style guide / cast ledger，真实执行一次世界观与升级体系任务，产出可支撑后续章节 brief 和正文写作的最小可用 canon 资产。

## 任务说明

请在任务范围内完成：

1. 阅读上述项目文档和已有 canon。
2. 生成或补齐：
   - `example-project\canon\world-bible.md`
   - `example-project\canon\power-system.md`
   - `example-project\canon\factions.md`
   - `example-project\canon\terminology-glossary.md`
3. 保持“东方玄幻升级流、底层少年逆势崛起、突破有代价、不随意开无代价外挂”的读者承诺。
4. 明确标注世界规则、境界层级、升级资源、势力冲突、术语表。
5. 写一份自检报告，说明这些资产如何满足工作流 B 阶段质量门槛，以及是否发现需 leader 决策的问题。

## 范围与约束

- 可以修改 `example-project\canon\` 下本任务列出的四个文件。
- 不要修改 `workflow\` 设计文档，不要修改 task-hall / project-manager / mycli 系统文件。
- 不直接写章节正文。
- 若发现已有 canon 冲突，先在报告中列出冲突和建议，不要静默覆盖核心设定。

## 期望产物

- `D:\agent_workspace\projects\xuanhuan-novel-workflow\example-project\canon\world-bible.md`
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\example-project\canon\power-system.md`
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\example-project\canon\factions.md`
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\example-project\canon\terminology-glossary.md`
- 任务报告 Markdown，包含完成内容、验证结果、问题/阻塞、建议下一步。

## 验收标准

- 世界观、升级体系、势力与术语能互相引用且不明显冲突。
- 境界体系层级清晰，至少包含低中高阶段与资源/代价。
- 势力格局能提供首卷冲突来源。
- 产物足以供后续章节 brief / 正文任务读取。
- 报告明确说明是否允许进入章节 brief 与正文实跑。

## 发布模式

watched。执行 agent 完成或受阻时必须通过 task-link report 汇报给 `opencode/engineering-leader`。

## 建议 agent 类型或能力要求

建议 `senior-builder`；需要长篇设定、结构化资产写作和自检能力。

## 领取门槛

复杂度：高

最低模型要求：expert

指定 agent 类型：senior-builder
