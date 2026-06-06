# 架构设计

## 模块划分

```
chat-soft/source/
├── apps/
│   ├── desktop/                       ← Bridge（本机 Node.js）
│   │   └── electron/
│   │       ├── local-agent.ts         ← 核心：SSE 连接、透传、session 管理
│   │       ├── agent.ts               ← 入口：启动 local-agent
│   │       └── main.ts                ← Electron 窗口（未使用）
│   │   └── runtime/state/             ← session 持久化
│   └── mobile/                        ← 手机端（React + Capacitor）
│       ├── src/
│       │   ├── App.tsx                ← UI + reducer + SSE_EVENT handler
│       │   └── styles.css             ← 暗色主题
│       └── android/                   ← Android 原生层
│           └── app/src/main/java/
│               ├── ForegroundService.java  ← 后台保活
│               └── MainActivity.java      ← 入口 + 权限
├── server/
│   └── api/src/index.ts               ← 云服务器（Fastify + WebSocket）
├── shared/
│   ├── protocol/src/index.ts          ← 事件类型定义
│   └── core/src/index.ts              ← ChatClient（WS + HTTP 双通道）
└── tools/                             ← 废弃工具脚本
```

## 模块边界

### 模块：Bridge（desktop/electron/local-agent.ts）
- **职责**：启动 opencode serve → 连接 SSE `/event` → 接收手机消息 POST `/prompt_async` → 原样转发 SSE 事件
- **不负责**：消息存储、用户认证、事件转换/缩减
- **输入依赖**：云服务器 WS（bridge.message.new）、opencode serve SSE 流
- **输出/被依赖**：云服务器 WS（bridge.sse 等）、opencode serve API 调用

### 模块：手机端（mobile/src/App.tsx）
- **职责**：消息收发、SSE 事件渲染、命令 Picker、Markdown 显示、后台拉消息
- **不负责**：消息存储、AI 调用
- **输入依赖**：云服务器 WS（sse/command.response 事件）、Cloud server HTTP polling
- **输出/被依赖**：云服务器 WS（message.send_text）

### 模块：云服务器（server/api/src/index.ts）
- **职责**：消息持久化（db.json）、WebSocket 中继（phone↔bridge）、HTTP API
- **不负责**：AI 调用、SSE 事件解析
- **输入依赖**：phone WS、bridge WS、HTTP POST
- **输出/被依赖**：phone WS（sse/command.response）、bridge WS（bridge.message.new）

### 模块：协议层（shared/protocol）
- **职责**：定义所有事件类型（ChatMessage、ServerToClientEvent、BridgeClientEvent 等）
- **不负责**：网络传输、业务逻辑
- **输入依赖**：无
- **输出/被依赖**：所有模块（类型定义）

### 模块：ChatClient（shared/core）
- **职责**：Phone WebSocket 连接管理、HTTP polling 兜底、onSse/onStreamText 等事件分发
- **不负责**：UI 渲染
- **输入依赖**：云服务器 WS/HTTP
- **输出/被依赖**：手机端 App.tsx

## 数据流

```
Phone (React)
  ↓ WS /ws (message.send_text)
Server (Fastify + WS) → 存储 db.json → WS /ws/bridge (bridge.message.new)
  ↓
Bridge (Node.js)
  ↓ POST /session/{sid}/prompt_async (agentId + parts)
OpenCode Serve (port 4096)
  ↓ SSE /event (message.part.delta, session.idle, ...)
Bridge (透明转发)
  ↓ WS /ws/bridge (bridge.sse)
Server → pushToAll phone WS (sse)
  ↓
Phone ChatClient → onSse → SSE_EVENT reducer → 渲染
```

## 部署拓扑

```
┌─ 49.232.183.40 (腾讯云 CVM) ───────────┐
│  /opt/chat_soft/server/api/             │
│  PM2: chat-soft-server (端口 3000)       │
│  DB: /opt/chat_soft/data/db.json        │
└─────────────────────────────────────────┘
         ↕ WebSocket
┌─ 本机 Windows ───────────────────────────┐
│  Bridge: node dist-electron/agent.js      │
│          监听 127.0.0.1:45888             │
│  OpenCode Serve: 监听 127.0.0.1:4096     │
│  源码: capability-library/mycli/          │
│        channels/chat-soft/source/        │
└──────────────────────────────────────────┘
         ↕ WebSocket
┌─ 手机 (华为 MNA-AL00) ───────────────────┐
│  Capacitor WebView + React               │
│  ForegroundService 后台保活               │
└──────────────────────────────────────────┘
```