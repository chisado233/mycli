# channels

`channels` 是面向“外部消息入口 / 通信通道 / agent 桥接”的 `mycli` 容器包。每个子包负责一种消息通道或桥接方式。

## Subpackages

- `QQ` — QQ / NapCat / OneBot v11 通道，包含 `qq-bridge.js`，可桥接 OpenCode agents。
- `chat-soft` — Chat Soft 手机端 / 阿里云服务器 / 本机 private-assistant 通道。

## Discover

```powershell
mycli channels list
mycli channels QQ --help
mycli channels QQ list
mycli channels chat-soft --help
mycli channels chat-soft list
```

## Channel Monitor UI

脱手启动一个类似 QQ 的本机监控界面，集中查看各 channel 的收发消息、最近事件与连通状态：

```powershell
mycli channels monitor-ui
```

默认地址：

```text
http://127.0.0.1:45990
```

可选指定端口：

```powershell
mycli channels monitor-ui 45991
```

停止后台监控界面：

```powershell
mycli channels monitor-ui-stop
```

启动并自动用 Edge 打开：

```powershell
mycli channels monitor-ui-open
```

当前监控数据源：

- `QQ/logs/bridge.detached.out.log`、`QQ/logs/qq-bridge.log`、`QQ/logs/napcat.detached.out.log`：解析 QQ 收发消息和桥接事件。
- `chat-soft` 的本地 / 云端 HTTP API：读取最近消息与会话。
- PID state、端口、health URL：用于判断 channel 连通状态。

## Chat Soft

Chat Soft 是手机端 / 阿里云服务器 / 本机 private-assistant 的通信通道。

```powershell
mycli channels chat-soft start-detached
mycli channels chat-soft status-detached
mycli channels chat-soft stop-detached
```

- `start-detached`：启动本机 local agent bridge。
- `status-detached`：检查阿里云服务器、本地 `45888`、已注册 agent 与日志。
- `stop-detached`：停止本机 local agent bridge，不影响阿里云 PM2 服务。

当前 Chat Soft 的 channel 内源码副本位于：

```text
D:\agent_workspace\capability-library\mycli\channels\chat-soft\source
```

`start-detached` 依赖这份源码副本启动，不再依赖 `D:\agent_workspace\projects\chat_soft`。

## QQ / NapCat

```powershell
mycli channels QQ start-detached [qq]
mycli channels QQ status-detached
mycli channels QQ stop-detached
mycli channels QQ install-task [qq]
mycli channels QQ start-task
mycli channels QQ status-task
mycli channels QQ stop-task
mycli channels QQ avatar <qq> [size] [out]
mycli channels QQ members [group-id] --format json|table|md --out <file>
```

- `start-detached`：脱手启动 QQ channel bridge、NapCat 和 QQ 进程。
- `stop-detached`：停止脱手启动的 bridge、NapCat、QQ 进程。
- `install-task/start-task/status-task/stop-task`：通过 Windows Task Scheduler 管理 QQ channel。
- `avatar`：从 qlogo.cn 下载 QQ 头像，默认输出到 `D:\agent_workspace\tmp\qq-avatar`。
- `members`：通过 NapCat `get_group_member_list` 获取群成员；`group-id` 省略时使用 `bridge.config.json` 中的默认群。

## State and logs

```text
D:\agent_workspace\capability-library\mycli\channels\QQ\state
D:\agent_workspace\capability-library\mycli\channels\QQ\logs
D:\agent_workspace\capability-library\mycli\channels\chat-soft\state
D:\agent_workspace\capability-library\mycli\channels\chat-soft\logs
```

## Safety notes

- `channels` 会连接外部消息系统，启动或停止 bridge 会影响真实外部消息入口。
- 发送消息、群操作、启动常驻 bridge、安装计划任务等动作都应先确认用户意图。
- 日志可能包含外部消息内容，引用或外传前要注意隐私。
