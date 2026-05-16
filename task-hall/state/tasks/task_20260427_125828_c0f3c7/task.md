# Builder 子任务：github-hot-repos-report 无 token 脚本与调度方案

## 背景
上级任务 `task_20260427_125725_840a21` 要求将 `github-hot-repos-report` 从 prototype 推进到可用状态。本子任务负责补齐无 token 轻量脚本与定期调度方案。

## 目标
在项目 `D:\agent_workspace\projects\github-hot-repos-report` 中提供一个无需 token 的轻量辅助脚本，并更新运行说明/调度方案，使项目具备可手动运行、可定期执行、可失败兜底的操作路径。

## 项目路径或上下文
- 项目路径：`D:\agent_workspace\projects\github-hot-repos-report`
- 上级任务：`task_20260427_125725_840a21`
- 当前已有：`README.md`、`runbook.md`、`scripts/README.md`、`reports/template.md` 等骨架。

## 任务范围
1. 开始前检查任务目录、项目目录和 task-link 状态，避免重复施工。
2. 在 `scripts/` 下新增一个轻量脚本或最小可运行辅助工具，优先 PowerShell 或 Python。
3. 脚本不得依赖 token、密钥、Cookie、登录态。
4. 脚本可抓取 GitHub Trending 公开页面并输出候选 Markdown/JSON；若页面结构限制导致无法稳定解析，脚本必须给出清晰错误和人工流程提示。
5. 更新 `scripts/README.md`、`runbook.md` 或新增 `schedule-plan.md`，说明如何运行脚本。
6. 调度方案需说明建议频率、运行步骤、失败处理、日志位置、人工复核环节。
7. 默认不要注册 Windows Task Scheduler，只提供方案；如认为必须注册，先在报告中说明理由，不要擅自创建长期系统任务。
8. 至少做一次基本运行/语法/帮助验证，并在报告中记录命令与结果。

## 明确不做什么
- 不负责首份真实热点报告内容（另有子任务），但脚本可生成候选数据。
- 不使用任何凭据或登录态。
- 不部署外部服务。
- 不 push、不发外部消息。
- 不修改 task-hall/agent 系统代码。

## 交付物
- `D:\agent_workspace\projects\github-hot-repos-report\scripts\...` 下的无 token 轻量脚本。
- `D:\agent_workspace\projects\github-hot-repos-report\scripts\README.md` 或 `runbook.md` 的运行说明更新。
- `D:\agent_workspace\projects\github-hot-repos-report\schedule-plan.md` 或 `runbook.md` 中的定期调度方案。
- task-link report 中记录验证命令和结果。

## 验收标准
- 脚本可在无 token 条件下运行帮助/语法/基本抓取或明确失败。
- README/runbook 说明清楚运行方法和人工兜底。
- 调度方案覆盖频率、步骤、失败处理、日志、人工复核。
- 未创建长期系统任务，除非报告中有充分理由且边界安全。

## 推荐 agent 类型
`middle-builder`

## 汇报方式
完成后通过：

```powershell
mycli task-hall task-link report <本子任务ID> <report.md> opencode/middle-builder <session-id>
```

报告需列出产物路径和验证结果。heartbeat/recover 只是兜底，不是正常交付方式。
