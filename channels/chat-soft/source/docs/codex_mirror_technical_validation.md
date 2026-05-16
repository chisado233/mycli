# Codex 镜像技术验证记录

更新时间：2026-04-17

## 最新实测结果

### 2026-04-17 第二轮联调

已通过本地真实联调确认：

- 本地镜像服务可直接拉起 Codex `app-server`
- `GET /api/codex-mirror/status` 可返回真实连接状态
- `GET /api/codex-mirror/models` 可返回真实模型列表
- `GET /api/codex-mirror/sessions` 可返回真实历史会话列表
- `POST /api/codex-mirror/sessions` 可真实新建 Codex 会话
- `POST /api/codex-mirror/sessions/:sessionId/messages` 可真实发送消息到 Codex
- `GET /api/codex-mirror/sessions/:sessionId/messages` 可拉回真实用户消息与 Codex 回复

本地实测样例：

- 新建会话成功创建线程 `019d9b5d-364a-7632-b28f-284028e36cc8`
- 发送消息内容：`请只回复四个汉字`
- Codex 真实回复：`四个汉字`

当前仍然保留的限制：

- 镜像层“切换会话”目前只更新镜像服务内当前会话状态，还没有驱动 VS Code 可见标签页一起切换
- 消息列表已经能读到真实消息，但逐条消息时间仍是镜像层归一化结果，不是完整原始事件时间
- 工具调用、reasoning、raw event 入口已保留，但调试页还没完成细粒度展示
- 在当前机器上本地联调时，`Invoke-RestMethod` 会偶发走异常代理链路，推荐使用 `curl.exe --noproxy "*"`

## 1. 目标

本文件用于记录 `Codex 镜像` 当前阶段已经确认的技术事实、可用入口、可用状态源和主要风险，作为后续接入实现的依据。

## 2. 当前已验证的可用来源

### 2.1 OpenAI VS Code 扩展

本地已安装扩展：

- `openai.chatgpt-26.415.20818-win32-x64`

已确认扩展内部存在 Codex 相关命令与结构，包括：

- `chatgpt.openSidebar`
- `chatgpt.newCodexPanel`
- `chatgpt.newChat`
- `chatgpt.addToThread`

结论：

- 有现成的“打开侧边栏 / 新建会话 / 往线程添加上下文文件”的入口。
- 但尚未发现公开且稳定的“把任意文本直接发到当前活动 Codex 会话输入框并提交”的标准命令接口。

### 2.2 Codex app-server

现有桥接代码已经验证过以下能力可以通过 app-server 获取：

- `model/list`
- `thread/list`
- `thread/read`
- `thread/start`
- `turn/start`

结论：

- 会话列表、会话内容、模型列表、新建会话、发起 turn 都存在可用入口。
- 这是当前最值得优先依赖的“官方/内部接口路径”。

### 2.3 VS Code workspaceStorage

已验证 VS Code 会在：

- `Code/User/workspaceStorage/<workspace-id>/workspace.json`
- `Code/User/workspaceStorage/<workspace-id>/state.vscdb`

中保存当前工作区相关状态。

其中已确认有价值的键：

- `workspace.json`
  - 可判断该 storage 对应哪个工作区
- `agentSessions.model.cache`
  - 可发现 Codex 会话资源
  - 会话资源形如：
    - `openai-codex://route/local/<session-id>`

结论：

- 这是一个非常关键的“历史会话与最近活跃会话补充来源”。
- 即使当前没有直接打开 Codex 会话标签页，也可能从这里拿到工作区最近活跃的 Codex 会话。

### 2.4 现有桥接代码

当前仓库内已有桥接扩展：

- [extension.ts](D:/agent_workspace/projects/chat_soft/tools/codex-vscode-bridge/src/extension.ts)

已经具备的能力包括：

- 读取模型列表
- 读取线程列表
- 读取线程内容
- 新建线程
- 发送 turn
- 读取当前工作区的 `workspaceStorage`
- 从标签页和 workspaceStorage 里解析当前线程候选

结论：

- 这份桥接代码可以直接作为 `Codex 镜像接入层` 的实验基础，而不是从零开始。

## 3. 当前已验证的能力判断

### 3.1 会话发现

当前可行性：高

原因：

- app-server 有 `thread/list`
- workspaceStorage 有 `agentSessions.model.cache`
- 标签页和自定义 editor URI 中也可解析出 thread id

