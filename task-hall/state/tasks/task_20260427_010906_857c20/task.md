# 工程部 Leader 接手玄幻小说工作流项目

## 背景

工程部体系、task-hall/task-link 基础链路、5 个 builder 池，以及玄幻小说顶级 agent 工作流 prototype 已经建立。现在需要按正确工程部流程，由生命周期维持系统从任务大厅领取本任务并分配给 engineering-leader，由 leader 继续发布 watched tasks 给 builder 推进项目。

项目路径：`D:\agent_workspace\projects\xuanhuan-novel-workflow`

重要参考：

- `D:\agent_workspace\projects\xuanhuan-novel-workflow\README.md`
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\workflow\design.md`
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\workflow\top-agent.md`
- `D:\agent_workspace\projects\xuanhuan-novel-workflow\workflow\runbook.md`
- `D:\agent_workspace\capability-library\agent-system-rules\agent-system\工程部\工程部正式设计.md`

## 目标

由 `opencode/engineering-leader` 正式接手 `xuanhuan-novel-workflow` 项目，把它从 prototype 推进到经过真实工程部多 agent 链路验证的可复用工作流。

## 任务说明

leader 需要：

1. 读取 project-manager 当前状态和项目文件。
2. 判断还缺哪些关键产物或验证。
3. 发布 watched tasks 给 builder 池，至少覆盖：
   - 世界观/升级体系任务实跑；
   - 章节正文任务实跑；
   - 审校/返工流程检查；
   - 整体架构 QA 或一致性检查。
4. 每个 builder 任务通过 `mycli task-hall publish-raw` 发布，默认 watched。
5. builder 汇报后，通过 task-link 判断 complete / continue / switch-agent。
6. 更新 project-manager 状态、任务和 next action。
7. 不亲自写核心产物，只调度、验收和整合。

## 推荐流程

```powershell
D:\agent_workspace\capability-library\mycli\mycli.ps1 project-manager agent-guide xuanhuan-novel-workflow
D:\agent_workspace\capability-library\mycli\mycli.ps1 task-hall publish-raw <builder-task.md> custom 80 xuanhuan "..." watched opencode/engineering-leader <leader-session> middle-builder
```

如果当前 leader session id 不清楚，先发布任务并在任务说明中写清由本 leader 接收回调；后续 callback queue / lifecycle 会兜底。

## 交付物

- 已发布的 builder task id 列表；
- 每个任务的目标和 assigned agent type；
- project-manager 更新结果；
- 当前等待的 task-link / callback 状态；
- 如有无法继续的阻塞，说明原因。

## 验收标准

- leader 不直接完成核心施工，而是通过 task-hall 发布任务给 builder；
- 至少发布 3 个 watched builder/QA 任务；
- project-manager 状态被更新；
- 后续推进可以通过 lifecycle tick / callback queue 恢复。

## 领取门槛

复杂度：高

最低模型要求：expert

指定 agent 类型：engineering-leader
