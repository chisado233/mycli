# task-hall

当前任务前台协议版本：`frontdesk-v0.2`

`task-hall` 是面向 agent 的任务大厅。它只负责任务从“提交/上传”到“上架、展示、领取记录、报告审核、关闭或重新上架”的生命周期，不直接执行任务内容；当前新版支持由 task-hall 事件触发 `lifecycle-wake`，再由程序化 `lifecycle-tick` 调度合适 agent 执行任务。

## Design

任务大厅支持三类任务请求来源：

- `scheduled`：定时定点发布到大厅的任务。
- `trigger`：外部条件满足后发布到大厅的任务；条件检查由用户自定义 trigger 负责。
- `custom`：手动上传和上架的临时任务。

任务请求入口推荐使用 JSON；通过前台 agent 审核后生成 Markdown 任务说明文件，推荐命名为 `task.md`。任务正文、约束、交付物、验收标准和领取门槛以 Markdown 为主体。

前台 agent 与审核 agent 配置位于：

```text
C:\Users\38188\.config\opencode\agent\task-hall-frontdesk.md
C:\Users\38188\.config\opencode\agent\task-hall-reviewer.md
```

## Frontdesk v0.2 Protocol

`frontdesk-v0.2` 采用“轻 JSON 入口 + Markdown 语义协议”的设计：

- 任务提交时，上交任务请求 JSON。
- 前台 agent 判断任务是否可接受、描述是否完整。
- 不完整则退回，要求发起 agent 重新提交任务请求。
- 通过后由前台 agent 生成 `task.md`。
- `task.md` 中必须包含 `## 领取门槛`，写明复杂度和最低模型要求。
- agent 领取时提交领取申请 JSON。
- 前台 agent 根据 `task.md` 的领取门槛和领取申请中的模型等级判断是否允许领取。
- skill 不作为第一版硬性领取条件。

### Task Request JSON

任务请求 JSON 最小结构：

```json
{
  "request_type": "scheduled | trigger | custom",
  "title": "任务标题",
  "requester": "请求发起方",
  "description": "任务描述",
  "context": "背景上下文",
  "expected_output": "期望交付物",
  "constraints": []
}
```

可选字段：

```json
{
  "target_path": "目标路径",
  "schedule": "定时规则，仅 scheduled 需要",
  "trigger": "触发条件，仅 trigger 需要",
  "priority": 50,
  "tags": []
}
```

### Claim Request JSON

领取申请 JSON 最小结构：

```json
{
  "task_id": "任务 ID",
  "agent_id": "申请 agent ID",
  "model": "模型 ID",
  "model_tier": "nano | cheap | standard | strong | expert",
  "claim_reason": "领取理由"
}
```

模型等级顺序固定为：

```text
nano < cheap < standard < strong < expert
```

### Markdown 领取门槛

前台 agent 生成或更新任务 Markdown 时，应包含类似小节：

```markdown
## 领取门槛

复杂度：中高

最低模型要求：strong

不建议使用：

- nano
- cheap

领取要求说明：

本任务涉及共享工具设计和多步骤判断，不允许低等级模型领取。
```

## Reviewer v0.1 Protocol

审核 agent 根据原始任务 Markdown 和执行 agent 提交的任务报告 Markdown 判断任务出口。

审核 agent 不执行任务、不运行验证命令、不修改产物，只做文本一致性判断。

审核结论只使用四类：

```text
complete            任务已完全完成，下架并归入已完成
return_to_agent     未完全完成，打回原 agent 继续
relist_as_is        原任务仍合理，原样重新上架
revise_and_relist   根据已完成部分和困难修订任务后重新上架
```

任务报告推荐结构：

```markdown
# 任务报告

## 任务结论

完成 / 部分完成 / 受阻 / 无法完成

## 完成内容

- ...

## 未完成内容

- ...

## 产物路径

- ...

## 验证结果

- ...

## 遇到的问题

- ...

## 是否需要继续

- ...
```

## Status Model

```text
draft      uploaded but not visible in the hall
listed     visible and claimable
claimed    claimed by an agent; hidden from the default hall view
done       submitted as successful
cancelled  cancelled by operator
archived   hidden from normal active views
```

默认大厅视图只展示 `listed` 任务。领取后任务会进入 `claimed`，不会再出现在默认 `tasks` 列表里；需要看所有任务时用 `tasks all`，看已领取用 `tasks claimed`。

## Storage

默认状态目录位于本包内：

```text
D:\agent_workspace\capability-library\mycli\task-hall\state
```

结构：

