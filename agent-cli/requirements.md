# agent-cli Requirements

## 1. 文档目的

这份文档用于讨论并收敛 `D:\agent_workspace\capability-library\mycli\agent-cli` 的第一版需求。

目标不是先把实现写死，而是先明确：

- 这个 `agent-cli` 到底要解决什么问题
- 它和现有 `codex`、`opencode` 的关系是什么
- 它在 `mycli` 体系里应该长成什么样
- 第一版做什么，不做什么

---

## 2. 背景

当前本地已经至少存在两类可用 coding agent CLI：

- `codex`
- `opencode`

它们都能完成一部分“代码代理”工作，但使用入口、参数风格、能力暴露方式、适用场景并不完全一致。

现在希望新增一个统一入口：

- `agent-cli`

它的职责不是替代底层 agent，而是：

- 统一发现
- 统一说明
- 统一路由
- 统一常见工作流入口

也就是说，`agent-cli` 更像“本地 agent 调度与包装层”，而不是重新实现一个新的模型代理。

---

## 3. 当前已确认方向

当前已经确认的方向：

1. 第一版先做统一的 `agent-cli`
2. 第一版只整合两个来源：
   - `codex`
   - `opencode`

补充约束：

- agent-cli 对外名字保留来源前缀
- `codex` 可以视作一个单独 agent
- `opencode` 不是一个单独 agent
- `opencode` 更像一个 agent 容器 / agent 来源
- `opencode` 内部的多个 agent 需要映射到 `agent-cli`
- 默认 agent 第一版先设为 `opencode/private-assistant`
- 默认 agent 后续允许配置
- `opencode` agents 默认自动同步，不手工挑选
- `workflow` 以后再做
- 但结构上要预留 workflow 入口，避免后续推翻命令设计

---

## 4. 核心目标

第一版希望实现这些目标：

1. 用一个统一入口暴露本地 agent 能力
2. 在统一入口下接入：
   - `codex` 单 agent
   - `opencode` 提供的多个 agent
3. 让用户能先看说明，再选 agent，再执行
4. 保留原生透传能力，避免包装层限制底层 CLI
5. 为后续 workflow 和 route/recommend 预留空间
6. 支持创建新 agent，并显式指定来源
7. 能在 `mycli` 体系中被注册、发现、帮助、执行

---

## 5. 非目标

第一版暂时不追求：

- 自己实现新的大模型协议层
- 完整抽象掉 `codex` 和 `opencode` 的所有差异
- 自动判断所有任务都该走哪个 agent
- 统一所有底层参数语义
- 取代原生命令本身
- 正式实现 workflow 执行层

换句话说，第一版更像：

- 一个统一 agent 命令中枢

而不是：

- 一个完全独立的新 agent runtime

---

## 6. 预期定位

建议把 `agent-cli` 定位成三层结构：

### 第一层：发现与说明层

用户可以快速知道：

- 当前支持哪些 agent
- 每个 agent 擅长什么
- 当前默认 agent 是谁
- 每个 agent 来自哪里
- 什么时候该用 `codex`
- 什么时候该用某个 `opencode` agent

### 第二层：统一执行层

用户可以通过统一入口运行：

- 指定 agent 的原生命令
- 指定 agent 的统一执行动作
- 指定 agent 的常用工作流

### 第三层：工作流包装层

对常见任务给出统一入口，例如：

- 代码解释
- 代码修改
- review
- 修 bug
- 需求实现

这层不一定完全屏蔽底层差异，但要尽量把常见动作收敛成易理解的命令。

当前说明：

- 这一层先不正式实现
- 但命令结构需要为它预留位置
- 这样后续加入 workflow 时，不需要破坏现有 `agent-cli` 入口

---

## 7. 建议的包定位

在 `mycli` 中建议表现为一个 package：

```powershell
mycli agent-cli --help
mycli agent-cli list
```

包内可能包含：

- 直接命令
- 子包

建议至少考虑下面这两种结构之一。

### 方案 A：扁平包

```powershell
mycli agent-cli list
mycli agent-cli agents
mycli agent-cli route <task>
mycli agent-cli codex ...
mycli agent-cli opencode ...
```

### 方案 B：统一 agent 结构

