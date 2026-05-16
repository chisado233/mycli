# GitHub 项目本地部署跑通工程任务

## 背景
这是工程部生命周期系统的真实行为监控任务。目标不是部署到公网，而是选择一个安全、轻量、公开的 GitHub 项目，把它克隆到本地临时目录，安装依赖，跑通本地启动/测试/构建中的至少一个可验证路径，并记录完整过程。

## 目标
验证工程部 leader -> builder/QA 的 task-hall 工作链路是否能处理“GitHub 项目部署跑通”类工程任务。

## 推荐项目
优先使用一个轻量公开项目，例如：
- https://github.com/vitejs/vite/tree/main/packages/create-vite/template-vanilla
- 或者直接用 npm create vite@latest 创建一个 vanilla 项目作为等价 GitHub 生态部署烟测。

如果选择其他公开 GitHub 项目，必须说明原因，项目必须轻量、安全、无需密钥、无需外部服务账号。

## 工作范围
- 在 `D:\agent_workspace\tmp\github-deploy-smoke\` 下创建/克隆/初始化项目。
- 安装依赖。
- 尝试运行本地构建或测试；如果适合，也可短暂启动本地 dev server 并用命令验证端口响应。
- 记录遇到的问题和解决过程。
- 发布必要的 watched 子任务给 senior-builder/middle-builder/qa，leader 不应亲自做核心施工。

## 不做范围
- 不部署公网。
- 不 push 到任何远端。
- 不使用密钥、token、云服务账号。
- 不修改 workspace 全局配置。
- 不删除用户已有项目。

## 交付物
- `D:\agent_workspace\tmp\github-deploy-smoke\` 下的项目/产物。
- 安装、构建、运行或验证记录。
- 如果有子任务，所有子任务都必须通过 task-link report 汇报。
- leader 最终通过 task-link report 汇总。

## 验收标准
- 能说明选择了哪个 GitHub/生态项目。
- 能说明执行了哪些命令。
- 至少一个验证路径成功，或清晰说明为何无法成功以及已尝试步骤。
- 所有执行 agent 都通过 task-link report 交付。
- leader 对下游 report 进行 complete/continue/switch-agent 判断。

## 推荐 agent 类型
engineering-leader

## 汇报方式
必须使用 `mycli task-hall task-link report`；最终聊天回复不能替代任务提交。