```text
state/
  listings.json
  events.jsonl
  requests/
    req_xxx/
      request.json
      frontdesk.raw.txt
      frontdesk-response.json
  tasks/
    task_xxx/
      task.md
      meta.json
      claims.jsonl
      submissions.jsonl
      claim-review-yyyymmdd_hhmmss.json
      submission-review-yyyymmdd_hhmmss.json
      task-report-yyyymmdd_hhmmss.md
```

## Current Implementation Progress

当前已落地并测试通过：

- `submit-request` 会调用 `agent-cli` 运行 `opencode/task-hall-frontdesk`。
- 前台 agent 审核任务请求 JSON；通过后生成包含 `## 领取门槛` 的 `task.md`。
- `submit-request` 默认创建并上架 `listed` 任务；使用 `--draft` 可只创建草稿。
- `claim` 默认调用 `opencode/task-hall-frontdesk` 审核领取申请；通过后才进入 `claimed`。
- `review-submission` 调用 `opencode/task-hall-reviewer` 审核任务报告。
- 审核结论 `complete` 会把任务置为 `done`；`relist_as_is` 会重新上架；`revise_and_relist` 会更新 `task.md` 并重新上架；`return_to_agent` 只记录审核结果并要求原 agent 继续。
- `tasks all --json` 可输出 JSON 列表。

前台与审核 agent 配置文件：

```text
C:\Users\38188\.config\opencode\agent\task-hall-frontdesk.md
C:\Users\38188\.config\opencode\agent\task-hall-reviewer.md
```

已知边界：

- `task-hall` 本身不执行任务内容；它只在发布、report、continue、switch 等事件发生时启动程序化 lifecycle tick，由 tick 调度 agent。
- skill 不作为第一版硬性领取条件。
- 领取申请最稳方式是提供 `claim.json`，避免 PowerShell 参数透传歧义。
- 前台/审核 agent 返回 JSON 的稳定性依赖其 prompt；脚本会保存 raw output 和解析后的 JSON 以便排错。


## Event-driven Lifecycle Wake

新版 task-hall 不需要常驻 AI，也不需要固定轮询 daemon。正常情况下，只要通过 task-hall 命令产生关键事件，task-hall 会立即启动一次后台 lifecycle tick。

自动触发点：

- `publish` / `publish-raw` / `upload-publish` / `submit-request` 成功上架任务；
- `task-link report`，执行者提交 watched 任务报告；
- `task-link continue`，发布者要求原执行者返工；
- `task-link switch-agent`，发布者切换执行 agent。

触发后 task-hall 会用程序启动后台进程。正常非 dry-run 的 tick 会优先执行 `dispatch listed tasks`，确保新上架任务先被领取；后续 callback / recover / continue / switched 阶段彼此隔离，单阶段异常会记录 `lifecycle.stage_failed` 事件并继续后续阶段。等价于：

```powershell
mycli task-hall lifecycle-tick --listed-limit 2 --callback-limit 5 --cwd D:\agent_workspace
```

输出与元数据记录在：

```text
D:\agent_workspace\capability-library\mycli\task-hall\state\lifecycle-wake\
```

手动补偿命令：

```powershell
mycli task-hall lifecycle-wake --reason manual --cwd D:\agent_workspace
mycli task-hall lifecycle-tick --listed-limit 2 --callback-limit 5 --cwd D:\agent_workspace
```

通常不需要开机启动或常驻轮询。例外：如果机器重启前已有 listed / claimed / waiting_publisher / continued / switched / pending callback 等历史遗留状态，且重启后没有新的 task-hall 事件触发，可手动运行一次 `lifecycle-wake --reason startup-recover`。

注意：为避免历史 continue/callback/recover 任务阻塞新任务领取，事件驱动的正常 tick 将 listed 分发放在第一阶段。dry-run 仍按完整诊断顺序展示 callbacks、recover、continue、switched、recover claimed、listed。

## Agent Pools and Multi-session Concurrency

生命周期调度采用“agent 类型 + agent 模板 + 多 session”模型：

- `required_agent_type` 决定任务需要哪类 agent；
- 每类 agent 绑定一个默认 agent 模板和模型；
- 同一个 agent 模板可以为不同任务启动多个独立 session；
- 并发上限按 agent 类型统计，不按 agent id 是否相同统计；
- task meta / task-link 会记录 `executor_agent`、`executor_agent_type`、`executor_session`；
- watched 子任务 callback 优先回到 `publisher_session`，避免多个同模板 leader session 串线。

当前默认池：

