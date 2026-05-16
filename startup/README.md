# mycli startup

`mycli startup` 管理“开机启动命令注册表”。所有注册并启用的命令都会在当前 Windows 用户登录时由一个计划任务统一启动。

## Usage

```powershell
mycli startup --help
mycli startup commands [--json]
mycli startup add <id> <command...>
mycli startup remove <id>
mycli startup enable <id>
mycli startup disable <id>
mycli startup install
mycli startup uninstall
mycli startup run
mycli startup status [--json]
mycli startup ui
mycli startup ui-open
mycli startup ui-stop
mycli startup ui-status
mycli startup native <args...>
```

注意：`mycli startup list` 是 mycli 的包级内置命令清单；要查看已注册的开机启动命令，请使用 `mycli startup commands` 或 `mycli startup native list`。

## How it works

- 注册表文件：`D:\agent_workspace\capability-library\mycli\startup\state\startup-commands.json`
- 日志目录：`D:\agent_workspace\capability-library\mycli\startup\state\logs\`
- Windows 计划任务名：`\mycli\startup\RunRegisteredCommands`
- `add` 会写入注册表并自动 `install` 计划任务。
- `run` 会按注册顺序启动所有 `enabled=true` 的命令；每条命令异步启动，输出写入日志文件。

## Command details

- `commands [--json]` — 查看已注册启动命令；这是查看 registry 的主命令。
- `add <id> <command...>` — 注册命令，并自动安装或更新 Windows 计划任务。
- `enable <id>` / `disable <id>` — 启用或禁用某条命令但保留记录。
- `remove <id>` — 从 registry 删除命令。
- `install` / `uninstall` — 安装或移除统一的 Windows Task Scheduler 计划任务。
- `run` — 立即按登录启动逻辑运行所有 enabled 命令。
- `status [--json]` — 查看 registry 和计划任务状态。
- `ui` / `ui-open` / `ui-stop` / `ui-status` — 管理本地 Startup Commands UI。

## Startup Commands UI

`startup` 提供本地 UI，用于查看开机启动命令、启用/禁用/移除命令、安装/更新统一计划任务，以及手动运行所有 enabled 启动项：

```powershell
mycli startup ui
mycli startup ui-open
mycli startup ui-status
mycli startup ui-stop
```

默认地址：

```text
http://127.0.0.1:46020
```

该 UI 通过 `.agent-ui.json` 接入 `mycli workspace-ui`。

## Examples

注册一个命令：

```powershell
mycli startup add task-hall-recover mycli task-hall lifecycle-wake --reason startup-recover --cwd D:\agent_workspace
```

查看已注册命令：

```powershell
mycli startup commands
```

立即模拟开机启动执行：

```powershell
mycli startup run
```

禁用但保留记录：

```powershell
mycli startup disable task-hall-recover
```

删除记录：

```powershell
mycli startup remove task-hall-recover
```

## Notes

- 这里的“开机启动”使用 Windows Task Scheduler 的当前用户 `AtLogOn` 触发器。
- 请只注册幂等、可重复启动的命令；避免注册会阻塞很久的前台交互命令。
- 命令会异步启动，输出写入日志；排查时先看 `state\logs\`。
- 涉及部署、删除、推送、外部消息发送、远程执行等高风险命令时，必须先取得用户明确授权。
