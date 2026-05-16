# GitHub/Vite 本地部署烟测执行子任务

## 背景
父任务 `task_20260427_113401_32f8b3` 要验证工程部 leader -> builder/QA 的 task-hall 工作链路能否处理“GitHub 项目部署跑通”类工程任务。工程部 Leader 只负责统筹，不亲自做核心施工，因此将本地部署烟测交由 builder 执行。

## 目标
在 `D:\agent_workspace\tmp\github-deploy-smoke\` 下创建一个安全、轻量、无需密钥的 GitHub 生态项目，安装依赖，并跑通至少一个可验证路径（优先 `npm run build`；如合适可短暂启动 dev server 并验证端口响应）。

## 项目路径或上下文
- 父任务 ID：`task_20260427_113401_32f8b3`
- 父任务目录：`D:\agent_workspace\capability-library\mycli\task-hall\state\tasks\task_20260427_113401_32f8b3`
- 工作目录：`D:\agent_workspace\tmp\github-deploy-smoke\`
- 推荐项目：优先使用 `npm create vite@latest` 创建 vanilla 项目，或使用 Vite 官方 vanilla 模板等价完成 GitHub 生态部署烟测。

## 任务范围
1. 开始前检查本子任务目录已有产物、`task-link show` 状态，以及 `D:\agent_workspace\tmp\github-deploy-smoke\` 是否已存在半成品，避免重复施工；若已有可复用产物，先记录再决定是否继续。
2. 在 `D:\agent_workspace\tmp\github-deploy-smoke\` 下初始化/创建项目。
3. 安装依赖。
4. 运行本地构建或测试中的至少一个可验证路径；推荐 `npm run build`。
5. 如适合，短暂启动本地 dev server，并用命令验证本地端口响应；验证后必须停止服务进程。
6. 记录完整命令、结果、遇到的问题和解决过程。
7. 写出执行记录/报告文件到 `D:\agent_workspace\tmp\github-deploy-smoke\` 下，并通过 task-link report 汇报。

## 明确不做什么
- 不部署公网。
- 不 push 到任何远端。
- 不使用密钥、token、云服务账号。
- 不修改 workspace 全局配置。
- 不删除用户已有项目；如目标目录已存在内容，先判断并记录，避免破坏性操作。

## 交付物
- `D:\agent_workspace\tmp\github-deploy-smoke\` 下的项目/产物。
- 安装、构建、运行或验证记录 Markdown（建议：`D:\agent_workspace\tmp\github-deploy-smoke\deployment-smoke-report.md`）。
- 通过 `mycli task-hall task-link report <本任务ID> <report.md> opencode/middle-builder <session-id>` 提交的 task-link report。

## 验收标准
- 明确说明选择了哪个 GitHub/生态项目，以及选择原因（轻量、安全、无需密钥、无需外部账号）。
- 明确列出执行过的命令。
- 至少一个验证路径成功（例如 build 成功），或清晰说明为何无法成功以及已尝试步骤。
- 若启动 dev server，必须说明验证端口响应的方法和停止服务的方式。
- 不越界修改无关文件。

## 推荐 agent 类型
middle-builder

## 汇报方式
- 必须使用 `task-link report` 汇报，聊天回复不能替代正式提交。
- 汇报 Markdown 至少包含：状态、完成内容、产物路径、验证结果、未完成项、问题或阻塞、建议下一步。
- heartbeat/recover 只是兜底，不是正常交付方式；正常完成后应主动 task-link report。
