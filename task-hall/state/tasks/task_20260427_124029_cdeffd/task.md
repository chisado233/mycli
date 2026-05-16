# GitHub 热点仓库长期摘取整理报告项目：Leader 规划与施工指挥

## 背景
用户希望把一次性的 GitHub 热点抓取，升级为一个长期项目：持续摘取 GitHub 热点仓库、整理结构化报告、保留历史结果，并由 engineering-leader 自己判断如何拆任务、指挥 builder 干活。

这是工程部生命周期系统的真实任务测试：leader 不能只自己写完所有东西；必须先理解项目目标，再自行拆解 watched 子任务给合适 builder，并通过 task-link 管理子任务完成、返工或交接。

## 项目信息
- project-manager id: `github-hot-repos-report`
- 项目目录：`D:\agent_workspace\projects\github-hot-repos-report`
- 项目类型：ongoing research / automation

## 总目标
建立第一版“GitHub 热点仓库长期摘取整理报告”项目骨架和运行流程，使后续可以定期生成热点报告。

## Leader 工作要求
1. 先读取并理解 project-manager 项目状态：
   - `mycli project-manager current github-hot-repos-report`
   - `mycli project-manager agent-guide github-hot-repos-report`
2. 自己判断如何拆分任务，但至少应考虑：
   - 抓取/采集方案：GitHub Trending 或等价公开来源；不使用 token。
   - 报告格式：Markdown 模板、字段、历史报告命名规范。
   - 项目骨架：README、runbook、reports、scripts、state 等。
   - 第一版验证：生成一份样例/首期报告，或说明如何运行生成。
3. 必须通过 task-hall 发布 watched 子任务给 builder，不要只在自己 session 内完成全部施工。
4. 子任务完成后，必须根据 builder 的 task-link report 判断：
   - complete：验收通过
   - continue：需要返工
   - switch-agent：需要换 agent
   - cancel：任务不再需要
5. 子任务全部处理完后，leader 必须更新 project-manager 状态/任务/next-action，并对本上级任务执行 `mycli task-hall task-link report`。

## Builder 子任务建议
Leader 可自行调整，但建议至少发布一个 builder 子任务，要求 builder 在项目目录内完成：
- `runbook.md`：长期运行说明，包括手动运行、定期运行建议、数据来源限制、无 token 策略。
- `reports/README.md` 或报告模板。
- 可选 `scripts/` 下轻量脚本或说明文件，用于获取/整理热点数据；若不写脚本，也要写明人工/半自动流程。
- 生成或迁移一份首期报告到 `reports/`。

## 边界
- 不使用 GitHub token、密钥或登录。
- 不克隆大型仓库。
- 不部署外部服务。
- 不 push、不发外部消息。
- 不做复杂长期爬虫守护进程；第一版以可维护、可手动/定时调用为准。

## 交付物
- 项目目录内的长期报告项目骨架与说明。
- 至少一个 builder watched 子任务及其 task-link 处理记录。
- project-manager 状态更新记录。
- 本任务 task-link report。

## 验收标准
- Leader 明确体现“拆任务并指挥 builder”而不是独自完成全部施工。
- 项目目录有可读的长期运行说明。
- 有 reports 目录和报告模板/首期报告方案。
- 子任务通过 task-link 闭环。
- 本任务最终通过 task-link report 提交。
