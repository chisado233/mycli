# GitHub 热点仓库长期报告项目：真实报告、无 token 脚本与定期调度方案

## 背景
项目 `github-hot-repos-report` 已完成 prototype 骨架。用户要求继续推进三件事：

1. 做首份真实报告。
2. 做无 token 轻量脚本。
3. 做定期调度方案。

本任务要求 engineering-leader 继续接手，自己判断拆分，并指挥 builder 施工。leader 不应独自完成所有施工；必须至少发布 watched builder 子任务，并通过 task-link 验收。

## 项目信息
- project-manager id: `github-hot-repos-report`
- 项目目录：`D:\agent_workspace\projects\github-hot-repos-report`
- 当前阶段：prototype -> usable/operations preparation

## 总目标
把 `github-hot-repos-report` 从 prototype 推进到可用状态：能产出首份真实 GitHub 热点报告，有无 token 的轻量辅助脚本，并有清晰的定期调度方案。

## 必做事项

### 1. 首份真实报告
- 从 GitHub Trending 或等价公开来源实际整理当前热点仓库。
- 不使用 GitHub token、密钥、登录态。
- 输出到项目 `reports/` 目录，建议文件名：`reports/2026-04-27-real-github-hot-repos.md` 或类似清晰命名。
- 至少 10 个仓库。
- 每个仓库至少包含：仓库名、链接、主要语言/技术、简介/热点原因、可见热度指标或说明。
- 明确写明采集时间、来源、方式、限制。

### 2. 无 token 轻量脚本
- 在 `scripts/` 下提供一个轻量脚本或最小可运行辅助工具。
- 优先 PowerShell 或 Python，按项目环境自行判断。
- 脚本不得依赖 token、密钥、登录态。
- 脚本可以抓取 GitHub Trending 公开页面并输出候选 Markdown/JSON；如果页面结构限制导致无法稳定解析，脚本也应给出清晰错误和人工流程提示。
- 必须有 README 或 runbook 说明如何运行。
- 至少做一次基本运行/语法/帮助验证，并在报告中记录结果。

### 3. 定期调度方案
- 更新 `runbook.md` 或新增 `schedule-plan.md`。
- 说明建议频率、运行步骤、失败处理、日志位置、人工复核环节。
- 不强制真正注册 Windows Task Scheduler；如 leader 判断适合注册，可先说明并谨慎执行。默认只做方案，不创建长期系统任务，除非理由充分。
- 如涉及未来 agent/lifecycle 接管，要说明如何通过 task-hall 或 project-manager 继续推进。

## Leader 工作要求
1. 先读取项目状态：
   - `mycli project-manager current github-hot-repos-report`
   - `mycli project-manager agent-guide github-hot-repos-report`
2. 自己判断拆分方式，但必须至少发布一个 watched builder 子任务。
3. 需要时可发布多个 builder 子任务，例如：
   - builder A：真实报告
   - builder B：脚本与调度方案
   也可以合并为一个子任务，但要说明理由。
4. 子任务必须通过 task-link report 汇报，leader 必须验收 complete/continue/switch/cancel。
5. 完成后更新 project-manager 状态、任务和 next action。
6. 最后对本任务执行 task-link report。

## 边界
- 不使用 GitHub token、密钥、登录态。
- 不克隆大型仓库。
- 不部署外部服务。
- 不 push、不发外部消息。
- 不改 task-hall/agent 系统代码，除非发现系统 bug 并另行汇报。

## 验收标准
- 有首份真实报告，且不是样例占位。
- 有无 token 轻量脚本或最小辅助工具，并有验证记录。
- 有定期调度方案。
- builder 子任务完成 task-link 闭环。
- project-manager 被更新。
- 本任务通过 task-link report 提交。
