# 调度 Agent

## 定位

调度 agent 是小说写作系统的总调度者。它只负责调度，不直接创作小说内容，不直接编辑小说内容。

调度 agent 的核心产物是用于调用其他 agent 的 JSON 请求文件。

## 核心职责

- 判断当前任务类型。
- 决定要调用哪个 agent。
- 为被调用 agent 写 JSON 请求文件。
- 在 JSON 中写明 system prompt、用户提示词、目标文件、上下文文件、是否自动关联等字段。
- 调用 agent runner 执行 JSON 请求。
- 留存 JSON 请求、提示词、输出和运行记录。
- 按流程串联：关联判断 agent → 写作 agent → 小说编辑 agent → 状态更新 agent。

## 输入

- 小说项目路径
- 当前任务
- 目标 md
- 用户要求
- 可选模型参数

## 输出

- 一个或多个 agent JSON 请求文件
- agent 调用顺序
- 运行记录

## 待讨论问题

- 调度 agent 生成的 JSON 请求文件命名规则是什么？
- 调度 agent 是否只负责写 JSON，还是也负责执行 JSON？
- 调度 agent 一次 loop 是否默认包含：关联判断 → 写作 → 小说编辑 → 状态更新？
