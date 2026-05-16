# Lifecycle wake smoke task

## 背景
验证 task-hall publish-raw 后会立即发起 lifecycle wake，而不是等待 5 分钟轮询。

## 目标
由 middle-builder 创建一个简单文件，证明任务被即时调度。

## 工作范围
- 在 `D:\agent_workspace\tmp\task-hall-wake-smoke\done.txt` 写入一行完成说明。
- 写任务报告并通过 task-link report 提交。

## 交付物
- `D:\agent_workspace\tmp\task-hall-wake-smoke\done.txt`
- task-link report

## 验收标准
- 文件存在。
- task-link report 已提交。

## 推荐 agent 类型
middle-builder

## 汇报方式
必须使用 task-link report。
