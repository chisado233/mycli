# novel-writing agent 当前进度记录

记录时间：2026-05-08

## 总体目标

为 `mycli novel-writing` 搭建一套小说写作专用 agent 层。它不直接使用 opencode agent loop，而是用 JSON 请求驱动专用流程；底层模型调用统一走 `mycli agent-cli llm-call`。

当前目标是形成：

```text
调度 agent 生成 JSON
  ↓
关联判断 agent 判断上下文与 YAML 关联字段
  ↓
runner 自动 apply-relations 写回目标 md YAML
  ↓
写作 agent 生成候选稿
  ↓
小说编辑 agent 提供修改建议
  ↓
状态更新 agent 提供状态追踪更新建议
```

## 已落地模块

### 1. mycli 包结构

已建立并注册：

- `mycli novel-writing`
- `mycli novel-writing agent`
- `mycli novel-writing project`
- `mycli novel-writing material-library`
- `mycli novel-writing writing-skill-library`
- `mycli novel-writing collector`
- `mycli novel-writing deconstruction`

agent 子包位置：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\agent
```

### 2. 小说项目模板

项目模板位置：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\project\templates\小说项目模板
```

已形成的核心目录包括：

- `00-项目总览/`
- `01-作品企划/`
- `02-世界观/`
- `03-故事背景/`
- `04-角色/`
- `05-大纲/`
- `06-明线暗线伏笔/`
- `06A-状态追踪/`
- `07-章节正文/`
- `08-审核与修订/`
- `09-素材引用/`
- `10-生成记录/`
- `11-调度与生成/`

关键设计：

- 小说项目不用通用 `project-manager`；一个小说项目就是一个项目文件夹。
- 所有关键内容尽量拆为细粒度 Markdown。
- 正文生成采用候选稿机制，不直接覆盖定稿。
- 大纲、章节、角色、势力等文件顶部使用 YAML 存机器可读关联信息。

### 3. 素材图书馆

素材库位置：

```text
D:\agent_workspace\capability-library\skill-library\novel-writing\material-library
```

当前分类：

- `爽点/`
- `金句/`
- `梗/`
- `情感冲突/`
- `情感线发展/`

原则：只记录有复用和创作价值的素材，不收集泛泛资料。每条素材使用 Markdown + YAML tag。

### 4. agent 设计文档与提示词

agent 设计文档：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\agent\agents
```

已包含：

- `调度agent.md`
- `关联判断agent.md`
- `写作agent.md`
- `小说编辑agent.md`
- `状态更新agent.md`

提示词模板：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\agent\prompts
```

已包含同名 prompt 文件。

职责边界：

- 调度 agent：只负责输出 JSON 调度，不写正文。
- 关联判断 agent：只判断上下文和关联 YAML，不写正文。
- 写作 agent：负责生成指定内容或候选稿。
- 小说编辑 agent：只给编辑意见、修改建议和问题检查。
- 状态更新 agent：给人物/势力/伏笔/章节状态更新建议。

## 当前 runner 能力

