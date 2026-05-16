# GitHub 热点仓库长期报告项目：完整周期性抓取演练

## 背景
项目 `github-hot-repos-report` 已具备：真实报告、无 token 轻量脚本、定期调度方案。刚刚通过 `mycli clash` 验证，设置 `HTTP_PROXY/HTTPS_PROXY=http://127.0.0.1:7890` 后，脚本可以成功抓取 GitHub Trending 并生成 `state/candidates/daily-latest.json` 与 `state/candidates/daily-latest.md`。

用户要求：做一次完整抓取。

本任务要求 engineering-leader 按长期项目的真实运行方式组织一次完整周期性报告演练：脚本抓取 -> 候选生成 -> 人工复核/整理 -> 正式报告 -> project-manager 状态更新 -> task-link 汇报。leader 必须自己判断拆分，并至少发布 watched builder 子任务。

## 项目信息
- project-manager id: `github-hot-repos-report`
- 项目目录：`D:\agent_workspace\projects\github-hot-repos-report`
- 关键脚本：`scripts\fetch_trending_no_token.py`
- 代理方式：通过 Clash mixed port `http://127.0.0.1:7890`，运行时设置 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量。

## 总目标
完成一次完整周期性抓取演练，并产出一份新的正式报告，报告必须基于本次脚本候选输出和人工复核整理，而不是样例占位。

## 必做事项
1. 读取项目状态：
   - `mycli project-manager current github-hot-repos-report`
   - `mycli project-manager agent-guide github-hot-repos-report --phase operations_preparation`
2. 自己判断拆分方式，并发布至少一个 watched builder 子任务。
3. builder 子任务建议目标：
   - 在项目目录运行脚本，带 Clash 代理环境变量：
     - `HTTP_PROXY=http://127.0.0.1:7890`
     - `HTTPS_PROXY=http://127.0.0.1:7890`
   - 生成/刷新：
     - `state\candidates\daily-latest.json`
     - `state\candidates\daily-latest.md`
     - `state\logs\trending-fetch.log`
   - 基于候选数据和人工复核整理，生成新的正式报告到 `reports/`，建议命名：`reports/2026-04-27-periodic-github-hot-repos.md`。
   - 报告至少包含 10 个仓库，明确来源、抓取时间、代理方式、无 token 边界、候选文件路径和限制。
4. leader 必须验收 builder task-link report，必要时 continue 返工。
5. 更新 project-manager：把当前 next action 标记完成或新增下一步长期运行事项。
6. 最后对本任务执行 task-link report。

## 边界
- 不使用 GitHub token、密钥、Cookie 或登录态。
- 不克隆大型仓库。
- 不部署外部服务。
- 不 push、不发外部消息。
- 默认不要注册真正的长期系统计划任务；本次是演练。

## 验收标准
- 脚本通过 Clash 代理实际运行成功，或如失败则有清晰日志和替代说明；本任务目标是尽力完成真实抓取。
- `state/candidates/daily-latest.json` 与 `.md` 存在且本次刷新。
- `reports/` 下有新的正式周期性抓取报告，不是样例占位。
- builder 子任务通过 task-link 闭环。
- project-manager 被更新。
- 本任务通过 task-link report 提交。
