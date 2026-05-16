# 小说写作 Agent 子包设计

## 定位

`mycli novel-writing agent` 是小说写作系统的 agent 层，负责封装：

- agent-loop
- 调度 agent
- 关联判断 agent
- 写作 agent
- 小说编辑 agent
- 状态更新 agent

每个 agent 都有独立设计文档，位于：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\agent\agents
```

这些 agent 不使用 opencode。它们都通过 `mycli agent-cli llm-call` 作为底层模型调用方式，但对外表现为小说写作专用 agent 链路。

## 核心原则

- 调度 agent 不直接创作小说内容。
- 写作 agent 负责内容生成。
- 关联判断 agent 专门判断关联文件。
- 小说编辑 agent 专门提供编辑意见和修改建议。
- 每一次生成都要留存提示词。
- 每一次关联判断都要留存关联判断结果。
- 第一版全部传全文，不做摘要。

## agent-loop 初步流程

```text
输入任务
  ↓
读取目标 md
  ↓
关联判断 agent 生成关联文件清单
  ↓
留存关联判断结果
  ↓
调度 agent 组装上下文与提示词
  ↓
留存提示词.md
  ↓
写作 agent 通过 llm-call 生成内容
  ↓
保存候选输出
  ↓
小说编辑 agent 提供修改建议，检查雷点、跑偏、设定冲突、状态遗漏
  ↓
状态更新 agent 更新人物/势力/伏笔/章节状态
  ↓
写入生成记录
```

## 留存目录建议

在具体小说项目中：

```text
11-调度与生成/
  prompts/
  relation-results/
  agent-runs/
```

## 底层调用

各 agent 第一版都通过：

```powershell
mycli agent-cli llm-call --model <model> --prompt-file <prompt.md>
```

封装层负责生成 prompt 文件、收集全文上下文、保存输出和记录。
