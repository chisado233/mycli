# channels chat-soft

Chat Soft 的手机端 / 云服务器 / 本地 agent 网关通道封装。

## 一键启动

```powershell
mycli channels chat-soft start-detached
```

这个命令会脱手启动本机 Chat Soft local agent bridge，使手机端发到阿里云服务器的 `private-assistant` / `private-assistant-2` 消息能被本机 agent 轮询并回复。

启动依赖的是本 package 内的源码副本：

```text
D:\agent_workspace\capability-library\mycli\channels\chat-soft\source
```

默认使用：

- 项目目录：`D:\agent_workspace\capability-library\mycli\channels\chat-soft\source`
- 云服务器：`http://39.106.125.149:3000`
- 本地 agent 端口：`127.0.0.1:45888`
- agent-cli：`D:\agent_workspace\capability-library\mycli\mycli.ps1`
- agent：`opencode/private-assistant`
- agent 工作目录：`D:\agent_workspace`

## 状态检查

```powershell
mycli channels chat-soft status-detached
```

检查内容包括：

- PID state file
- 本地 `45888` 监听与 health
- 阿里云 `3000` health
- 本地已注册 opencode/private-assistant agents
- 本地 agent 日志尾部

## 停止本地网关

```powershell
mycli channels chat-soft stop-detached
```

只停止本机 `127.0.0.1:45888` local agent bridge，不会停止阿里云服务器上的 PM2 服务。

## 说明

手机端收发消息依赖两部分：

1. 阿里云 Chat Soft server：`39.106.125.149:3000`
2. 本机 local agent bridge：`127.0.0.1:45888`

服务器可以接收手机消息，但真正调用本地 `private-assistant` 回复，需要本机 local agent bridge 常驻。
