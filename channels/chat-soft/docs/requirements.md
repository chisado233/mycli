# 需求分析

## 项目目标
手机端（Android）通过云端中转，调用本机 PC 上的 OpenCode AI 助手，实现远程实时 AI 编程辅助。核心是建立一条「手机 → 云服务器 → 本机 Bridge → opencode serve」的 SSE 实时事件流通道。

## 目标用户
- 千束（本机用户）
- 个人私有使用，非多用户系统

## 核心需求

| 编号 | 需求 | 优先级 | 说明 |
|------|------|--------|------|
| R1 | 手机端发送文本消息，OpenCode 实时回复 | P0 | 核心链路，消息必须到达 bridge 并触发 opencode |
| R2 | 回复文本在手机端实时流式显示 | P0 | token 级 streaming，不是一次性展示 |
| R3 | 工具调用可视化（bash/write/search 等） | P1 | 手机端看到 agent 正在做什么操作 |
| R4 | 后台长时间运行不中断 | P1 | 切后台后 WS 保持连接，回前台消息不丢 |
| R5 | Markdown 格式化渲染 | P1 | 代码块、列表、表格正确显示 |
| R6 | Session 管理（新建/切换） | P1 | 支持 `/session new`、`/session <id>`、Picker 选 session |
| R7 | Agent/Model 切换 | P2 | 支持 `/agent`、`/model` 命令，列表显示+状态栏更新 |
| R8 | 开机自启 | P2 | Windows 启动时自动拉起 bridge + opencode serve |
| R9 | 手机端通知 | P3 | Agent 完成回复时推送通知栏消息（暂缓） |
| R10 | 消息历史补拉 | P1 | 切回前台时自动拉取离线期间消息 |

## 不做的事情（边界）

- 不做多用户/账号系统
- 不做端到端加密（私有网络）
- 不做图片/语音/视频消息（V1 只做文本）
- 不做 FCM 推送（当前 ForegroundService 保活）
- 不依赖第三方 IM 服务

## 验收标准

- 手机发消息 → opencode 回复 → 手机显示完整回复，延迟可接受
- 切后台 5 分钟再切回 → WS 重连 → 消息正常收发
- Windows 重启后 → bridge 自动启动 → 手机可正常发消息
- `/session new` → 新 session 创建成功 → 消息在新 session 中
- `/abort` → 当前 turn 取消 → 可继续发新消息