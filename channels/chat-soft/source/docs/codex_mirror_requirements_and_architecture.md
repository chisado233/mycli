# Codex 镜像需求与架构设计

更新时间：2026-04-17

## 1. 项目定义

`Codex 镜像` 是一个本地运行的同步系统，用于把 VS Code 中 Codex 插件的会话、消息、流式输出和控制能力镜像出来，并通过本地接口提供给外部系统使用。

它的目标不是“模仿一个类似 Codex 的 agent”，而是把 VS Code 里的 Codex 会话作为真实源头，构建一层：

- 可读
- 可写
- 可同步
- 可控制
- 可持久化

的本地镜像服务。

## 2. 核心目标

### 2.1 会话镜像

- 尽可能发现并同步 Codex 插件中的所有历史会话。
- 不同会话必须独立，不能串会话。
- 镜像层中的会话唯一标识直接沿用 Codex 内部会话 id。
- 镜像层允许对会话做本地重命名，但不回写到 Codex 插件。

### 2.2 消息镜像

- 同步用户消息与 Codex 回复消息。
- 支持流式输出镜像。
- 支持完整保留 Codex 原始结构，而不仅是纯文本。
- 消息成功的判定标准是：目标 Codex 会话中真实出现该用户消息。

### 2.3 控制能力

- 支持切换会话。
- 镜像中切换会话时，VS Code 中可见的 Codex 当前会话也要切过去。
- 支持切换模型。
- 模型切换既要更新镜像层记录，也要尽量同步到当前 Codex 会话。
- 支持新建会话，并可选指定模型。
- 支持失败消息重试发送。

### 2.4 接口能力

- 对外提供 REST 接口。
- 对外提供 WebSocket 实时事件流。
- 默认返回整理后的消息视图。
- 允许额外获取 raw event / 原始结构。

### 2.5 第一阶段落地形态

- 先做本地后台服务。
- 同时提供一个简单调试页面。
- 页面布局不是重点，优先保证功能完整和调试效率。

## 3. 非目标

以下内容不作为第一阶段重点：

- 手机端适配
- 复杂 UI 打磨
- 会话/消息搜索
- 备注、标签、收藏
- 删除 Codex 原始会话

说明：

- 手机端后续要方便接入，但第一阶段先不优先处理。
- 删除能力只作用于镜像层缓存，不修改 Codex 原始会话。

## 4. 用户已确认的关键需求

### 4.1 会话范围

- 目标范围尽可能大。
- 优先覆盖 Codex 插件中的所有历史会话，而不是仅当前工作区或当前可见会话。

### 4.2 实时性要求

- 尽可能快。
- 必须支持流式同步。
- 不仅要看到最终消息，还要尽量同步生成中的增量内容。

### 4.3 发送实现策略

- 优先走 Codex 插件内部/官方接口。
- 如果无法完全通过内部接口实现，可以接受本地 UI 模拟作为兜底。
- 核心目标是让消息稳定进入目标会话。

### 4.4 离线行为

- 需要明确显示 `Codex 未连接`。
- Codex 未连接时，尽量不允许实际操作，尤其是不允许发送消息。

### 4.5 排序与展示

- 会话列表默认按 Codex 原会话最近活跃时间排序。
- 会话列表保持简洁，不堆叠过多状态字段。
- 工具调用与中间事件默认折叠，可展开查看。
- 流式消息默认展示为一条持续更新的完整消息，同时支持查看增量片段。

### 4.6 导出

- 需要支持导出能力。
- 希望尽可能支持多种导出格式。
- 初步目标格式：
  - JSON
  - Markdown
  - 原始事件日志

## 5. 总体架构

建议将 `Codex 镜像` 拆成四层：

### 5.1 采集层

职责：

- 接入 VS Code + Codex 插件
- 发现会话
- 发现消息
- 捕获流式事件
- 捕获工具调用和中间事件
- 监听模型切换和会话切换

建议实现策略：

- 第一优先：Codex 插件内部能力 / app-server / 状态源
- 第二优先：VS Code 状态存储 / 工作区缓存 / 会话索引
- 第三优先：必要时使用 UI 注入兜底

### 5.2 镜像核心层

职责：

- 统一会话模型
- 统一消息模型
- 统一 raw event 存储
- 维护同步状态
- 处理会话重命名
- 做去重、排序、串行控制
- 保证切换会话和发送消息严格串行

### 5.3 存储层

建议使用本地数据库，优先 SQLite。

职责：

- 保存镜像会话
- 保存会话别名
- 保存消息整理视图
- 保存 raw event
- 保存流式片段
- 保存模型配置
- 保存同步游标与断点恢复状态

### 5.4 接口层

职责：

- 对外提供 REST
- 对外提供 WebSocket
- 提供调试页面
- 提供导出能力

## 6. 数据模型建议

### 6.1 会话模型

建议字段：

- `session_id`
- `source_session_id`
- `source` = `vscode-codex`
- `title`
- `mirror_title`
- `effective_title`
- `model_id`
- `created_at`
- `updated_at`
- `last_active_at`
- `is_deleted_in_mirror`
- `connection_state`

说明：

- `source_session_id` 与 `session_id` 第一阶段可相同，直接沿用 Codex 内部 id。
- `mirror_title` 用于本地重命名。
- `effective_title = mirror_title ?? source_title`

### 6.2 消息模型

建议字段：

- `message_id`
- `session_id`
- `source_message_id`
- `role`
- `status`
- `text`
- `created_at`
- `updated_at`
- `finalized_at`
- `is_streaming`
- `send_state`

其中：

- `send_state` 用于区分：
  - 待发送
  - 发送中
  - 已进入 Codex 会话
  - 失败