```powershell
mycli agent-cli list
mycli agent-cli agent list
mycli agent-cli agent show codex
mycli agent-cli agent show <opencode-agent>
mycli agent-cli agent use codex
mycli agent-cli agent use <opencode-agent>
mycli agent-cli current
mycli agent-cli native --agent codex ...
mycli agent-cli native --agent <opencode-agent> ...
mycli agent-cli workflow list
mycli agent-cli route explain "..."
```

结合当前决策，现在更推荐方案 B，因为它更符合：

- `agent-cli` 是统一入口
- `codex` 是其中一个 agent
- `opencode` 是 agent 来源，而不是单个 agent
- 后续要加 workflow 时也不用再推翻命令结构

---

## 8. 第一版建议能力范围

第一版建议至少包含 4 类能力。

### 7.1 agent 发现

例如：

```powershell
mycli agent-cli list
mycli agent-cli agents
mycli agent-cli agent list
```

输出内容建议包括：

- agent 名称
- 一句话简介
- 适用场景
- 来源
- 原生入口
- 是否为当前默认 agent

### 7.2 agent 选择与帮助

例如：

```powershell
mycli agent-cli agent show codex
mycli agent-cli agent show <opencode-agent>
mycli agent-cli current
```

帮助内容应该回答：

- 这个 agent 擅长什么
- 常用命令有哪些
- 与另一种 agent 的区别是什么
- 当前默认 agent 是否是它

建议补一个默认 agent 选择入口，例如：

```powershell
mycli agent-cli agent use codex
mycli agent-cli agent use <opencode-agent>
```

### 7.3 原生透传

例如：

```powershell
mycli agent-cli native --agent codex ...
mycli agent-cli native --agent <opencode-agent> ...
mycli agent-cli native ...
```

这一层非常重要，因为它保证：

- 包装层不阻塞底层能力
- 新功能上线时不必等 `agent-cli` 先适配

其中：

- 显式指定 `--agent` 时，直接走对应 agent
- 未指定 `--agent` 时，走当前默认 agent

### 8.4 workflow 预留入口

例如：

```powershell
mycli agent-cli workflow explain --agent codex --prompt "..."
mycli agent-cli workflow patch --agent opencode --prompt "..."
mycli agent-cli workflow review --agent codex --prompt "..."
```

或者更简化：

```powershell
mycli agent-cli explain --agent codex "..."
mycli agent-cli patch --agent opencode "..."
mycli agent-cli review --agent codex "..."
```

这一块需要后续重点讨论。

当前建议：

- 第一版可以让 `workflow` 出现在帮助文档和结构设计里
- 但先不实现真实 workflow 命令逻辑
- 或者只返回“预留入口，暂未实现”的提示

这样可以提前锁定命名空间：

```powershell
mycli agent-cli workflow --help
```

---

## 9. Codex 与 OpenCode 的整合思路

当前建议不要把两者“硬融合”为一个假装完全一致的接口，而应该采用：

- 统一入口
- agent 抽象
- 明确差异
- 适度包装
- 保留原生

这里需要明确区分两层对象：

### 来源层

- `codex`
- `opencode`

### agent 层

- `codex` 自身可视为一个 agent
- `opencode` 下面会有多个 agent
- `agent-cli` 最终面向用户暴露的是 agent 层，不是单纯来源层

建议先把二者抽象成：

```text
Agent
  - name
  - summary
  - source
  - upstreamAgentName
  - displayName
  - strengths
  - native entry
  - isDefault
  - mode
  - common workflows
  - passthrough mode
```

然后每个 agent 各自维护：

- 自己的说明
- 自己的来源
- 自己对应的上游 agent 标识
- 自己的原生透传命令
- 自己的常用 workflow 映射

这样做的好处是：

- 后续可以继续加入 `harness`、`claude-code`、`openclaw`
- 不需要一开始就做一个过度抽象的统一协议

---

## 10. 映射模型建议

当前建议把 `agent-cli` 的核心注册对象定义为“映射后的 agent”，而不是直接把来源当成 agent。

例如：

```text
MappedAgent
  - name                  # agent-cli 对外统一名字，保留来源前缀
  - source                # codex | opencode
  - upstreamAgentName     # 上游真实 agent 名
  - displayName           # 给 list/show 用的人类可读名称
  - summary
  - strengths
  - nativeEntry
  - nativeArgsTemplate
  - isDefault
  - mode                  # primary | subagent | all
```

