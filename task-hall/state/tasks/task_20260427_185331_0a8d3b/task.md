# GitHub 热点仓库长期报告项目：完整周期性抓取演练 Builder 子任务

## 背景
上级任务 `task_20260427_185115_3f8a39` 要求对长期项目 `github-hot-repos-report` 做一次完整周期性抓取演练：脚本抓取 -> 候选生成 -> 人工复核/整理 -> 正式报告。此前已验证通过 Clash mixed port `http://127.0.0.1:7890` 设置 `HTTP_PROXY/HTTPS_PROXY` 后，无 token 脚本可抓取 GitHub Trending。

## 目标
在项目真实运行路径下完成一次日度候选抓取，并基于本次候选数据人工复核/整理生成正式周期性报告。

## 项目路径或上下文
- project-manager id: `github-hot-repos-report`
- 项目目录：`D:\agent_workspace\projects\github-hot-repos-report`
- 关键脚本：`scripts\fetch_trending_no_token.py`
- 代理：`HTTP_PROXY=http://127.0.0.1:7890`、`HTTPS_PROXY=http://127.0.0.1:7890`
- 推荐运行命令参考：

```powershell
$env:HTTP_PROXY="http://127.0.0.1:7890"; $env:HTTPS_PROXY="http://127.0.0.1:7890"; python .\scripts\fetch_trending_no_token.py --since daily --limit 10 --json-out .\state\candidates\daily-latest.json --md-out .\state\candidates\daily-latest.md --log-file .\state\logs\trending-fetch.log
```

## 任务范围
1. 开始前检查本任务 task-link 状态和任务目录已有产物，避免重复施工。
2. 在项目目录实际运行抓取脚本，带 Clash 代理环境变量。
3. 生成/刷新：
   - `state\candidates\daily-latest.json`
   - `state\candidates\daily-latest.md`
   - `state\logs\trending-fetch.log`
4. 阅读候选 JSON/Markdown，进行人工复核与整理。
5. 生成正式报告：`reports\2026-04-27-periodic-github-hot-repos.md`。
6. 报告至少包含 10 个仓库，并明确：来源、抓取时间、代理方式、无 token 边界、候选文件路径、限制/风险。
7. 提交 task-link report，说明命令、结果、产物路径与限制。

## 明确不做什么
- 不使用 GitHub token、密钥、Cookie 或登录态。
- 不克隆大型仓库。
- 不部署外部服务。
- 不 push、不发外部消息。
- 不注册真正的长期系统计划任务；本次只是演练。
- 不修改无关项目文件。

## 交付物
- `D:\agent_workspace\projects\github-hot-repos-report\state\candidates\daily-latest.json`
- `D:\agent_workspace\projects\github-hot-repos-report\state\candidates\daily-latest.md`
- `D:\agent_workspace\projects\github-hot-repos-report\state\logs\trending-fetch.log`
- `D:\agent_workspace\projects\github-hot-repos-report\reports\2026-04-27-periodic-github-hot-repos.md`
- task-link report。

## 验收标准
- 脚本通过 Clash 代理实际运行成功；如失败，必须保留清晰日志并说明失败原因和替代处理。
- 候选 JSON/Markdown 存在且为本次刷新。
- 正式报告不是样例占位，且基于本次候选输出和人工复核整理。
- 正式报告至少包含 10 个仓库。
- 明确记录代理方式、无 token 边界、候选文件路径与限制。

## 推荐 agent 类型
`middle-builder`

## 汇报方式
完成后使用：

```powershell
mycli task-hall task-link report <task-id> <report.md> <executor-agent> <session-id>
```

## 状态对齐要求
开始前必须检查任务目录已有 report、task-link-report、handoff、plan 或半成品，并结合 `mycli task-hall task-link show <task-id>` 判断真实进展，避免重复施工。

## heartbeat 说明
heartbeat/recover 只是兜底，不是正常交付方式。正常交付必须通过 task-link report 汇报。
