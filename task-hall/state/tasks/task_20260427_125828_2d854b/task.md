# Builder 子任务：github-hot-repos-report 首份真实热点报告

## 背景
上级任务 `task_20260427_125725_840a21` 要求将 `github-hot-repos-report` 从 prototype 推进到可用状态。本子任务负责“首份真实报告”部分，必须基于公开、无需认证来源整理真实 GitHub 热点仓库，不得使用 token、密钥或登录态。

## 目标
在项目 `D:\agent_workspace\projects\github-hot-repos-report` 的 `reports/` 目录产出首份真实 GitHub 热点仓库报告，建议文件名：`reports/2026-04-27-real-github-hot-repos.md`。

## 项目路径或上下文
- 项目路径：`D:\agent_workspace\projects\github-hot-repos-report`
- 上级任务：`task_20260427_125725_840a21`
- 当前已有样例报告：`reports/2026-04-27-github-hot-repos.md`（明确是占位，不能直接当真实报告）

## 任务范围
1. 开始前检查任务目录、项目目录和 task-link 状态，避免重复施工。
2. 从 GitHub Trending 或等价公开来源实际整理当前热点仓库。
3. 不使用 GitHub token、密钥、Cookie、登录态。
4. 报告至少包含 10 个仓库。
5. 每个仓库至少包含：仓库名、链接、主要语言/技术、简介/热点原因、可见热度指标或说明。
6. 报告必须明确写明采集时间、来源、方式、限制。
7. 若网络或页面结构受限，必须如实说明，并尽最大可能通过公开来源补充；不要伪造“实时抓取”。

## 明确不做什么
- 不修改 task-hall/agent 系统代码。
- 不使用任何凭据或登录态。
- 不克隆大型仓库。
- 不部署外部服务。
- 不负责脚本和调度方案（另有子任务）。

## 交付物
- `D:\agent_workspace\projects\github-hot-repos-report\reports\2026-04-27-real-github-hot-repos.md` 或同等清晰命名的真实报告。
- task-link report 中说明数据来源、采集方式、验证方式、限制。

## 验收标准
- 报告不是样例占位。
- 至少 10 个真实仓库。
- 每个仓库字段齐全。
- 明确来源、采集时间、方式、限制。
- 未使用 token/密钥/登录态。

## 推荐 agent 类型
`middle-builder`

## 汇报方式
完成后通过：

```powershell
mycli task-hall task-link report <本子任务ID> <report.md> opencode/middle-builder <session-id>
```

报告需列出产物路径和验证结果。heartbeat/recover 只是兜底，不是正常交付方式。