可以这样理解：

- `codex` 来源目前可能只映射出一个 agent：`codex`
- `opencode` 来源可能映射出多个 agent，例如：
  - `opencode/build`
  - `opencode/general`
  - `opencode/explore`
  - `opencode/private-assistant`

当前建议：

- 对外名称保留来源前缀
- 推荐采用 `/` 风格，例如：
  - `codex/default`
  - `opencode/build`
  - `opencode/private-assistant`

也可以讨论是否让 `codex` 简写为 `codex`，但如果追求绝对对称，`codex/default` 更整齐。

也就是说，第一版不是：

- `agent-cli = codex + opencode`

而更像：

- `agent-cli = codex-agent + opencode-agent-a + opencode-agent-b + ...`

---

## 11. 建议的命令方向

下面是一组建议讨论的命令草案，不代表最终定稿。

### 顶层

```powershell
mycli agent-cli --help
mycli agent-cli list
mycli agent-cli agents
mycli agent-cli current
mycli agent-cli sync
mycli agent-cli recommend <task text>
```

### agent 管理

```powershell
mycli agent-cli agent list
mycli agent-cli agent show codex/default
mycli agent-cli agent show opencode/private-assistant
mycli agent-cli agent use codex/default
mycli agent-cli agent use opencode/private-assistant
mycli agent-cli source list
mycli agent-cli source show opencode
```

### 执行入口

```powershell
mycli agent-cli native --agent codex/default ...
mycli agent-cli native --agent opencode/private-assistant ...
mycli agent-cli native ...
```

### workflow 子包

```powershell
mycli agent-cli workflow list
mycli agent-cli workflow explain --agent codex --prompt "..."
mycli agent-cli workflow implement --agent opencode --prompt "..."
mycli agent-cli workflow review --agent codex --prompt "..."
```

当前约束：

- 这些命令先作为未来规划保留
- 第一版不要求真的全部落地
- 但要避免未来命令名冲突

### route / recommend

```powershell
mycli agent-cli recommend "帮我 review 一个 Python 仓库"
mycli agent-cli recommend "帮我快速改一个前端页面"
```

这一类命令先只做规则推荐，不一定自动执行。

---

## 12. 第一版输入输出原则

建议遵循这些原则：

1. 先能说明白，再追求自动化
2. 先能稳定透传，再做高级工作流
3. 允许显式选 agent，也允许设置默认 agent
4. 默认保留来源前缀，避免歧义
5. 文档优先于魔法

也就是说，第一版应优先保证：

- 用户知道自己在调用谁
- 用户知道参数最终传给谁
- 用户知道这层包装新增了什么价值
- 用户知道当前默认 agent 是谁
- 用户知道该 agent 来自 `codex` 还是 `opencode`

---

## 13. 统一 session 与执行模型

当前新增需求：

- 所有 `agent-cli` 对外 agent 命令都尽量统一成同一套执行模型
- 重点统一这些能力：
  - 创建新 session
  - 继续已有 session
  - session 命名
  - 指定模型
  - 指定 agent
  - 指定工作目录

建议把 `agent-cli` 对外执行入口理解成“统一 session 层”，底层再映射到 `codex` 或 `opencode`。

### 13.1 建议统一参数

例如：

```powershell
mycli agent-cli run --agent opencode/private-assistant --model openai/gpt-5.4 --session_name "repo-review" --prompt "review this repo"
mycli agent-cli run --agent codex/default --model gpt-5.4 --session_name "bugfix-1" --prompt "fix failing tests"
```

建议统一参数至少包括：

- `--agent`
- `--model`
- `--session_name`
- `--prompt`
- `--cwd`
- `--continue`
- `--session`
- `--fork`

### 13.2 新 session

默认行为建议是：

- 不传 `--continue` / `--session` 时，创建新 session

### 13.3 session 命名

建议 `agent-cli` 对外统一使用：

- `--session_name`

然后再映射到底层：

- `opencode`：已有 `--title`
- `codex`：当前没有明确等价的 `--name` 参数，需要评估：
  - 是否通过 prompt/context 间接表达
  - 是否只在 `agent-cli` 自己的 session 元数据里记录

使用 `--session_name` 而不是 `--name` 的原因：

- 语义更明确
- 避免和 agent 名称、profile 名称、来源名称混淆
- 方便后续扩展更多命名参数

