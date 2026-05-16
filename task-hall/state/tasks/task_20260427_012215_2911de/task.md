# 玄幻小说工作流真实链路验证：章节 brief 与正文草稿实跑

## 背景

工程部正在验证 `xuanhuan-novel-workflow` 是否能通过真实 task-hall/task-link 多 agent 链路产出可复用写作工作流。本任务验证 E/F 阶段：从已批准或当前可用 canon 生成章节 brief，并基于 brief 产出单章正文草稿。

项目路径：`D:\agent_workspace\projects\xuanhuan-novel-workflow`

示例小说项目路径：`D:\agent_workspace\projects\xuanhuan-novel-workflow\example-project`

重要参考：

- `D:\agent_workspace\projects\xuanhuan-novel-workflow\workflow\design.md` 的阶段 E/F 与模板 10.4/10.5
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\workflow\runbook.md`
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\templates\task-chapter-draft.md`
- `example-project\canon\` 下已有 canon 资产

## 目标

真实执行一次“章节 brief → 正文草稿”链路，产出可供审校/返工任务检查的最小样章资产。

## 任务说明

请在任务范围内完成：

1. 阅读项目工作流文档与 `example-project\canon\` 下可用资产。
2. 如世界观/升级体系资产尚不完整，不要等待其他任务；请基于已有 canon 和待定占位显式列出假设，产出“验证用”章节 brief 和草稿，报告中说明依赖风险。
3. 创建首章 brief：`example-project\chapter-briefs\chapter-001.md`，至少包含本章目标、开场状态、结尾状态、关键场景、冲突点、爽点、章尾钩子、伏笔、canon 约束清单。
4. 基于该 brief 创建正文草稿：`example-project\drafts\chapters\chapter-001-draft.md`，并附 self-check notes。
5. 不直接修改 canon；若需要 canon delta，在报告中列为建议，留给 canon 更新任务。

## 范围与约束

- 可以新增/修改：
  - `example-project\chapter-briefs\chapter-001.md`
  - `example-project\drafts\chapters\chapter-001-draft.md`
- 不要修改 `example-project\canon\` 下核心资产。
- 不要修改 workflow 设计文档、mycli、task-hall、project-manager。
- 正文应遵守已有风格与读者承诺，避免无代价外挂。

## 期望产物

- `D:\agent_workspace\projects\xuanhuan-novel-workflow\example-project\chapter-briefs\chapter-001.md`
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\example-project\drafts\chapters\chapter-001-draft.md`
- 任务报告 Markdown，说明使用了哪些 canon、做了哪些假设、自检结果、是否建议进入 review。

## 验收标准

- brief 结构完整，能直接指导正文写作。
- 草稿与 brief 一致，具备明确推进价值和章尾钩子。
- 草稿不越权修改 canon，不引入无法解释的战力/世界规则。
- 报告列明待审校的风险点和建议下一步。

## 发布模式

watched。执行 agent 完成或受阻时必须通过 task-link report 汇报给 `opencode/engineering-leader`。

## 建议 agent 类型或能力要求

建议 `middle-builder`；需要中文网文章节设计与正文草稿能力，并能遵守 canon 边界。

## 领取门槛

复杂度：中高

最低模型要求：strong

指定 agent 类型：middle-builder
