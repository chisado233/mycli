# mycli

`mycli` 是 `D:\agent_workspace\capability-library` 的统一命令入口。

它把本地能力包、脚本、外部 CLI、agent、workflow、配置、代理、远程电脑和长期任务管理组织成一套 **可发现、可说明、可执行** 的命令体系。

## 快速使用

```powershell
mycli --help
mycli list
mycli <package> --help
mycli <package> list
mycli <package> <command> [args...]
```

如果 `mycli` 不在 PATH 中，使用完整入口：

```powershell
D:\agent_workspace\capability-library\mycli\mycli.ps1 --help
D:\agent_workspace\capability-library\mycli\mycli.ps1 list
```

## 核心模型

- 目录表示 package 树。
- 每个 package 的命令注册在 `cli.package.json`。
- 每个 package 的 `--help` 内容来自同目录 `README.md`。
- 命令通过注册的绝对路径 `entry` 执行，可用 `prefixArgs` 包装原生命令。
- 统一入口不够时，优先使用该包提供的 `native` 命令透传到底层 CLI。

## 能力地图

| 需求 | 优先入口 |
|---|---|
| 调用 agent / 直接调模型 / 生成图片 | `mycli agent-cli ...` |
| 编排多步骤、可等待、可审核流程 | `mycli agent-workflow ...` |
| 搜索和注册本地 skills | `mycli skill-library ...` |
| 从 ClawHub 搜索、检查、安装、发布 skills | `mycli clawhub ...` |
| 查询 workspace JSON 配置 | `mycli config-cli ...` |
| 注册和管理一次性/持久定时命令或脚本 | `mycli cron ...` |
| GitHub 仓库、issue、PR、Actions 与 API 操作 | `mycli github ...` |
| 管理长期项目状态、任务和 next actions | `mycli project-manager ...` |
| 查询/创建 workspace 标准 runtime/data/config/cache/logs 路径与打开统一 UI | `mycli workspace ...` |
| 控制 Clash 代理、测速、切换节点 | `mycli clash ...` |
| 远程电脑 / WireGuard / 中转命令 | `mycli remote-pc ...` |
| 外部消息通道与 bridge | `mycli channels ...` |
| 本地素材 / 表情包路径与发送 | `mycli asset-library ...` |
| Windows 登录启动命令 | `mycli startup ...` |
| CLIProxyAPI 本地服务 | `mycli cliproxyapi ...` |
| Codex 账号注册与 CPA 配套 | `mycli codex-register ...` |

## 顶层包

```powershell
mycli list
```

当前常见顶层包：

- `agent-cli` — 统一本地 agent provider，支持 run、session replay、schedule、mount、llm-call、native。
- `agent-workflow` — 初始化、生成、校验、运行多步骤 workflow 工程。
- `asset-library` — 管理本地素材资源，目前以 meme / sticker 为主。
- `channels` — 外部消息入口和 agent bridge 容器包，如 `chat-soft`、`QQ`。
- `clash` — 本地 Clash for Windows 和 REST controller 包装。
- `clawhub` — npm `clawhub` 包装，用于搜索、检查、安装、同步和发布 OpenClaw skills。
- `cliproxyapi` — 管理本地 CLIProxyAPI Go server、config、keys、startup、logs、tests。
- `codex-register` — 管理 codex-register 项目、CPA 上传配置和 auth quota 检查。
- `config-cli` — 自动发现并描述 `D:\agent_workspace\config` 下的 JSON 配置。
- `cron` — 注册和管理一次性/持久 Windows Task Scheduler 定时命令或脚本任务。
- `github` — 官方 GitHub CLI (`gh`) 包装，支持 repo、issue、PR、Actions、search、api 与 auth。
- `novel-writing` — 小说写作 skill 的工作入口和拆书初始化入口。
- `project-manager` — 持久项目注册、查询、状态、任务和上下文管理。
- `remote-pc` — 基于 WireGuard 的 remote PC bridge control commands。
- `skill-library` — 本地 skill 索引、搜索、注册。
- `startup` — 当前 Windows 用户登录时自动运行的 mycli commands。
- `workspace` — 管理 `D:\agent_workspace` 标准 runtime/data/config/cache/logs/ui 路径、命名空间目录与统一 UI 总控台 / launcher（`mycli workspace ui ...`）。

## 常用流程

### 发现能力

```powershell
mycli list
mycli agent-cli --help
mycli agent-cli list
mycli skill-library skills
mycli skill-library search opencode
```

### 单次 agent 调用

```powershell
mycli agent-cli agents
mycli agent-cli run --agent opencode/private-assistant --cwd D:\agent_workspace --prompt "review this repo" --return_mode silent
mycli agent-cli session events --session <session-id> --last 1
```