| agent 类型 | agent 模板 | 并发上限 |
|---|---|---:|
| engineering-leader | `opencode/engineering-leader` | 2 |
| senior-builder | `opencode/senior-builder` | 2 |
| middle-builder | `opencode/middle-builder` | 3 |
| qa | `opencode/engineering-qa` | 1 |
| agent-creator | `opencode/engineering-agent-creator` | 1 |

例子：如果同时出现 3 个 `engineering-leader` 任务，前两个会用 `opencode/engineering-leader` 模板分别启动两个不同 session；第三个保持 listed，等待任一 leader task 被 `complete` / `cancel` 释放容量后再调度。

## Usage

```powershell
mycli task-hall init

mycli task-hall submit-request D:\agent_workspace\tmp\task-request.json
mycli task-hall submit-request D:\agent_workspace\tmp\task-request.json --draft
mycli task-hall claim task_20260424_210000_abc123 opencode/private-assistant D:\agent_workspace\tmp\claim.json
mycli task-hall review-submission task_20260424_210000_abc123 D:\agent_workspace\tmp\task-report.md

mycli task-hall upload D:\agent_workspace\tmp\task.md custom 50 workspace "整理下载目录"
mycli task-hall upload-publish D:\agent_workspace\tmp\task.md custom 50 workspace "整理下载目录"

mycli task-hall tasks
mycli task-hall tasks listed
mycli task-hall tasks claimed
mycli task-hall tasks all
mycli task-hall show task_20260424_210000_abc123

mycli task-hall publish task_20260424_210000_abc123
mycli task-hall edit task_20260424_210000_abc123 "新标题" custom 80 "tag1,tag2" D:\agent_workspace\tmp\new-task.md
mycli task-hall claim task_20260424_210000_abc123 opencode/private-assistant D:\agent_workspace\tmp\claim.json
mycli task-hall claim task_20260424_210000_abc123 opencode/private-assistant --no-frontdesk
mycli task-hall release task_20260424_210000_abc123 opencode/private-assistant
mycli task-hall submit task_20260424_210000_abc123 success opencode/private-assistant "完成说明"
mycli task-hall submit task_20260424_210000_abc123 fail opencode/private-assistant "失败原因，会自动重新上架"
mycli task-hall done task_20260424_210000_abc123 opencode/private-assistant "completed"

mycli task-hall cancel task_20260424_210000_abc123
mycli task-hall delete task_20260424_210000_abc123
mycli task-hall archive task_20260424_210000_abc123
mycli task-hall status
```

`submit-request` 会调用 `mycli agent-cli run --agent opencode/task-hall-frontdesk`，把任务请求 JSON 交给前台 agent 审核。审核通过后自动创建 `task.md` 任务并默认上架；带 `--draft` 时只创建草稿。

`claim` 默认会调用前台 agent 审核领取申请。若要手动绕过前台审核，可使用 `--no-frontdesk`，但只建议维护者在测试或修复异常时使用。

`review-submission` 会调用 `opencode/task-hall-reviewer`，根据原始任务 Markdown 和任务报告 Markdown 判断任务完成、打回、原样重上架或修订后重上架。

## Submit Semantics

- `submit <task-id> success <agent> <note>`：任务成功，状态变为 `done`。
- `submit <task-id> fail <agent> <note>`：任务失败，记录失败说明，并把任务重新上架为 `listed`。
- `done` 是兼容旧用法的成功提交快捷命令。

推荐新流程中优先使用 `review-submission <task-id> <report.md>`，让审核 agent 根据原任务和任务报告判断是否归档、打回或重新上架。`submit success/fail` 保留为简单兼容命令。

## Agent 发布任务规范

推荐使用 `submit-request` 发布任务，不推荐 agent 直接 `upload-publish` 未经前台审核的 Markdown。

### 1. 任务请求 JSON 必填字段

```json
{
  "request_type": "custom",
  "title": "任务标题",
  "requester": "opencode/private-assistant",
  "description": "要完成什么",
  "context": "为什么要做、已有背景、相关路径或系统",
  "expected_output": "期望交付物",
  "constraints": [
    "约束 1",
    "约束 2"
  ]
}
```

`request_type` 只能使用：

- `scheduled`：定时任务。
- `trigger`：触发型任务。
- `custom`：自定义任务。

可选字段：

```json
{
  "target_path": "D:\\agent_workspace\\...",
  "schedule": "daily 09:00",
  "trigger": "当某事件发生时",
  "priority": 50,
  "tags": ["task-hall", "docs"]
}
```

### 2. 发布命令

默认提交并上架：