### 6.3 原始事件模型

建议字段：

- `event_id`
- `session_id`
- `message_id`
- `event_type`
- `event_index`
- `event_ts`
- `raw_payload`
- `normalized_payload`

### 6.4 流式片段模型

建议字段：

- `chunk_id`
- `message_id`
- `chunk_index`
- `chunk_text`
- `created_at`

## 7. 接口草案

### 7.1 REST

#### 会话接口

- `GET /api/codex-mirror/sessions`
  - 获取会话列表
- `POST /api/codex-mirror/sessions`
  - 新建会话
  - 可选指定模型
- `GET /api/codex-mirror/sessions/:sessionId`
  - 获取会话详情
- `PATCH /api/codex-mirror/sessions/:sessionId`
  - 修改镜像侧会话标题
- `DELETE /api/codex-mirror/sessions/:sessionId`
  - 仅删除镜像侧缓存
- `POST /api/codex-mirror/sessions/:sessionId/switch`
  - 切换当前会话，并同步切换 VS Code 可见会话

#### 消息接口

- `GET /api/codex-mirror/sessions/:sessionId/messages`
  - 默认返回整理视图
  - 可通过参数获取 raw events
- `POST /api/codex-mirror/sessions/:sessionId/messages`
  - 发送消息
  - 支持异步模式
  - 支持等待提交成功模式
- `POST /api/codex-mirror/messages/:messageId/retry`
  - 重试发送失败消息

#### 模型接口

- `GET /api/codex-mirror/models`
  - 获取可用模型
- `POST /api/codex-mirror/sessions/:sessionId/model`
  - 切换指定会话模型
- `POST /api/codex-mirror/default-model`
  - 设置默认模型

#### 导出接口

- `GET /api/codex-mirror/sessions/:sessionId/export?format=json`
- `GET /api/codex-mirror/sessions/:sessionId/export?format=markdown`
- `GET /api/codex-mirror/sessions/:sessionId/export?format=raw`

#### 状态接口

- `GET /api/codex-mirror/status`
  - 返回：
    - Codex 是否连接
    - 当前活跃会话
    - 默认模型
    - 最近同步时间

### 7.2 WebSocket

事件建议分两层：

#### 标准事件

- `session.created`
- `session.updated`
- `session.deleted`
- `session.switched`
- `message.created`
- `message.delta`
- `message.completed`
- `message.failed`
- `message.retrying`
- `connection.changed`

#### 原始事件

- `raw.codex.event`

说明：

- 默认调试和业务系统优先消费标准事件。
- 深度调试和高级接入可以消费 raw event。

## 8. 一致性与状态机要求

### 8.1 切换会话必须严格串行

- 切换会话与发送消息之间必须严格串行。
- 不能出现消息发送到错误会话的情况。
- 必要时应通过内部队列或 session lock 保证一致性。

### 8.2 发送成功判定

发送成功的判定标准：

- 不是“镜像层已提交”
- 不是“桥接层已调用”
- 而是“目标 Codex 会话中真实出现该用户消息”

### 8.3 离线限制

- `Codex 未连接` 时，发送功能不可用。
- 第一阶段不做离线消息排队补发。

## 9. 调试页面要求

第一阶段调试页面只要求满足开发与验证：

- 查看会话列表
- 切换会话
- 查看消息
- 发送消息
- 切换模型
- 新建会话
- 查看原始事件
- 查看流式片段
- 导出会话

UI 原则：

- 简单
- 可用
- 便于调试
- 不优先做视觉设计

## 10. 第一阶段实施范围

### 10.1 必做

- 本地服务进程
- SQLite 持久化
- 会话发现与同步
- 消息发现与同步
- 流式增量同步
- 会话切换
- 模型切换
- 新建会话
- 发送消息
- 失败重试
- REST 接口
- WebSocket 接口
- 调试页面
- 导出能力

### 10.2 可接受降级

如果某些 Codex 内部能力无法直接获取，第一阶段允许：

- 优先使用内部接口
- 必要时结合状态存储
- 最后用 UI 注入方式兜底

前提是：

- 行为稳定
- 不串会话
- 消息最终能进入目标会话

## 11. 风险点

### 11.1 Codex 插件内部接口不稳定

风险：

- 未来版本变化可能导致采集或发送失效

对策：

- 封装适配层
- 区分内部接口路径和 UI 注入兜底路径

### 11.2 无法直接获取完整历史会话

风险：

- 某些历史会话可能只能通过本地状态或缓存发现

对策：

- 多来源会话发现
- 统一合并和去重

### 11.3 流式事件结构不稳定

风险：

- 不同版本的事件字段可能变化

对策：

- 原样存 raw
- 镜像层只做最小必要标准化

### 11.4 切换会话和发送消息竞态

风险：

- 可能串会话

对策：

- 强制串行
- 明确 session lock 和确认机制

## 12. 下一步建议

在当前需求文档确认后，下一步进入：

1. 技术验证文档
   - 列出能够从 VS Code / Codex 读取到哪些真实状态
   - 列出可用于发送消息的真实入口

2. 项目骨架搭建
   - `apps/codex-mirror-server`
   - `apps/codex-mirror-debug`
   - `shared/codex-mirror-protocol`

3. 第一轮实现优先级
   - 先打通会话列表同步
   - 再打通消息读取
   - 再打通消息发送
   - 再补流式、模型切换、导出

## 13. 参考来源

- 需求问答记录见：
  [codex_mirror_requirements_discussion.md](D:/agent_workspace/projects/chat_soft/docs/codex_mirror_requirements_discussion.md)