### 13.4 agent 映射

建议：

- `agent-cli` 的 `--agent` 是统一入口
- 底层映射时：
  - `opencode/*` -> `opencode run --agent <upstreamAgentName>`
  - `codex/default` -> `codex` 或 `codex exec` 对应路径

### 13.5 模型映射

两边都已有 `--model`，所以统一成本较低：

- `codex`: `--model`
- `opencode`: `--model`

### 13.6 继续 session

两边都支持 continue / session，只是参数形式略有差异：

- `codex`
  - `resume`
  - `--last`
- `opencode`
  - `run --continue`
  - `run --session`

所以 `agent-cli` 需要定义自己的统一 session 语义，再分别下沉映射。

---

## 14. 第一版统一参数规则草案

下面这部分把 `agent-cli run` 的统一参数规则收敛成一版可讨论的命令规格。

### 14.1 参数清单

第一版建议统一支持：

- `--agent`
- `--model`
- `--session_name`
- `--prompt`
- `--cwd`
- `--continue`
- `--session`
- `--fork`

后续可选参数先不纳入第一版强制统一范围，例如：

- provider 级参数
- sandbox/approval 级参数
- 输出格式参数
- 附件参数

这些可以等基础 session 层稳定后再扩展。

### 14.2 参数含义

`--agent`

- 指定要调用的映射后 agent
- 示例：
  - `codex/default`
  - `opencode/private-assistant`
  - `opencode/build`

`--model`

- 指定底层使用的模型
- 若不传，则使用来源侧默认模型或用户默认配置

`--session_name`

- 给本次 session 指定一个可读名称
- 主要用于：
  - 列表展示
  - 恢复时识别
  - 本地 session 元数据记录

`--prompt`

- 本次运行的自然语言任务输入
- 对新 session 来说是首条任务
- 对 continue / session 来说可视为追加任务

`--cwd`

- 指定工作目录
- 若不传，默认使用当前目录

`--continue`

- 表示继续最近一次 session
- 不指定具体 session id

`--session`

- 表示继续某个明确指定的 session
- 值为 session id 或 agent-cli 自己定义的统一 session 标识

`--fork`

- 表示基于既有 session 分叉出一个新 session
- 不在原 session 上直接续写

### 14.3 默认行为

建议默认行为如下：

1. 未传 `--continue` 且未传 `--session`
   - 创建新 session
2. 传了 `--continue`
   - 继续最近 session
3. 传了 `--session`
   - 继续指定 session
4. 传了 `--fork`
   - 从目标 session 分叉，而不是原地继续

### 14.4 参数约束

建议第一版采用这些约束：

1. `--continue` 与 `--session` 互斥
2. `--fork` 只能和 `--continue` 或 `--session` 一起使用
3. 新 session 场景下，建议允许不传 `--prompt`
   - 这样可以进入对应底层 agent 的交互模式
4. 若传 `--session_name` 且是 continue 场景
   - 第一版建议先不修改旧 session 名
   - 如有需要，后续单独设计 rename 能力

### 14.5 是否必须显式传 `--agent`

建议规则：

1. 传了 `--agent`
   - 就使用显式指定 agent
2. 没传 `--agent`
   - 就使用当前默认 agent
3. 如果当前没有默认 agent
   - 报错并提示先 `agent use ...` 或显式传 `--agent`

### 14.6 是否必须传 `--prompt`

建议规则：

1. 新 session：
   - `--prompt` 可选
   - 不传时进入交互式运行
2. continue / session：
   - `--prompt` 也可选
   - 不传时仅恢复会话
   - 传了则在恢复后追加新任务

### 14.7 session_name 的统一语义

建议 `--session_name` 仅定义为 `agent-cli` 自己的统一会话名字段。

然后分别映射：

- `opencode`
  - 直接映射到 `--title`
- `codex`
  - 先存入 `agent-cli` 本地 session 元数据
  - 必要时再考虑是否注入到 prompt/context

这样做的好处是：

- 不必强行要求 `codex` 和 `opencode` 完全同构
- 先把统一体验建立起来
- 后续还可以继续增强底层映射

### 14.8 统一命令示例

新 session：

```powershell
mycli agent-cli run --agent opencode/private-assistant --model openai/gpt-5.4 --session_name "repo-review" --prompt "review this repo"
```

