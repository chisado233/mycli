# 关键决策记录

> 记录项目中的关键选择：为什么选 A 不选 B、踩过的坑、重要的边界划分

---

### 使用 opencode serve SSE 而非 --format json
- **日期**：2026-06-06
- **决策**：放弃 spawn opencode --format json，改为启动 opencode serve 并通过 SSE /event 接收实时事件
- **原因**：--format json 的 JSONL 输出只有 step_start/tool_use/step_finish，永远不输出 type:text 事件。手机端需要 token 级流式显示，JSONL 做不到
- **替代方案**：mycli agent-cli run --return_mode stream（也用了 agent-cli，已弃用）
- **后果**：需要管理 serve 进程的生命周期，但获得了真正的 token 级流式

### Bridge 仅做透明转发，不缩减封装
- **日期**：2026-06-06
- **决策**：Bridge 不解析/转换/缩减 SSE 事件，只做原样透传
- **原因**：任何转换都会丢失信息，手机端需要完整的 opencode 事件流
- **替代方案**：将 SSE 事件转为自定义 bridge.stream.* 事件（旧方案）
- **后果**：新增 SseEvent 类型到协议，server relay 直接转发

### 云服务器 DB 使用 JSON 文件
- **日期**：2026-06-06
- **决策**：使用文件系统 JSON 存储，不引入数据库
- **原因**：单用户、低并发，JSON 足够简单。后续可迁移 SQLite
- **替代方案**：SQLite/PostgreSQL
- **后果**：PowerShell 写入会破坏 JSON 格式，必须用 node.js 操作

### ForegroundService 保活而非 FCM
- **日期**：2026-06-06
- **决策**：使用 Android ForegroundService 常驻通知保活 WS，不接入 FCM
- **原因**：FCM 需要服务端改造，当前单用户场景 ForegroundService 足够
- **替代方案**：FCM 推送、WorkManager 周期任务
- **后果**：通知栏有常驻 "Chat Soft Connected" 提示

### agentId/modelId 不生效时的降级策略
- **日期**：2026-06-06
- **决策**：/agent /model 仅显示列表和状态栏更新，不强制切换
- **原因**：opencode serve 的 prompt_async 接受但忽略 agentId/modelId 参数
- **替代方案**：改 opencode.json 全局配置
- **后果**：用户需手动改配置才能切换模型

### 手机端 WS 自动重连
- **日期**：2026-06-06
- **决策**：ChatClient WS close 后 3s 自动 connect()，不依赖上层手动重连
- **原因**：服务器重启后 phone WS 永久断开，用户无感知
- **替代方案**：HTTP polling 兜底（已有）+ 手动重连按钮
- **后果**：基本消除因服务器重启导致的断连问题

### 使用 Capacitor 而非原生 Android
- **日期**：2026-06-05
- **决策**：使用 Capacitor WebView + React，不写原生 Android UI
- **原因**：快速迭代、复用 Web 技术栈
- **替代方案**：原生 Kotlin/Swift
- **后果**：WebView JS 在后台可能被暂停，ForegroundService 缓解但通知难实现