```powershell
mycli task-hall submit-request D:\agent_workspace\tmp\task-request.json
```

只创建草稿：

```powershell
mycli task-hall submit-request D:\agent_workspace\tmp\task-request.json --draft
```

指定前台 agent：

```powershell
mycli task-hall submit-request D:\agent_workspace\tmp\task-request.json --agent opencode/task-hall-frontdesk
```

### 3. 发布质量要求

发起 agent 必须让请求 JSON 足以被前台 agent 判断：

- 目标清楚。
- 背景清楚。
- 交付物清楚。
- 约束清楚。
- 如果涉及具体路径，必须给出路径。
- 如果是 `scheduled`，必须给出时间/频率与输出位置。
- 如果是 `trigger`，必须给出触发条件、输入事件和输出动作。
- 如果涉及删除、发布、push、部署、外部写入、账号、凭据、付费资源等高风险操作，必须写明授权边界和安全约束。

如果前台 agent 退回请求，发起 agent 应根据 `frontdesk-response.json` 中的 `missing_information` 和 `suggested_request_patch` 修改请求后重新提交。

### 4. 不要这样发布

- 不要只写一句“修一下 bug”。
- 不要隐藏高风险动作。
- 不要把多个无关目标塞进一个任务。
- 不要把临时想法、闲聊或未成形需求直接发布。
- 不要绕过前台 agent 批量 `upload-publish`，除非用户明确要求或维护者在做兼容测试。

## Agent 领取规范

领取前必须先阅读任务：

```powershell
mycli task-hall show <task-id>
```

推荐使用 `claim.json` 申请领取：

```json
{
  "task_id": "task_...",
  "agent_id": "opencode/private-assistant",
  "model": "MoreCode/gpt-5.5",
  "model_tier": "expert",
  "claim_reason": "我已阅读任务，模型等级满足领取门槛，准备立即处理。"
}
```

命令：

```powershell
mycli task-hall claim <task-id> opencode/private-assistant D:\agent_workspace\tmp\claim.json
```

领取规则：

- 前台 agent 会读取任务 `## 领取门槛`。
- 申请中的 `model_tier` 必须满足最低模型要求。
- skill 不作为第一版硬性要求。
- 不满足门槛会拒绝领取。
- `--no-frontdesk` 只用于维护者测试或异常修复，不应作为普通领取方式。

## Agent 提交任务报告规范

执行 agent 完成、部分完成、受阻或无法完成时，应提交 Markdown 任务报告，然后走审核：

```powershell
mycli task-hall review-submission <task-id> D:\agent_workspace\tmp\task-report.md
```

### 1. 报告模板

```markdown
# 任务报告

## 任务结论

完成 / 部分完成 / 受阻 / 无法完成

## 完成内容

- ...

## 未完成内容

- ...

## 产物路径

- `D:\path\to\file`

## 验证结果

- 执行了什么命令或检查
- 结果是什么
- 如果没有验证，说明原因

## 遇到的问题

- ...

## 是否需要继续

- 不需要，任务已完成
- 需要，建议继续做 ...
- 无法继续，原因是 ...
```

### 2. 完成报告必须包含

- 对原任务目标逐项回应。
- 对原任务交付物逐项说明。
- 关键产物路径。
- 验证方式和结果。
- 明确说明没有关键未完成项。
- 如果任务要求不产生文件，必须说明实际产出形式。

### 3. 部分完成/受阻报告必须包含

- 已完成部分。
- 未完成部分。
- 阻塞原因。
- 已尝试步骤。
- 保留的中间产物路径。
- 建议下一步。
- 是否建议修订任务、拆分任务、提高领取门槛或原样重新上架。

### 4. 审核 agent 的处理

审核 agent 只根据原始任务 Markdown 与任务报告 Markdown 判断：

- `complete`：任务完全完成，下架归入已完成。
- `return_to_agent`：未完全完成，打回原 agent 继续。
- `relist_as_is`：原任务仍合理，原样重新上架。
- `revise_and_relist`：根据当前完成情况和困难修订任务后重新上架。

报告越具体，越容易通过审核；只写 `ok`、`done`、`failed` 通常会被打回。

## Agent 使用守则

本节是给会主动使用任务大厅的 agent 的操作规范。

### 1. 定位与边界

- `task-hall` 是任务大厅，不是执行器，也不是编排器。
- 大厅只表示“有什么任务可以领取”和“谁领取/提交了什么结果”。
- agent 是否领取、如何执行、是否需要拆解任务，由 agent 自己负责。
- 不要把任务领取等同于用户授权执行高风险动作；任务里的约束和用户当前指令仍然优先。

