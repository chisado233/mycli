# 玄幻小说写作工作流搭建任务（二次发布）

## 背景

当前工程部系统正在按 `D:\agent_workspace\capability-library\agent-system-rules\agent-system` 下的文档进行校验和增强。task-hall 已具备 `publish-raw`、`task-link`、callback queue、lifecycle tick 等基础能力，并正在加强生命周期维护系统与监控前端。

已有玄幻小说工作流 prototype：

- 项目 ID：`xuanhuan-novel-workflow`
- 项目路径：`D:\agent_workspace\projects\xuanhuan-novel-workflow`
- 设计文档：`D:\agent_workspace\projects\xuanhuan-novel-workflow\workflow\design.md`
- 顶级 agent 提示词：`D:\agent_workspace\projects\xuanhuan-novel-workflow\workflow\top-agent.md`
- 运行手册：`D:\agent_workspace\projects\xuanhuan-novel-workflow\workflow\runbook.md`

## 目标

由工程部 leader 接手并组织 builder/QA，将玄幻小说写作工作流从 prototype 推进为真实可复用、可验证、可通过 task-hall/task-link 多 agent 协作运行的顶级 agent 工作流。

## 任务说明

leader 需要按工程部流程推进，不亲自完成核心施工：

1. 读取 project-manager 当前状态和项目资产。
2. 检查已有工作流是否缺少关键阶段、模板、验收规则、回调/返工流程。
3. 发布 watched builder tasks，至少覆盖：
   - 世界观/升级体系任务实跑；
   - 章节正文写作任务实跑；
   - 审校/返工流程验证；
   - 总体架构和可复用性 QA。
4. builder/QA 完成后通过 `task-link report` 汇报，leader 通过 `task-link complete/continue/switch-agent` 判断和闭环。
5. 更新 project-manager 状态、task、next action 和关键产物路径。
6. 最终输出当前施工进度、已发布任务、等待中的 task-link/callback、下一步计划。

## 推荐命令

```powershell
D:\agent_workspace\capability-library\mycli\mycli.ps1 project-manager agent-guide xuanhuan-novel-workflow
D:\agent_workspace\capability-library\mycli\mycli.ps1 task-hall publish-raw <builder-task.md> custom 80 xuanhuan "..." watched opencode/engineering-leader <leader-session> middle-builder
```

如果 leader 当前 session id 由 lifecycle dispatch 生成，请优先使用该 session id 作为子任务 `publisher_session`。

## 交付物

- builder/QA watched task id 列表；
- 每个任务的 required_agent_type 和目标；
- project-manager 更新结果；
- task-link / callback queue 当前状态；
- 需要继续等待或恢复的事项。

## 验收标准

- 本任务必须通过任务大厅和生命周期维护系统分配给 `opencode/engineering-leader`；
- leader 必须通过 task-hall 发布至少 3 个 watched 子任务；
- 不得绕过工程部流程直接由当前 assistant 完成核心施工；
- 后续能通过生命周期维护系统继续推进。

## 领取门槛

复杂度：高

最低模型要求：expert

指定 agent 类型：engineering-leader