### 直接模型调用 / 图片生成

```powershell
mycli agent-cli llm-call --list-models
mycli agent-cli llm-call --model MoreCode/gpt-5.4 --prompt "hello"
mycli agent-cli llm-call --model MoreCode/gpt-image-2 --task image-generate --prompt "一只可爱的白色小猫，水彩风格" --size 1024x1024
```

### 多步骤 workflow

```powershell
mycli agent-workflow init D:\agent_workspace\projects\my-flow --workflow-id my_flow --name "My Flow"
mycli agent-workflow scaffold D:\agent_workspace\projects\my-flow
mycli agent-workflow validate D:\agent_workspace\projects\my-flow
mycli agent-workflow start-run D:\agent_workspace\projects\my-flow
```

### 本地 skill 检索与注册

```powershell
mycli skill-library skills
mycli skill-library search novel
mycli skill-library register
mycli skill-library register D:\agent_workspace\capability-library\skill-library\some-skill
```

### 项目状态管理

```powershell
mycli project-manager query --mode ongoing
mycli project-manager current <id-or-name>
mycli project-manager agent-guide <id-or-name> --phase validation
mycli project-manager task-add <id-or-name> --title "Run validation" --type validate --set-current
```

### Clash 代理控制

```powershell
mycli clash status
mycli clash selectors
mycli clash country-use TapFog 日本
mycli clash auto-start TapFog 日本 60 4000
mycli clash auto-stop
```

### 远程电脑桥接

```powershell
mycli remote-pc wg-status
mycli remote-pc status B
mycli remote-pc connect B
mycli remote-pc run B "hostname"
mycli remote-pc relay-run "Get-Location"
```

### Windows 登录启动项

```powershell
mycli startup commands
mycli startup add task-hall-recover mycli task-hall lifecycle-wake --reason startup-recover --cwd D:\agent_workspace
mycli startup status
```

### Workspace-config 路径治理

```powershell
mycli workspace ensure-package channels/QQ
mycli workspace config-path mycli channels/QQ
mycli workspace config mycli channels/QQ --json
mycli workspace ui open
```

每个包、项目、skill、agent 默认都应有自动生成的 `workspace-config.json`，用于记录 `tmp/var/logs/cache/config/data/downloads/backups/ui` 等路径。以 mycli 包为例：

```text
D:\agent_workspace\config\mycli\<package-path>\workspace-config.json
```

mycli 包脚本撰写规则：不要把中间产物、日志、下载物、状态、缓存、真实配置或有效数据路径写死在源码包目录中；脚本应读取对应 `workspace-config.json` 的 `paths` 字段，并把产物写入相应 workspace 位置。

## 包与命令维护

修改 `mycli` 运行时或包注册前，先读：

```text
D:\agent_workspace\capability-library\mycli\common\technical-manual.md
```

常用维护命令：

```powershell
mycli package list
mycli package register <package/path> --summary <text> --source <text>
mycli package register-full <package/path> --summary <text> --source <text> --commands <json> --help <markdown>
mycli <package> command list
mycli <package> command register <name> --summary <text> --entry <absolute-path> --args <json> [--prefix-args <json>]
mycli <package> command update <name> [--summary <text>] [--entry <absolute-path>] [--args <json>] [--prefix-args <json>]
mycli <package> help update --content <markdown>
```

新增或重整包的 workspace-aware 流程：

1. 注册子包：创建包目录、`cli.package.json`、`README.md`。
2. 生成 workspace 目录：`mycli workspace ensure-package <package-path>`。
3. 生成/确认 workspace-config：`mycli workspace config mycli <package-path> --json`。
4. 撰写脚本：从 workspace-config 读取路径，不写死 tmp/logs/downloads/config/data 等产物路径。
5. 注册命令并更新 README。
6. 验证 `--help`、`list`、代表性只读命令，并确认产物写入 workspace 对应位置。

维护约束：

- `entry` 必须是绝对路径。
- `cli.package.json` 是注册契约。
- `README.md` 是包级 help 来源。
- 参数元数据尽量保持结构化。
- `registry.json` 一类索引文件通常应通过命令刷新，不要手工编辑作为主方案。

## 安全边界

- 只读查询通常可以直接执行。
- 外部通信、远程执行、代理切换、开机启动、账号登录/发布、删除/卸载、写入凭据等动作必须先确认用户意图。
- 不打印 API key、token、WireGuard 私钥、Clash secret、Management API key 等敏感信息。
- 长期运行或后台任务必须能通过对应包的 `status/list/logs/cancel/stop` 命令检查和停止。

## Docs

- 用户手册：`D:\agent_workspace\capability-library\mycli\common\user-manual.md`
- 维护与技术手册：`D:\agent_workspace\capability-library\mycli\common\technical-manual.md`