### 2. 查看任务

默认只看可领取任务：

```powershell
mycli task-hall tasks
```

需要查看特定状态时：

```powershell
mycli task-hall tasks listed
mycli task-hall tasks claimed
mycli task-hall tasks done
mycli task-hall tasks all
```

看到候选任务后，必须先阅读任务详情：

```powershell
mycli task-hall show <task-id>
```

不要只凭标题领取任务。

### 3. 领取任务

只有当你确认自己准备处理该任务时，才领取：

```powershell
mycli task-hall claim <task-id> <agent-id> D:\path\claim.json
```

领取后任务状态变为 `claimed`，默认大厅不再显示，避免其他 agent 重复领取。

推荐 `agent-id` 使用稳定标识，例如：

```text
opencode/private-assistant
codex/default
agent/<name>
```

### 4. 领取后的处理

- 领取后应尽快处理或释放，不要长期占用。
- 如果发现任务不适合自己、范围不清、权限不足，应该释放：

```powershell
mycli task-hall release <task-id> <agent-id>
```

- 如果执行完成、部分完成、受阻或无法完成，推荐写任务报告并交给审核 agent：

```powershell
mycli task-hall review-submission <task-id> D:\path\task-report.md
```

- 如果执行失败但任务仍值得别人继续做，也可以使用兼容提交命令；系统会自动重新上架：

```powershell
mycli task-hall submit <task-id> fail <agent-id> "失败原因、已尝试步骤、建议下一步"
```

- 如果执行成功，应提交成功：

```powershell
mycli task-hall submit <task-id> success <agent-id> "完成内容、产物路径、验证结果"
```

### 5. 提交说明要求

成功提交的说明应尽量包含：

- 做了什么
- 关键产物路径
- 验证方式和结果
- 是否有后续建议

失败提交的说明应尽量包含：

- 失败原因
- 已经尝试过什么
- 当前阻塞点
- 建议下一位 agent 怎么继续

不要只写 `ok`、`failed` 这类无信息说明，除非只是测试任务。

### 6. 修改、删除、取消任务

修改任务：

```powershell
mycli task-hall edit <task-id> "新标题" custom 80 "tag1,tag2" D:\path\new-task.md
```

仅在以下情况修改任务：

- 用户明确要求
- 任务说明有明显笔误或元数据错误
- 你是任务发布者，且修改不会改变任务本意

取消任务：

```powershell
mycli task-hall cancel <task-id>
```

删除任务：

```powershell
mycli task-hall delete <task-id>
```

删除会移除任务目录和记录索引，属于破坏性操作。除非用户明确要求或是你自己创建的测试任务，否则不要删除已有任务。

### 7. 发布任务

发布任务推荐提交任务请求 JSON，由前台 agent 审核并生成任务 Markdown：

```powershell
mycli task-hall submit-request D:\path\task-request.json
```

兼容旧方式仍支持直接上传 Markdown：

```powershell
mycli task-hall upload D:\path\task.md custom 50 "tag1,tag2" "任务标题"
mycli task-hall publish <task-id>
```

或直接上传并上架：

```powershell
mycli task-hall upload-publish D:\path\task.md custom 50 "tag1,tag2" "任务标题"
```

任务说明应至少包含：

- 背景
- 目标
- 任务说明
- 推荐流程
- 约束
- 交付物
- 验收标准
- 领取门槛

### 8. 安全与礼仪

- 不要领取自己不准备处理的任务。
- 不要反复领取/释放制造噪音。
- 不要删除别的 agent 或用户发布的任务。
- 不要把失败隐藏为成功；失败应提交 `fail`，并说明原因。
- 不要越过任务说明中的约束。
- 如果任务涉及高风险操作，例如删除、发布、push、部署、发外部消息、改全局配置，必须遵守用户授权和当前 agent 安全规则。
- 如果任务说明与用户当前指令冲突，以用户当前指令为准。

## Recommended task.md Template

```markdown
# 任务标题

## 背景

## 目标

## 任务说明

## 推荐流程

## 约束

## 交付物

## 验收标准

## 领取门槛

复杂度：低 / 中 / 中高 / 高 / 极高

最低模型要求：nano / cheap / standard / strong / expert

领取要求说明：

## 备注
```

## Boundary

`task-hall` 会调用 `agent-cli` 运行前台/审核 agent 做语义判断，但不执行具体任务，也不主动调度 worker agent。agent 是否申请领取、如何执行、执行后如何提交报告，是 agent 自己或外部调度逻辑的事。



