# PowerShell-cli

`PowerShell-cli` 为 `mycli` 提供 detached persistent PowerShell runspace sessions，适合重复执行本地命令、维护长连接变量、以及通过 `plink` 做非交互远程服务器操作。

## Usage

```powershell
mycli PowerShell-cli start [--admin] [--shell pwsh|powershell] [--cwd <path>] [--session <id>] [--idle-timeout-sec <seconds>] [--wait-ready]
mycli PowerShell-cli send <session-id> --text "Get-Location"
mycli PowerShell-cli send <session-id> "Get-Date"
mycli PowerShell-cli read <session-id> [--after <seq>] [--wait-ms <ms>] [--limit <n>] [--raw]
mycli PowerShell-cli status <session-id>
mycli PowerShell-cli sessions
mycli PowerShell-cli stop <session-id>
mycli PowerShell-cli cleanup [--all]
```

注意：`mycli PowerShell-cli list` 是 mycli 框架保留的包命令列表；session 列表命令叫 `sessions`。

## Command details

- `start`：启动后台 broker；默认脱手启动并立刻返回。
- `send`：把文本命令放进 session 队列，由 broker 在持久 runspace 中执行。
- `read`：从 `events.jsonl` 读取增量输出。
- `status`：查看 session 元数据和计数器。
- `sessions`：列出已知 sessions。
- `stop`：停止某个 broker。
- `cleanup`：不带 `--all` 时只修正 stale 元数据；带 `--all` 时停止仍存活的 sessions。

## Repeated remote server operation pattern

远程服务器操作优先在持久 session 内使用 `plink`，这样能保留 `$plink`、`$base` 等变量，并避免 OpenSSH 密码提示。

```powershell
mycli PowerShell-cli start --cwd D:\agent_workspace --idle-timeout-sec 600 --wait-ready

mycli PowerShell-cli send <session-id> --text "$plink='C:\Program Files\PuTTY\plink.exe'; $base=@('-ssh','-batch','-no-antispoof','-P','22','-hostkey','SHA256:...','-pw','<password>','root@<host>')"

mycli PowerShell-cli send <session-id> --text "& $plink @base 'hostname; whoami; pwd'"
mycli PowerShell-cli read <session-id> --wait-ms 2000
```

For the full server connection guide, see:

```text
D:\agent_workspace\capability-library\skill-library\aliyun-server-operation\SKILL.md
```

## State paths

```text
D:\agent_workspace\capability-library\mycli\PowerShell-cli\state\sessions\<session-id>
```

Session state includes metadata, broker process information, command queue, and output events.

## Safety notes

- `--admin` 会尝试通过 `Start-Process -Verb RunAs` 启动 broker，需要明确需要管理员权限时再用。
- 不要通过 `PowerShell-cli` 使用需要交互密码提示的 native `ssh`；密码型非交互命令使用 `plink -pw ...`。
- 这不是完整 ConPTY 模拟器，适合持久 PowerShell 命令控制，不等同于真实交互终端。
- 长时间不用的 session 应 `stop` 或 `cleanup --all`，避免后台 broker 持续占用资源。
