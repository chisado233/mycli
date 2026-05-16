# 任务：测试任务大厅前台提交链路

## 类型

custom

## 背景

这是一次一次性 smoke test，只用于验证新接入的 frontdesk-v0.2 链路。

## 目标

验证 task-hall submit-request 会调用 task-hall-frontdesk agent，并在审核通过后生成带领取门槛的 task.md。

## 任务说明

这是一个本地链路验证任务，重点是确认任务请求从提交入口进入 task-hall-frontdesk 后，能够被正确审核，并在通过后产出结构完整的任务 Markdown。该任务不要求修改业务代码，也不要求执行真实业务操作。

## 约束

- 不要修改业务代码
- 不要执行外部发布或远程写入
- 只用于本地 task-hall 链路验证

## 交付物

- 一个上架或草稿任务
- 对应的 task.md
- task.md 中明确包含：任务目标、交付物、验收标准、领取门槛

## 验收标准

- task-hall submit-request 成功调用 task-hall-frontdesk agent
- 前台审核通过该请求
- 成功生成 task.md 或等效任务 Markdown
- 产出的 Markdown 中包含“## 领取门槛”章节
- “## 领取门槛”中写明复杂度和最低模型要求
- 全流程仅用于本地 smoke test，不发生外部发布或远程写入

## 领取门槛

复杂度：低

最低模型要求：cheap

不建议使用：

- nano

领取要求说明：

该任务主要是一次性本地链路验证，目标明确、风险较低、无需复杂设计或高风险操作。领取 agent 需能够理解任务大厅提交流程，并确认生成的任务 Markdown 结构完整。

## 前台备注

该请求属于 custom 任务，目标、背景、交付物与约束均已明确，可进入任务大厅。由于这是 smoke test，建议按最小必要范围执行验证，避免扩大为业务改造或系统级联调。