继续最近 session：

```powershell
mycli agent-cli run --continue --prompt "continue and summarize progress"
```

继续指定 session：

```powershell
mycli agent-cli run --session sess_001 --prompt "apply the fix now"
```

分叉 session：

```powershell
mycli agent-cli run --session sess_001 --fork --session_name "alt-fix" --prompt "try a safer implementation"
```

---

## 15. agent 创建能力

除了“运行已有 agent”，`agent-cli` 还需要支持“创建新 agent”。

### 15.1 目标

希望用户可以通过统一入口创建一个新 agent，并显式指定它属于哪个来源。

例如：

```powershell
mycli agent-cli agent create --source opencode --name my-agent --description "..."
mycli agent-cli agent create --source codex --name my-agent --description "..."
```

### 15.2 第一版边界

当前已知约束：

- `opencode` 支持 `opencode agent create`
- `codex` 当前暂不支持类似的 agent create 能力

所以第一版建议：

- `agent-cli` 对外可以提供统一的 `agent create`
- 但按 source 做能力分流

具体行为建议：

1. `--source opencode`
   - 允许创建
   - 映射到底层 `opencode agent create`
2. `--source codex`
   - 明确返回“不支持”
   - 不做伪实现

### 15.3 建议参数

第一版建议 `agent create` 至少支持：

- `--source`
- `--name`
- `--description`
- `--mode`
- `--tools`

其中：

`--source`

- 指定在哪个来源下创建 agent
- 第一版至少支持：
  - `opencode`
  - `codex`

`--name`

- 新 agent 名称
- 对 `opencode`，最终用于生成对应 agent 文件或注册项

`--description`

- 对 agent 的职责说明
- 对 `opencode`，可直接映射到底层 `--description`

`--mode`

- agent mode
- 当前从 `opencode agent create --help` 可见支持：
  - `all`
  - `primary`
  - `subagent`

`--tools`

- agent 可启用的工具列表
- 对 `opencode` 可映射到底层 `--tools`

### 15.4 第一版建议语义

建议统一命令形态：

```powershell
mycli agent-cli agent create --source opencode --name my-agent --description "Repository maintenance agent" --mode primary --tools bash,read,edit
```

若用户传：

```powershell
mycli agent-cli agent create --source codex ...
```

则返回明确提示，例如：

```text
Source 'codex' does not support agent creation yet.
```

### 15.5 与映射层的关系

agent 创建完成后，`agent-cli` 需要考虑两件事：

1. 是否立即触发同步
2. 新 agent 的对外映射名是什么

当前建议：

- `--source opencode` 创建成功后，自动触发一次同步
- 新 agent 自动进入映射清单
- 命名遵循统一前缀规则，例如：
  - `opencode/my-agent`

---

## 16. 本机 CLI 能力观察

当前本机观察到：

### 14.1 codex

- `codex --help` 支持交互模式和子命令模式
- 非交互执行主要是：
  - `codex exec`
  - `codex review`
- session 相关主要是：
  - `codex resume`
  - `codex fork`
- 通用参数包括：
  - `--model`
  - `--cd`
  - `--profile`
  - `--sandbox`
  - `--full-auto`

### 14.2 opencode

- `opencode run` 是统一执行入口
- `opencode run` 已支持：
  - `--model`
  - `--agent`
  - `--continue`
  - `--session`
  - `--fork`
  - `--title`
  - `--dir`
- `opencode session list` / `delete` 可做 session 管理

结论：

- `opencode` 更接近“原生支持多 agent + session 参数统一”的结构
- `codex` 更像“单 agent 主 CLI + exec/resume/fork 子命令”结构
- 所以 `agent-cli` 的统一层会更像：
  - 对 `opencode` 做轻映射
  - 对 `codex` 做适配包装

---

## 17. 当前建议的分阶段实现

### Phase 1：可发现、可透传

先完成：

- `agent-cli` 包注册
- 来源注册清单
- agent 映射清单
- `codex` agent 接入
- `opencode` agents 接入
- `native` 透传
- 统一 `run` 参数层
- `agent create --source ...`
- 默认 agent 选择
- 自动同步
- 帮助文档
- agent 对比说明
- workflow 入口预留

### Phase 2：常用 workflow 包装

再补：