核心文件：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\agent\novel_agent_runner.py
```

当前命令：

```powershell
mycli novel-writing agent build-prompt <request.json>
mycli novel-writing agent run <request.json>
mycli novel-writing agent collect-context <request.json>
mycli novel-writing agent apply-relations <relation.json>
```

### build-prompt

根据 JSON 请求组装提示词：

- 读取 `agent` / `task_type` / `target`
- 读取 `system_prompt` / `user_prompt`
- 拼入 `context_files` 指定 Markdown 全文
- 第一版全部传全文，不做摘要
- 输出提示词 Markdown

### collect-context

用于测试和展示自动关联展开结果。

当 `context_files` 中某个文件设置：

```json
{ "relate": true }
```

或：

```json
{ "关联": true }
```

runner 会读取目标文件 YAML frontmatter，并根据下列字段展开上下文：

- `相关人物`
- `相关势力`
- `相关素材`
- `相关伏笔`
- `一次关联人物`
- `一次关联势力`
- `前置文件`
- `后续文件`

当前只自动展开一层一次关联，二次关联默认不展开。

### apply-relations

根据关联判断 JSON 把 `写入YAML` 合并进目标 Markdown 的 YAML frontmatter。

输入 JSON 关键字段：

```json
{
  "项目路径": "D:\\path\\to\\novel-project",
  "目标文件": "05-大纲/01-第一卷/章节细纲/第001章.md",
  "写入YAML": {
    "相关人物": ["沈青玄"],
    "相关势力": ["青云宗"]
  }
}
```

行为：

- 相对路径基于 `项目路径` 解析。
- 合并已有 YAML 值。
- 自动去重。
- 支持 `--dry-run`。
- 现在支持宽松解析：如果模型输出前后有说明文字，也会尝试提取其中 `{ ... }` JSON 块。

### run

根据 JSON 请求：

1. 生成提示词。
2. 调用：

```powershell
mycli agent-cli llm-call --model <model> --prompt-file <prompt.md> --out <output>
```

3. 留存：
   - `提示词.md`
   - `输出.md`
   - `run.json`

默认输出目录：

```text
<小说项目>\11-调度与生成\agent-runs\<timestamp>\
```

## 最新完成：关联判断自动写回

已经实现：当 request JSON 的 `agent` 或 `task_type` 包含“关联判断”时，`run` 会在模型输出成功后自动执行关系写回。

控制字段：

```json
{
  "agent": "关联判断agent",
  "task_type": "关联判断",
  "auto_apply_relations": true,
  "自动应用关联": true
}
```

默认行为：

- `auto_apply_relations` 默认为 `true`。
- 如需关闭，显式设为 `false`。

自动写回流程：

1. 读取模型输出文件。
2. 宽松解析 JSON。
3. 读取 `项目路径`、`目标文件`、`写入YAML`。
4. 调用内部 `apply_relations_payload`。
5. 写入目标 md YAML frontmatter。
6. 输出 `输出.apply-result.json`。
7. 在 `run.json` 写入 `auto_apply_relations` 执行结果。

相关示例：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\agent\examples\relation-request.example.json
D:\agent_workspace\capability-library\mycli\novel-writing\agent\examples\relation-result.example.json
```

## 已验证内容

### 1. agent 子包基础命令

已验证：

```powershell
mycli novel-writing agent list
mycli novel-writing agent prompts
mycli novel-writing agent prompt 关联判断agent
```

### 2. build-prompt

已验证可以根据 request JSON 生成提示词。

测试目录：

```text
D:\agent_workspace\tmp\novel-agent-test
```

### 3. collect-context

已验证 `relate: true` 可以根据 YAML 关联字段自动展开上下文。

测试目录：

```text
D:\agent_workspace\tmp\novel-agent-relate-test
```

### 4. apply-relations

已验证可以把关联 JSON 的 `写入YAML` 合并到目标 Markdown YAML，并保留旧值、自动去重。

测试目录：

```text
D:\agent_workspace\tmp\novel-agent-apply-test
```

### 5. 宽松 JSON + 自动写回相关逻辑

已使用本地假模型输出验证。

测试目录：

```text
D:\agent_workspace\tmp\novel-agent-auto-apply-test
```

测试输入输出：

- 输入：`output.md`，包含 JSON 前后说明文字。
- 目标：`project\05-大纲\01-第一卷\章节细纲\第001章.md`
- 结果：`apply-result.json`

验证结果：

目标文件 YAML 从：

```yaml
相关人物: [旧人物]
相关势力: []
```

更新为：

```yaml
相关人物: [旧人物, 沈青玄]
相关势力: [青云宗]
```

### 6. Python 语法检查

已通过：

```powershell
python -m py_compile D:\agent_workspace\capability-library\mycli\novel-writing\agent\novel_agent_runner.py
```

## 当前尚未完成

1. 尚未实现完整 `agent-loop` 命令。
2. 调度 agent 目前只定义了职责与 JSON 输出方向，还没有 runner 解析调度 JSON 并连续调用多个 agent。
3. 写作 agent 生成候选稿的自动落盘逻辑尚未实现。
4. 小说编辑 agent 的建议输出尚未接入候选稿审核流程。
5. 状态更新 agent 目前只设计了职责，尚未实现自动更新或半自动建议应用。
6. 尚未真实调用模型完整跑一遍关联判断 `run`，目前自动 apply 逻辑用本地假输出验证通过。

## 下一步建议

优先做一个最小闭环：

```text
relation-request.json
  ↓
run 关联判断agent
  ↓
自动 apply-relations
  ↓
writing-request.json
  ↓
run 写作agent生成候选稿
```

然后再扩展：

1. 增加 `write-output` / `target_output` 字段，让写作 agent 输出自动保存到候选稿路径。
2. 增加 `agent-loop` 命令，读取调度 agent JSON，并按步骤执行。
3. 加入小说编辑 agent，对候选稿输出 `编辑建议.md`。
4. 加入状态更新 agent，输出状态变更建议 JSON 或 Markdown。
5. 最后再考虑半自动应用状态更新。
