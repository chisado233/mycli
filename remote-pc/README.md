# mycli remote-pc

`remote-pc` 是远程电脑桥接控制能力的 `mycli` 子包。它通过腾讯云 WireGuard Hub 连接本机 A 与远端 B，支持 WireGuard 状态检查、远端盘映射、远端 PowerShell 执行，以及经腾讯云中转让 A 执行命令。

## 当前实测状态（2026-05-16）

- A 本机 WireGuard tunnel 正常，`wg-status` 可同时看到本地状态与服务器 `wg show`。
- 腾讯云 relay → A 的命令通道已打通，`relay-health`、`relay-run`、`test-relay-file` 可用。
- B 的 SMB 映射已可用；当前实测 `Y:`（`\\10.66.0.3\D$`）可读、可写、可删，可直接修改 B 上文件。
- B 的 SSH 命令执行已打通，`mycli remote-pc run B "hostname"`、`Get-Location`、`Get-ChildItem`、`Get-Service`、`Get-Process`、临时文件创建/读取/删除都已实测通过。
- `status B` 当前常见状态是 `SMB 445: OK`、`SSH 22: OK`、`Ping: FAIL`。ICMP 不通目前不是 blocker。
- `run B "..."` 适合终端/脚本/文件/服务管理，不适合指望 GUI 程序一定在当前桌面可见地弹窗；通过 SSH 启动浏览器或其他桌面程序不可靠。
- 远端 PowerShell 输出常夹带 `#< CLIXML` 与 progress 噪音；通常不是失败，只是输出格式问题。

## 推荐工作模式

```powershell
mycli remote-pc status B
mycli remote-pc connect B
mycli remote-pc run B "Get-Location"
mycli remote-pc run B "Get-ChildItem D:\agent_workspace"
mycli remote-pc run B "Get-Service sshd"
mycli remote-pc run B "Get-Process powershell,sshd"
mycli remote-pc run B "Get-Content D:\agent_workspace\tmp\note.txt"
mycli remote-pc relay-run "hostname"
mycli remote-pc relay-run "Get-Location"
```

- 文件直接改动优先用映射盘（如 `Y:`）。
- 命令执行、脚本执行、服务查询/管理优先用 `run B "..."`。
- 需要经腾讯云中转在 A 上执行命令时，用 `relay-run "..."`。
- 复杂 PowerShell 表达式含 `$`、引号、管道时，要注意本地 PowerShell 与远端 PowerShell 的双重转义。

## 当前网络

```text
腾讯云 WireGuard Hub: 49.232.183.40 / 10.66.0.1
当前 A 电脑: 10.66.0.2
未来 B 电脑: 10.66.0.3
WireGuard UDP: 51820
```

## Usage

```powershell
mycli remote-pc --help
mycli remote-pc paths
mycli remote-pc status B
mycli remote-pc connect B
mycli remote-pc disconnect B
mycli remote-pc repair B
mycli remote-pc run B "hostname"
mycli remote-pc wg-status
mycli remote-pc wg-start
mycli remote-pc wg-stop
mycli remote-pc wg-restart
mycli remote-pc test-relay-file
mycli remote-pc command-server-start
mycli remote-pc command-server-status
mycli remote-pc relay-health
mycli remote-pc relay-run "Get-Location"
mycli remote-pc command-server-stop
mycli remote-pc native help
```

## Device and drive operations

```powershell
mycli remote-pc status B
mycli remote-pc connect B
mycli remote-pc disconnect B
mycli remote-pc repair B
mycli remote-pc run B "hostname"
```

- `status <target>`：检查目标设备可达性和映射盘状态。
- `connect <target>`：把目标设备磁盘映射到本机盘符。
- `disconnect <target>`：移除映射盘。
- `repair <target>`：重新连接并验证映射盘。
- `run <target> <command>`：通过 SSH 在目标设备上执行 PowerShell 命令。

当前 `run B "..."` 已验证可稳定用于：