判断：

- “发现会话”不是当前最大难点。
- 真正难点在于：
  - 尽可能覆盖所有历史会话
  - 去重与排序
  - 当前活动会话的准确判定

### 3.2 消息读取

当前可行性：高

原因：

- `thread/read` 已可拿到线程及 turns
- turn 中可以解析：
  - 用户消息
  - assistant 消息
  - reasoning
  - 其他 item

判断：

- 第一阶段实现“消息读取”和“历史同步”是完全可行的。

### 3.3 新建会话

当前可行性：高

原因：

- `thread/start` 已验证可用

判断：

- 新建会话接口可以优先基于 app-server 实现。

### 3.4 模型切换

当前可行性：中

原因：

- `model/list` 已验证可用
- 新建线程时可以指定模型
- 但“对一个已有当前会话立即切换模型”的标准入口还需要进一步验证

判断：

- 第一阶段至少可以保证：
  - 新会话按指定模型创建
  - 镜像层保存默认模型
  - 后续消息按当前模型策略生效
- 对“现有会话即时切模”的能力还要继续验证。

### 3.5 向当前活动会话直接发消息

当前可行性：中偏低

现状：

- 还没有找到一个干净公开的 VS Code 命令，可以把任意文本直接送进当前活动 Codex 会话。
- app-server 的 `turn/start` 能够往某个 thread 发起新 turn，这是当前最有希望的正路。

风险：

- “当前活动会话”的概念在 UI 层和 app-server 线程层之间不一定完全等价。

判断：

- 第一阶段发送链路应优先基于 app-server thread/turn 能力构建。
- 如果要严格做到“等同于你在当前可见 Codex 输入框输入”，可能还需要 UI 注入兜底。

## 4. 当前最大技术风险

### 4.1 历史会话覆盖范围

问题：

- app-server 和 workspaceStorage 是否能覆盖“所有历史会话”仍需进一步实测。

风险：

- 某些老会话可能不在当前工作区缓存里。

### 4.2 流式事件获取

问题：

- 虽然最终 turn 结果可读取，但完整流式中间事件、delta、工具事件是否能稳定拿到，还需要继续验证。

风险：

- 可能只能在某些内部通知或 webview 事件里拿到最细粒度流数据。

### 4.3 当前活动会话判定

问题：

- 现在可以通过标签页、自定义 URI、workspaceStorage 猜测当前活动会话。
- 但“百分之百等价于用户眼前正在操作的那条 Codex 会话”仍未被彻底锁定。

### 4.4 发送确认

问题：

- 用户要求“发送成功 = 消息真实出现在 Codex 会话里”。
- 这需要我们建立发送后的确认机制，而不是只相信本地提交成功。

## 5. 建议的接入优先级

### 第一优先级

- 基于 app-server 完成：
  - 模型列表
  - 会话列表
  - 会话消息读取
  - 新建会话
  - 基于 thread 的消息发送

### 第二优先级

- 基于 workspaceStorage 增强：
  - 当前工作区最近活跃会话识别
  - 历史会话补充发现
  - 当前活动会话候选对齐

### 第三优先级

- 必要时加入 UI 注入兜底：
  - 切换可见会话
  - 将文本注入输入框
  - 触发发送

## 6. 当前结论

当前阶段可以做出的判断是：

- `Codex 镜像` 不是空想，已经具备明确可落地的技术入口。
- 读取侧能力已经比较扎实。
- 新建会话能力也比较扎实。
- 发送能力已有可行正路，但要达到“完全等价当前 UI 会话操作”仍需继续验证。
- 第一阶段完全可以先把一个真实可运行的镜像服务做起来，再逐步逼近“完全镜像”。

## 7. 与当前代码的关系

当前新增的服务与调试页骨架：

- [index.ts](D:/agent_workspace/projects/chat_soft/server/codex-mirror/src/index.ts)
- [App.tsx](D:/agent_workspace/projects/chat_soft/apps/codex-mirror-debug/src/App.tsx)
- [index.ts](D:/agent_workspace/projects/chat_soft/shared/codex-mirror-protocol/src/index.ts)

它们当前属于：

- 架构骨架
- 接口骨架
- 调试入口骨架

尚未完成的部分主要是：

- 与真实 Codex app-server 的接入
- 与现有 VS Code bridge 的复用或整合
- 真实流式事件采集
- 发送确认机制
