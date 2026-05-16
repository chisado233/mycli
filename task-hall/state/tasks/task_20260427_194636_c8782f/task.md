# Multi leader capacity test 1

## 背景
测试 engineering-leader 类型并发上限为 2，同一 opencode/engineering-leader 模板应能开不同 session。

## 目标
不要拆任务。等待约 40 秒后写 report 并 task-link report，模拟 leader 正在占用容量。

## 交付物
- task-link report

## 验收标准
- 前两个任务可并发 claimed，第三个应等待容量。

## 推荐 agent 类型
engineering-leader

## 汇报方式
必须 task-link report。
