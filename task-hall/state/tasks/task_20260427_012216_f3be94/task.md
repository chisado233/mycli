# 玄幻小说工作流真实链路验证：整体架构 QA 与一致性检查

## 背景

工程部需要把 `xuanhuan-novel-workflow` 从 prototype 推进到经过真实多 agent 链路验证的可复用工作流。除内容产物实跑外，还需要独立 QA 检查整体架构、文档、样例项目和 task-hall/task-link 使用方式是否一致。

项目路径：`D:\agent_workspace\projects\xuanhuan-novel-workflow`

重要参考：

- `README.md`
- `workflow\design.md`
- `workflow\top-agent.md`
- `workflow\runbook.md`
- `templates\*.md`
- `example-project\`
- `D:\agent_workspace\capability-library\agent-system-rules\agent-system\工程部\工程部正式设计.md`

## 目标

执行一次整体架构 QA / 一致性检查，找出 prototype 到可复用工作流之间的缺口，并给出下一轮工程任务建议。

## 任务说明

请在任务范围内完成：

1. 阅读项目所有核心文档、模板和 example-project 当前资产结构。
2. 检查以下维度：
   - README / design / top-agent / runbook 是否描述一致。
   - task-hall/task-link 命令示例是否与当前 mycli 命令形态一致。
   - example-project 是否包含 MVP 运行所需目录和占位资产。
   - 工作流阶段 A-H 的输入、输出、验收门是否足够可执行。
   - 是否存在多 agent 并行修改同一 canon 的风险。
   - 缺失的自动化校验、schema、workflow.json 或 runbook 步骤。
3. 输出 QA 报告：`example-project\review\workflow-architecture-qa.md`。
4. 给出优先级排序的后续任务建议，但不要亲自实施修复。

## 范围与约束

- 可以新增/修改 QA 报告文件：`example-project\review\workflow-architecture-qa.md`。
- 不要修改核心 workflow 文档和 canon 资产。
- 不要修改 mycli/task-hall/project-manager 系统文件。
- 不要把未验证项写成已通过。

## 期望产物

- `D:\agent_workspace\projects\xuanhuan-novel-workflow\example-project\review\workflow-architecture-qa.md`
- 任务报告 Markdown，包含 QA 结论、通过项、问题清单、阻塞/风险、建议下一步。

## 验收标准

- QA 报告覆盖整体架构、文档一致性、运行链路、样例项目、风险和后续建议。
- 问题按严重度或优先级排序。
- 报告能帮助 leader 判断项目状态是继续 validation、进入 iteration，还是需补关键能力。

## 发布模式

watched。执行 agent 完成或受阻时必须通过 task-link report 汇报给 `opencode/engineering-leader`。

## 建议 agent 类型或能力要求

建议 `qa`；需要工程流程 QA、文档一致性检查和架构风险识别能力。

## 领取门槛

复杂度：高

最低模型要求：expert

指定 agent 类型：qa