- `explain`
- `implement`
- `review`
- `fix`

每个 workflow 明确：

- 默认推荐 agent
- 可切换 agent
- prompt 模板

### Phase 3：推荐与路由

最后再考虑：

- `recommend`
- 简单规则路由
- 根据任务类型建议走 `codex` 还是 `opencode`

---

## 18. 待讨论问题

下面这些问题需要后续讨论拍板。

### 18.1 `agent-cli` 是不是只整合 `codex` 和 `opencode`

候选答案：

- 第一版只做这两个
- 结构上允许以后扩展更多 agent

当前结论：

- 第一版只做这两个
- 文档和结构保留以后继续扩展的余地

### 18.2 `opencode` 的 agent 列表从哪里来

候选方向：

- 手工静态登记
- 从 `opencode` 配置或命令动态发现
- 先静态登记，后续再做动态发现

当前建议：

- 第一版默认全量接入 `opencode` 当前可发现的 agent
- 第一版优先尝试同步发现，而不是手工挑选少数 agent
- `agent-cli` 的职责是做映射层，不主动替用户删减 agent 集合

当前本机通过 `opencode agent list` 观察到的 agent 包括：

- `build`
- `compaction`
- `explore`
- `general`
- `plan`
- `summary`
- `title`
- `洛璃`
- `agent-creator`
- `novelist`
- `private-assistant`
- `tool-registrant`

补充观察：

- 这些 agent 还带有 mode 信息，例如：
  - `primary`
  - `subagent`
  - `all`
- 说明 `opencode` 的 agent 体系比“单一 agent 名称列表”更丰富
- 所以 `agent-cli` 不应该把 `opencode` 粗暴等同成一个 agent

当前建议的第一版策略：

- 默认全部映射
- 优先尝试通过 `opencode agent list` 做同步
- 如果同步失败，再考虑回退到缓存或静态清单
- `MappedAgent` 里建议保留 `mode` 字段，避免丢失上游语义

进一步建议：

- `agent-cli` 启动或执行 `agent list` 时，可以主动同步一次 `opencode` agent 清单
- 同步结果落地为本地映射缓存
- 映射层只负责：
  - 统一命名
  - 补充说明
  - 记录来源
  - 转发调用

而不负责裁剪上游 agent 列表

### 18.3 `agent-cli` 对外名字是否要和上游 agent 名完全一致

候选方向：

- 完全沿用上游名称
- 做统一命名映射

当前结论：

- 保留来源前缀
- 允许对上游 agent 名做轻度映射
- 当前倾向采用：
  - `codex/default`
  - `opencode/<upstreamAgentName>`

### 18.4 默认 agent 是否需要持久化

候选方向：

- 只在本次命令里用 `--agent`
- 允许 `agent use <name>` 持久化默认 agent

当前倾向：

- 支持持久化默认 agent
- 因为统一入口的价值之一就是减少重复选型

### 18.5 `sync` 是否显式提供为命令

当前倾向：

- 提供显式 `mycli agent-cli sync`
- 同时在 `agent list` 等关键命令里自动触发同步

### 18.6 `codex` 的 session name 如何处理

因为 `codex` 当前没有像 `opencode --title` 这样直接的 session 标题参数，所以需要进一步决定：

- 是否只在 `agent-cli` 本地记录 `--name`
- 是否把 `--name` 作为 prompt/context 的附加信息传给 `codex`
- 是否接受 `codex` 和 `opencode` 在 session naming 上不完全对齐

### 18.7 `agent create` 是否必须统一成功语义

当前已知会出现来源能力不一致：

- `opencode` 支持创建
- `codex` 暂不支持创建

所以需要决定：

- 是否允许某些 source 明确返回“不支持”
- 还是要等所有 source 都支持后再暴露统一 create 命令

当前建议：

- 允许来源能力不一致
- 只要错误提示清楚即可

### 18.8 workflow 是不是顶层直达

两种候选：

- `mycli agent-cli explain --agent codex "..."`  
- `mycli agent-cli workflow explain --agent codex --prompt "..."`

### 18.9 recommend 只建议，还是可以自动执行

第一版更建议：

- 只做建议，不直接执行

### 18.10 是否要统一 session 概念

例如：

- 是否支持恢复 Codex / OpenCode 各自会话
- 是否要在 `agent-cli` 层做统一 session 抽象

