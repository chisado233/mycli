# GitHub 热点仓库长期摘取整理报告：项目骨架与首期报告施工

## 背景
上级 task-hall 任务 `task_20260427_124029_cdeffd` 要求将一次性的 GitHub 热点抓取升级为长期项目。engineering-leader 已读取 project-manager 状态，当前项目处于 planning / draft，需要 builder 在项目目录内完成第一版可维护骨架与首期报告方案。

## 目标
在 `D:\agent_workspace\projects\github-hot-repos-report` 内完成第一版“GitHub 热点仓库长期摘取整理报告”项目骨架，使后续可以无 token、手动或定时生成 Markdown 热点报告，并至少产出一份首期/样例报告。

## 项目路径或上下文
- 项目目录：`D:\agent_workspace\projects\github-hot-repos-report`
- project-manager id：`github-hot-repos-report`
- 上级任务：`task_20260427_124029_cdeffd`
- 当前已有目录：`README.md`、`reports/`、`scripts/`、`state/`、`.agent-project/`

## 任务范围
请在项目目录内完成以下施工：
1. 更新/补全根目录 `README.md`，说明项目目标、目录结构、无 token 数据来源策略、基本运行流程。
2. 新增或更新根目录 `runbook.md`，包含：
   - 手动运行步骤；
   - 建议的定期运行方式（例如 Windows Task Scheduler / cron 思路即可，不要求实际注册计划任务）；
   - GitHub Trending 或等价公开来源的限制；
   - 明确“不使用 GitHub token、密钥、登录”；
   - 失败/空结果/网络受限时如何处理。
3. 补全 `reports/`：
   - `reports/README.md`：报告命名规范、字段说明、归档规则；
   - 报告模板（可为 `reports/template.md` 或在 README 中完整说明）；
   - 一份首期或样例报告，建议命名为 `reports/2026-04-27-github-hot-repos.md`，内容可基于公开 GitHub Trending 页面或明确标注为样例/人工整理占位，不能伪造为已验证实时抓取结果。
4. `scripts/` 下可选但推荐提供轻量脚本或说明文件：
   - 如果写脚本，必须不依赖 token，失败时输出可理解错误；
   - 如果不写脚本，需在 `scripts/README.md` 说明人工/半自动流程。
5. 如需记录运行状态，可在 `state/README.md` 说明该目录用途；不要写入密钥或外部凭证。

## 明确不做什么
- 不使用 GitHub token、密钥、登录态或私有 API。
- 不克隆大型仓库。
- 不部署外部服务。
- 不 push、不发外部消息。
- 不实现复杂长期爬虫守护进程；第一版以可维护、可手动/定时调用为准。
- 不修改 `D:\agent_workspace` 下无关项目或 task-hall 系统代码。

## 交付物
- `D:\agent_workspace\projects\github-hot-repos-report\README.md`
- `D:\agent_workspace\projects\github-hot-repos-report\runbook.md`
- `D:\agent_workspace\projects\github-hot-repos-report\reports\README.md`
- 报告模板或模板说明
- 至少一份首期/样例报告
- 可选：`scripts/` 轻量脚本或 `scripts/README.md`
- 可选：`state/README.md`

## 验收标准
- 项目目录有可读的长期运行说明，能让后续 agent/人工理解如何继续产出报告。
- `reports/` 有明确命名规范、报告字段和首期/样例报告。
- 无 token 策略、公开来源限制、失败处理被明确记录。
- 没有引入密钥、登录态、外部部署或大型克隆。
- 如提供脚本，至少做一次基本运行/语法检查；如无法联网或无法验证，需在报告中如实说明。

## 推荐 agent 类型
`middle-builder`

## 汇报方式
完成或受阻后，必须通过 task-link report 汇报本子任务。报告包含：完成内容、产物路径、验证命令/结果、未完成项、问题阻塞、建议下一步。

## 状态对齐要求
开始前必须先检查本子任务目录是否已有 report、task-link-report、handoff、plan 或半成品，并查看 task-link 状态；如已有有效产物，避免重复施工，基于现状继续。

## heartbeat 说明
heartbeat/recover 只是兜底，不是正常交付方式。正常完成、部分完成或受阻均应主动提交 task-link report。
