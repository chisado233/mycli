# agent-workflow

## Summary

`agent-workflow` 是对 `D:\agent_workspace\capability-library\agent-system-rules\agent-workflow` 的 `mycli` 包装入口。

它提供一个面向“复杂但相对固定流程任务”的工作流框架，适合下面这类场景：

- 流程步骤基本固定，但每步职责明确
- 一部分步骤是脚本、命令或固定逻辑
- 一部分步骤需要调用 agent 执行灵活任务
- 流程中存在人工审核、事件等待、条件跳转或受控回跳
- 需要把输入、输出、状态、事件流和产物都持久化下来

通过 `mycli agent-workflow ...`，你可以直接初始化、生成、校验、运行和调试 workflow 工程，而不必手动记忆 Python 入口路径。

## Source

- 能力目录：`D:\agent_workspace\capability-library\agent-system-rules\agent-workflow`
- PowerShell 入口：`D:\agent_workspace\capability-library\agent-system-rules\agent-workflow\scripts\agent-workflow.ps1`
- Python 主实现：`D:\agent_workspace\capability-library\agent-system-rules\agent-workflow\src\agent_workflow_scaffold.py`

## 适用场景

这个能力适合：

- 初始化新的 workflow 项目骨架
- 根据 `workflow.json` 批量生成 step 目录
- 校验流程定义是否合法
- 导出流程图快照
- 启动一次 workflow run
- 给 listener 节点注入事件
- 查看某次 run 的运行状态
- 对等待审核的节点执行 approve / reject
- 单独准备某个 step 的 debug 目录

如果你要做的是“长期运行、带状态、可等待外部事件、可人工审核”的 agent 流程，这个包比单纯调用 `agent-cli run` 更合适。

## Commands

### `mycli agent-workflow init`

创建一个新的 workflow 工程目录。

常见参数模式：

```powershell
mycli agent-workflow init <target_dir> --workflow-id <id> [--name <display-name>]
```

### `mycli agent-workflow scaffold`

根据 `workflow.json` 生成 step 目录、README、fixture、tests 和 `.generated` 产物。

```powershell
mycli agent-workflow scaffold <project_dir>
```

### `mycli agent-workflow validate`

校验 `workflow.json` 以及当前工程骨架是否完整。

```powershell
mycli agent-workflow validate <project_dir>
```

### `mycli agent-workflow graph`

导出流程图快照。

```powershell
mycli agent-workflow graph <project_dir>
```

### `mycli agent-workflow debug-step`

为单个 step 准备隔离调试目录，便于单节点排查。

```powershell
mycli agent-workflow debug-step <project_dir> <step_id>
```

### `mycli agent-workflow start-run`

启动一次 workflow run，并可附带输入/上下文 JSON。

```powershell
mycli agent-workflow start-run <project_dir> [--input-json <path>] [--context-json <path>]
```

### `mycli agent-workflow inject-event`

向 listener 节点注入事件，驱动等待中的流程继续执行。

```powershell
mycli agent-workflow inject-event <project_dir> <run_id> <step_id> --event-json <path>
mycli agent-workflow inject-event <project_dir> <run_id> <step_id> --event-text "hello"
```

### `mycli agent-workflow status`

读取某次 workflow run 的当前状态。

```powershell
mycli agent-workflow status <project_dir> <run_id>
```

### `mycli agent-workflow review-step`

对等待审核的 step 执行批准或驳回。

```powershell
mycli agent-workflow review-step <project_dir> <run_id> <target> --decision approve
mycli agent-workflow review-step <project_dir> <run_id> <target> --decision reject --reason "need revision"
```

## 常用工作流

### 1. 初始化一个新项目

```powershell
mycli agent-workflow init D:\agent_workspace\projects\my-flow --workflow-id my_flow --name "My Flow"
```

### 2. 根据 `workflow.json` 生成骨架

```powershell
mycli agent-workflow scaffold D:\agent_workspace\projects\my-flow
```

### 3. 校验流程

```powershell
mycli agent-workflow validate D:\agent_workspace\projects\my-flow
```

### 4. 导出流程图

```powershell
mycli agent-workflow graph D:\agent_workspace\projects\my-flow
```

### 5. 运行示例工程

```powershell
mycli agent-workflow start-run D:\agent_workspace\capability-library\agent-system-rules\agent-workflow\examples\script_echo_flow
```

## 工程结构概念

一个典型 workflow 工程通常包含：

- `workflow.json`：唯一事实来源
- `steps/`：每个节点一个目录
- `context/`：上下文定义
- `shared/`：共用资源
- `runtime/`：运行时元数据
- `var/`：运行产物、debug 数据、run 状态
- `.generated/`：自动生成的 manifest / graph

## 状态与产物位置

- `workflow.json` 是流程定义的事实来源。
- `steps/` 存放每个节点的目录、README、fixture、tests 等。
- `runtime/` 存放运行时元数据定义。
- `var/` 存放 run 状态、运行产物和 debug 数据；排查一次 run 时先看这里。
- `.generated/` 存放 scaffold / graph 等生成产物，可通过 `scaffold` / `graph` 再生成。

## 与 agent-cli 的关系

- `agent-workflow` 不是 `agent-cli` 的替代品
- 它是建立在 `agent-cli` 之上的 workflow 层
- 当 workflow 中出现 `agent` 类型节点时，运行时会进一步调用 `mycli agent-cli run`

也就是说：

- `agent-cli` 负责“调用 agent”
- `agent-workflow` 负责“编排多步骤流程并维护状态”

## 注意事项

- 实际执行入口是 `scripts\agent-workflow.ps1`，该脚本再转发到 Python 主实现
- `listener` / `webhook` 类型步骤适合长生命周期、等待事件的流程
- `review-step` 只适用于当前处于等待审核状态的 step
- `start-run` 可能创建或更新 `var/` 下的运行状态；如果运行中断，先用 `status <project_dir> <run_id>` 查看当前状态，不要盲目重跑。
- 短平快的一次性任务不要滥用 workflow；只有需要持久状态、等待、审核或多节点编排时再使用。
- 更完整的设计和使用细节请查看源目录下的 `README.md` 与 `USER_MANUAL.md`