第一版建议先不做。

### 18.11 是否要统一配置

例如：

- 默认 agent
- 默认 workflow agent 映射
- 常用 prompt 模板

这一块可以做，但不一定是第一版必须项。

---

## 19. 当前建议的最小可行版本

如果只做 MVP，建议是：

1. `agent-cli` 成为 `mycli` 下的一个正式 package
2. 接入两个来源：
   - `codex`
   - `opencode`
3. 对外暴露映射后的 agent 列表，而不是把来源直接当 agent
4. 至少提供：
   - `agent list`
   - `agent show <name>`
   - `agent use <name>`
   - `agent create --source <name> ...`
   - `current`
   - `sync`
   - `run`
   - `native [--agent <name>] ...`
   - `source list`
   - `source show <name>`
5. 预留 `workflow` 命名空间或帮助入口，但暂不正式实现
6. 暂时不做复杂自动路由
7. 顶层提供：
   - `list`
   - `agents`
   - `recommend`

---

## 20. 下一步建议讨论顺序

建议按这个顺序继续收敛：

1. 先定 `codex` 和 `opencode` 的“来源层 / agent 层”模型
2. 再定统一命名规则：
   - `codex/default`
   - `opencode/<agent>`
3. 再定统一 `run` 参数模型和 session 语义
4. 再定 `agent create --source ...` 的参数和错误语义
5. 再定 `sync` 的触发方式和缓存格式
6. 再定 `workflow` 入口怎么预留
7. 最后定是否需要 `recommend`

---

## 21. 新增：OpenCode 输出模式与事件流回放

基于当前实际使用反馈，`agent-cli` 新增一个优先级很高的目标：

- 解决其他 agent 调用 `agent-cli` 时，OpenCode 事件流持续输出导致上下文被大量占用的问题

因此，当前收敛后的要求是：

### 21.1 范围

第一版先只要求对 `opencode/*` 做结构化支持：

- `codex` 先不纳入这次输出模式改造重点
- 先把 OpenCode 跑顺、可调试、可回放

### 21.2 统一返回模式

`mycli agent-cli run` 对 OpenCode 新增显式参数：

- `--return_mode stream`
- `--return_mode silent`

不再采用自动混合模式。

其中：

#### `stream`

- 终端持续输出 OpenCode JSON 事件流
- 用于调试
- 重点观察：
  - `sessionID`
  - `step_start`
  - `tool_use`
  - `text`
  - `step_finish`
  - `invalid`
  - `JSON parsing failed`
  - `write / edit / read`
  - tool-output 补全线索

#### `silent`

- 终端不输出中间事件流
- 最终只输出：
  - `sessionID`
  - 必要时 round 信息
  - agent 最终汇报
- 主要目标是：
  - 给其他 agent 调用时避免刷爆上下文
  - 提高结果消费效率

### 21.3 silent 不是不记录

`silent` 模式下，必须仍然：

- 完整采集 OpenCode JSON 事件
- 保存原始流
- 保存最终报告
- 保存 run 元数据

也就是说：

- `stream` = 记录 + 实时展示
- `silent` = 记录 + 不实时展示

### 21.4 session / round 回放能力

新增一个事后查看执行过程的能力。

建议语义：

- 一个 `agent-cli run` 调用对应一个 `round`
- 一个 OpenCode `session` 下可以累积多个 round

建议支持：

```powershell
mycli agent-cli session events --session <sessionID> --last 1
mycli agent-cli session events --session <sessionID> --last 3
mycli agent-cli session events --session <sessionID> --round 2
mycli agent-cli session events --session <sessionID> --all
```

含义：

- `--last 1`
  - 返回该 session 最近一轮的事件流
- `--last 3`
  - 返回最近三轮
- `--round 2`
  - 返回第 2 轮
- `--all`
  - 返回该 session 的全部已记录轮次

### 21.5 设计原则

调试原则仍然保持：

- 不只信 agent 最终汇报
- 调试时以事件流 + 文件状态 + 工具输出为依据

但在日常调用场景下，应优先允许：

- 运行时保持安静
- 需要时再回放事件

这套能力的本质不是界面美化，而是：

- 控制终端输出噪音
- 降低上层 agent 的上下文占用
- 同时保留事后可审计、可复盘的执行轨迹
