# 功能设计

## 功能列表

| 编号 | 功能 | 优先级 | 说明 |
|------|------|--------|------|
| F1 | SSE 实时消息流 | P0 | 手机 ↔ 云 ↔ Bridge ↔ opencode serve 四层透传 |
| F2 | 手机端 Markdown 渲染 | P1 | marked 库解析，代码块/表格/列表暗色主题 |
| F3 | 后台 WS 保活 | P1 | ForegroundService + 30s 心跳 + 3s 自动重连 |
| F4 | 回前台补拉消息 | P1 | visibilitychange 触发 fetchRecent |
| F5 | Session 管理 | P1 | `/session new` / `/session <id>` / Pick list |
| F6 | /abort 中断 | P1 | POST /session/{sid}/abort 取消当前 turn |
| F7 | Agent/Model 切换 | P2 | 列表显示 + 状态栏更新 |
| F8 | 开机自启 | P2 | Windows Task Scheduler 启动 bridge |
| F9 | 手机端通知 | P3 | Capacitor LocalNotifications（暂缓） |

## 功能详述

### F1: SSE 实时消息流

- **描述**：手机发送文本消息后，opencode serve 通过 SSE 流实时推送 token 级回复事件，bridge 原样转发到云服务器，云服务器转发到手机。不经过任何事件转换/缩减。
- **用户流程**：手机输入文本 → 点发送 → 看到逐字流式回复
- **前置条件**：bridge 运行中，opencode serve 运行中，手机 WS 已连接云服务器
- **后置条件**：回复完整显示在手机消息列表，`session.idle` 事件标记完成
- **异常处理**：WS 断开时 ChatClient 3s 自动重连，手机通过 HTTP polling 补拉消息

### F2: 手机端 Markdown 渲染

- **描述**：使用 `marked` 库将助手回复解析为 HTML，`dangerouslySetInnerHTML` 渲染。CSS 暗色主题适配 OpenCode 风格。
- **用户流程**：收到回复 → 自动渲染为格式化文本
- **前置条件**：无
- **后置条件**：无
- **异常处理**：marked 解析失败时降级为纯文本

### F3: 后台 WS 保活

- **描述**：Android ForegroundService 常驻通知防止进程被杀；ChatClient 每 30s 发送 `sync.pull` 心跳；WS 断开时 3s 自动重连。
- **用户流程**：切后台 → 无感知连接保持 → 回前台继续收发
- **前置条件**：通知权限已授予
- **后置条件**：WS 心跳持续运行

### F4: 回前台补拉消息

- **描述**：`document.addEventListener("visibilitychange", ...)` 检测回到前台，调用 `connect()` 和 `fetchConversationMessages` 补拉离线期间消息。
- **用户流程**：离开一段时间后回来 → 消息列表自动更新
- **前置条件**：无
- **后置条件**：消息列表包含离线期间所有消息

### F5: Session 管理

- **描述**：输入 `/session` 自动从 serve API 获取 session 列表并弹出 Picker，点选后输入框填入 `/session <id>`。`/session new` 创建新 session（`POST /session`）。
- **用户流程**：输入 `/session` → 弹出列表 → 点一个 → 输入框变成 `/session ses_xxx` → 回车切换
- **前置条件**：bridge 已连接 opencode serve
- **后置条件**：后续消息在新 session 中处理

### F6: /abort 中断

- **描述**：`POST /session/{sid}/abort` 到 opencode serve 取消当前 turn，重置 `state.running`。
- **用户流程**：发送 `/abort` → 当前回复中断 → 可继续发新消息
- **前置条件**：session 正在处理中
- **后置条件**：session 状态回到 idle，可接受新消息

### F7: Agent/Model 切换

- **描述**：`/agent` 从 opencode config agent 目录读 `.md` 文件列表；`/model` 从 `opencode.json` 读 provider/models。状态栏同步更新。**注意：serve API 接受但忽略 agentId/modelId，实际切换需改 opencode.json**。
- **用户流程**：输入 `/agent` 或 `/model` → 弹出列表 → 选择一个 → 状态栏更新
- **前置条件**：bridge 运行中
- **后置条件**：状态栏显示新 agent/model 名称

### F8: 开机自启

- **描述**：通过 `mycli startup add` 注册 Windows Task Scheduler 任务，登录时执行 `mycli channels chat-soft start-detached`，自动拉起 bridge 和 opencode serve。
- **用户流程**：Windows 重启 → 登录 → bridge 和 serve 自动启动
- **前置条件**：已注册启动项
- **后置条件**：bridge 监听 127.0.0.1:45888，serve 监听 127.0.0.1:4096