- `hostname`、`whoami`、`Get-Location`
- `Get-ChildItem`、`Resolve-Path`、`Test-Path`
- `Get-Service`、`Get-Process`、`Get-NetTCPConnection`
- 临时文件创建、读取、删除

不建议把 `run B "..."` 直接当作 GUI 自动化入口；`Start-Process` 虽可能成功，但 GUI 不一定在当前桌面会话中可见。

B 电脑接入后的目标使用体验：

```powershell
mycli remote-pc connect B
Copy-Item X:\abc.txt C:\abc.txt
Set-Content X:\note.txt "hello"
Get-ChildItem X:\Projects
mycli remote-pc disconnect B
```

## WireGuard operations

```powershell
mycli remote-pc wg-status
mycli remote-pc wg-start
mycli remote-pc wg-stop
mycli remote-pc wg-restart
mycli remote-pc test-relay-file
```

- `wg-status`：显示本地 WireGuard service / adapter 与服务器 `wg show` 状态。
- `wg-start`：启动或安装 A 机 WireGuard tunnel service。
- `wg-stop`：停止并卸载 A 机 WireGuard tunnel service。
- `wg-restart`：重启 A 机 WireGuard tunnel service。
- `test-relay-file`：验证服务器能经 WireGuard 访问 A 的临时文件服务。

当前 `test-relay-file` 已实测通过，可作为 A ↔ 服务器 ↔ WireGuard 文件链路的健康检查。

## Relay command execution

命令服务用于让腾讯云服务器经 WireGuard 访问 A，并让 A 执行 PowerShell 命令。默认监听：

```text
10.66.0.2:18082
```

管理命令服务：

```powershell
mycli remote-pc command-server-start
mycli remote-pc command-server-status
mycli remote-pc relay-health
mycli remote-pc command-server-stop
```

经腾讯云中转，让 A 执行命令：

```powershell
mycli remote-pc relay-run "hostname"
mycli remote-pc relay-run "Get-Location"
mycli remote-pc relay-run "D:\agent_workspace\capability-library\mycli\mycli.ps1 agent-cli current"
```

当前 `relay-run` 已实测可用，适合：

- 在 A 上查询当前位置、主机名、服务状态
- 触发 A 上的 PowerShell / mycli / 脚本命令

当前 relay 命令链路使用腾讯云服务器上的 `authorized_keys` + 本机 OpenSSH 私钥；如更换 key 或 host key，需要同步更新 `config\secrets.local.json` / `config\relay.env.local`。

## Config and state paths

```text
D:\agent_workspace\capability-library\mycli\remote-pc\config\devices.local.json
D:\agent_workspace\capability-library\mycli\remote-pc\config\drive-maps.local.json
D:\agent_workspace\capability-library\mycli\remote-pc\wireguard\client-a.local.conf
D:\agent_workspace\capability-library\mycli\remote-pc\wireguard-validation.md
D:\agent_workspace\capability-library\mycli\remote-pc\logs
```

`client-a.local.conf` 包含 A 客户端 WireGuard 私钥，应视为本地敏感配置，不要外传。

## Safety boundaries

- 腾讯云安全组只需要开放 UDP `51820` 给 WireGuard。
- 不要向公网开放 SMB `445`、WinRM `5985/5986` 或 Windows SSH。
- SMB、SSH 远程命令和 command server 只应该通过 WireGuard 内网访问。
- `relay-run` 会在 A 机执行任意 PowerShell 命令；高风险命令必须先取得用户明确授权。
- 当前 command endpoint 是内网自用版，已限制来源 IP；长期运行前建议补 token、请求签名、命令审计和服务化管理。
- `relay-run` 外层通常使用双引号，内部 prompt 建议使用单引号。
- `run B "..."` 与 `relay-run "..."` 都更适合 CLI/脚本/服务管理，不要默认它们能可靠拉起当前桌面可见的 GUI 窗口。
