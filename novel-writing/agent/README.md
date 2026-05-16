# novel-writing agent

## Summary

小说写作 agent 子包。用于封装小说写作专用 agent-loop、关联判断 agent、写作 agent、审核 agent 等提示词模板。各 agent 底层通过 `mycli agent-cli llm-call` 调用模型，但对外作为小说写作专用 agent 链路使用。

## Source

`D:\agent_workspace\capability-library\mycli\novel-writing\agent`

## Command List

- `open`
- `show`
- `prompts`
- `prompt <name>`
- `build-prompt <request.json>`
- `run <request.json>`
- `collect-context <request.json>`
- `apply-relations <relation.json>`

## Agent Design Docs

每个 agent 的逻辑讨论文档在：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\agent\agents
```

当前包括：

- `调度agent.md`
- `关联判断agent.md`
- `写作agent.md`
- `小说编辑agent.md`
- `状态更新agent.md`

## Usage Examples

```powershell
mycli novel-writing agent open
mycli novel-writing agent show
mycli novel-writing agent prompts
mycli novel-writing agent prompt 写作agent
mycli novel-writing agent build-prompt D:\path\request.json
mycli novel-writing agent run D:\path\request.json
mycli novel-writing agent collect-context D:\path\request.json
mycli novel-writing agent apply-relations D:\path\relation.json --dry-run
```

## JSON Request Format

```json
{
  "agent": "写作agent",
  "task_type": "章节细纲",
  "model": "MoreCode/gpt-5.4",
  "system_prompt": "你是小说写作系统的写作 agent。",
  "user_prompt": "请根据上下文生成第001章细纲。",
  "project": "D:\\agent_workspace\\projects\\novels\\示例小说",
  "context_files": [
    { "path": "01-作品企划/写作核心.md", "label": "写作核心" },
    { "path": "02-世界观/世界观总览.md", "label": "世界观总览" },
    { "path": "05-大纲/01-第一卷/章节细纲/第001章.md", "label": "第001章细纲", "relate": true }
  ]
}
```

`agent` 现在可以省略。省略时，runner 会优先从传入的 Markdown 系统提示词中推断 agent 名称：

1. 如果 Markdown 有 YAML front matter，优先读取 `name` / `agent` / `title`。
2. 否则读取第一个 Markdown 标题。
3. 都没有时使用 `自定义md提示词agent`。

系统提示词也不必写在 `system_prompt` 字段里。以下字段都可以作为系统提示词来源，按顺序取第一个非空值：

- `system_prompt` / `系统提示词`
- `prompt` / `提示词`
- `agent_prompt`
- `agent_md`
- `agent_markdown`
- `md_prompt`

也就是说，可以直接传入某个 agent 的 `.md`：

```json
{
  "task_type": "031-035章素材库分类拆书",
  "model": "MoreCode/gpt-5.5",
  "prompt": {
    "path": "D:\\agent_workspace\\capability-library\\mycli\\novel-writing\\prompts\\拆书\\agent\\03A-章节批量粗拆agent.md"
  },
  "user_prompt": "请对第31-35章进行素材库分类版高质量拆书。",
  "project": "D:\\agent_workspace\\capability-library\\mycli\\novel-writing\\deconstruction\\书名",
  "context_files": []
}
```

旧写法仍然兼容：

```json
{
  "agent": "拆书-素材库分类agent",
  "system_prompt": {
    "path": "D:\\agent_workspace\\capability-library\\mycli\\novel-writing\\prompts\\拆书\\agent\\03A-章节批量粗拆agent.md"
  }
}
```

`context_files` 中的 Markdown 文件会自动读取全文并拼入最终提示词。

如果某个文件设置 `"relate": true` 或 `"关联": true`，runner 会读取该文件 YAML frontmatter 中的 `相关人物`、`相关势力`、`相关素材`、`相关伏笔`、`一次关联人物`、`一次关联势力`、`前置文件`、`后续文件`，并自动展开加入上下文文件列表。

## 关联判断自动写回

当请求 JSON 的 `agent` 或 `task_type` 包含“关联判断”时，`run` 会在模型输出成功后尝试解析输出 JSON，并默认把其中的 `写入YAML` 合并写入 `目标文件` 的 YAML frontmatter。

可用字段控制这个行为：

```json
{
  "agent": "关联判断agent",
  "task_type": "关联判断",
  "auto_apply_relations": true,
  "自动应用关联": true
}
```

- 默认：`true`
- 关闭：设为 `false`
- 写回结果会保存到模型输出旁边的 `输出.apply-result.json`
- `run.json` 中会记录 `auto_apply_relations` 的执行状态和错误信息
