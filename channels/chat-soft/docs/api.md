# 接口设计

## opencode serve API

| 方法 | 路径 | 说明 | 请求体 | 响应 |
|------|------|------|--------|------|
| POST | /session | 创建新 session | { agentId?, modelId? } | 200 JSON (session) |
| POST | /session/{sid}/prompt_async | 异步发送消息 | { parts: [{ type, text }], agentId?, modelId? } | 204 No Content |
| GET | /api/session | 获取 session 列表 | - | 200 JSON (items[]) |
| GET | /api/model | 获取模型列表 | - | 200 JSON (model[]) |
| POST | /session/{sid}/abort | 取消当前 turn | - | 200 true |
| PATCH | /session/{sid} | 更新 session | { modelId? } | 200 (不生效) |
| GET | /event | SSE 实时事件流 | - | text/event-stream |

## 云服务器 HTTP API

| 方法 | 路径 | 说明 |
|------|------|------|
| GET | /health | 健康检查 |
| GET | /api/agents | agent 列表 |
| POST | /api/agents/register | 注册 agent |
| GET | /api/conversations | 会话列表 |
| GET | /api/conversations/{id}/messages | 会话消息 |
| POST | /api/messages/text | 发送文本消息(通知bridge) |
| GET | /api/messages/recent | 最近消息 |
| PUT | /api/conversations/{id}/typing | typing 状态 |

## WebSocket 事件协议

### Bridge -> Server -> Phone

| Bridge 事件 | 中继后类型 | 用途 |
|-------------|-----------|------|
| bridge.sse | sse | opencode 原始 SSE 事件透传 |
| bridge.command.response | command.response | 命令查询响应 |
| bridge.status | status | agent/model/session 状态变更 |
| bridge.todo | todo | 任务列表 |

### Phone -> Server -> Bridge

| Phone 事件 | 中继后类型 | 用途 |
|-----------|-----------|------|
| auth.hello | (server 处理) | 设备认证 |
| message.send_text | bridge.message.new | 发送文本 |
| sync.pull | (server 处理) | 拉取全量消息 |

## SSE 事件类型

| 事件类型 | 含义 | 关键字段 |
|---------|------|---------|
| server.connected | SSE 连接建立 | - |
| message.updated | 消息创建/更新 | properties.info.role, .modelID |
| message.part.updated | part 状态变更 | properties.part.type |
| message.part.delta | 文本增量 | properties.delta |
| session.status | session 工作状态 | properties.status.type |
| session.idle | session 空闲(处理完成) | - |
| session.created | session 创建 | properties.info.id |
| session.diff | 文件变更 | properties.diff[] |
| server.heartbeat | 保活心跳 | - |

## 关键常量

- LOCAL_AGENT_PORT = 45888 (Bridge 监听端口)
- DEFAULT_CONVERSATION_ID = "primary"
- OPENCODE_SERVE_PORT = 4096 (serve 监听端口)
