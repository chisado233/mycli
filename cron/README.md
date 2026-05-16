# mycli cron

`mycli cron` 用于注册和管理本机 Windows Task Scheduler 定时任务。它是通用命令/脚本定时器，不内置 agent 语义；如果要定时唤起 agent，请把 `mycli agent-cli run ...` 当作普通命令注册进 cron。

## Usage

```powershell
mycli cron --help
mycli cron task-list [--json]
mycli cron add-command <id> (--once <datetime> | --every <delay> | --daily <HH:mm> | --weekly <days> <HH:mm>) [--persistent|--temp] [--missed skip|catch-up] [--random-delay <delay>] -- <command...>
mycli cron add-script <id> (--once <datetime> | --every <delay> | --daily <HH:mm> | --weekly <days> <HH:mm>) [--persistent|--temp] --script <path> [--copy-script] [-- <script args...>]
mycli cron show <id>
mycli cron logs <id> [--last <n>]
mycli cron run <id>
mycli cron enable <id>
mycli cron disable <id>
mycli cron delete <id>
mycli cron status
mycli cron ui
mycli cron ui-open
mycli cron ui-stop
mycli cron ui-status
mycli cron native <args...>
```

## Cron Scheduler UI

`cron` 提供本地任务监控 UI，用于查看任务列表、Task Scheduler 状态、最近运行记录，并执行启用、禁用、立即运行等操作：

```powershell
mycli cron ui
mycli cron ui-open
mycli cron ui-status
mycli cron ui-stop
```

默认地址：

```text
http://127.0.0.1:46010
```

该 UI 通过 `.agent-ui.json` 接入 `mycli workspace-ui`。

## Storage model

命令目录下分为两类任务目录：

```text
D:\agent_workspace\capability-library\mycli\cron\tasks\persistent\<task-id>\
D:\agent_workspace\capability-library\mycli\cron\tasks\temp\<task-id>\
```

每个任务一个文件夹，典型内容：

```text
task.json        # 代表任务的 JSON：命令、输入、脚本位置、schedule、missed policy、Task Scheduler 名称等
scripts\         # 如果任务依赖自建脚本且使用 --copy-script，脚本会复制到这里
runs\            # 每次执行的 stdout/stderr/meta 记录
```

临时任务（`--temp` 或 `--once` 默认）执行后会自动从 Windows Task Scheduler 注销，并把本地 `task.json` 标记为 `completed`；因此不会再触发，但执行记录仍保留在任务文件夹中。

## Schedule forms

- `--once "2026-05-16 18:30"`：一次性任务；默认存入 `tasks\temp`。
- `--every 30m` / `--every 2h`：按固定间隔重复。
- `--daily 09:00`：每天固定时间。
- `--weekly Mon,Wed,Fri 09:00`：每周指定日期固定时间。

`<delay>` 支持 `30s`、`15m`、`2h`、`1d`。

## Missed-run policy

电脑未开机时，Windows 定时任务无法在原时间生效。注册时可设置 missed policy：

- `--missed skip`：默认。错过就跳过，不在开机后补齐。
- `--missed catch-up`：启用 Task Scheduler 的 `StartWhenAvailable`，允许错过后补齐。
- `--random-delay 30m`：给触发器增加随机延迟，避免开机后任务堆在一起立即运行；也会影响正常触发时间。

不推荐大量任务开机立刻补齐；需要补齐时优先配合 `--random-delay` 分散执行。

## Examples

一次性命令：

```powershell
mycli cron add-command remind-once --once "2026-05-16 18:30" -- mycli agent-cli run --agent opencode/private-assistant --prompt "到点汇报状态" --return_mode silent
```

持久每日任务：

```powershell
mycli cron add-command daily-status --daily 09:00 --persistent --missed catch-up --random-delay 30m -- mycli project-manager query --mode ongoing
```

注册脚本任务并把脚本复制进任务目录：

```powershell
mycli cron add-script weekly-maintenance --weekly Sun 03:00 --persistent --script D:\agent_workspace\tmp\maintenance.ps1 --copy-script -- -Verbose
```

查看与管理：

```powershell
mycli cron task-list
mycli cron show daily-status
mycli cron logs daily-status --last 3
mycli cron disable daily-status
mycli cron enable daily-status
mycli cron delete daily-status
```

## Safety notes

- `cron` 会创建 Windows Task Scheduler 任务，任务路径为 `\mycli\cron\`。
- 定时执行删除、发布、push、部署、外部通信、远程执行、写凭据等高风险命令前，必须有明确授权。
- `--missed catch-up` 可能在机器恢复可用后补跑任务；不要给大量重任务同时设置无延迟补齐。
- `delete` 会注销 OS 计划任务并删除本地任务文件夹；如需保留记录，先复制任务目录。
