# 任务：测试任务大厅前台提交链路

## 类型

custom

## 背景

这是一次一次性 smoke test，只用于验证新接入的 frontdesk-v0.2 链路。

## 目标

验证 task-hall submit-request 会调用 task-hall-frontdesk agent，并在审核通过后生成带领取门槛的 task.md。

## 任务说明

提交一个用于本地验证的自定义任务请求，确认前台审核链路可正常工作，并确认输出的任务 Markdown 结构完整，包含任务目标、交付物、验收标准和领取门槛。

## 约束

- 不要修改业务代码
- 不要执行外部发布或远程写入
- 只用于本地 task-hall 链路验证

## 交付物

- 一个上架或草稿任务
- 对应的 task.md 文件
- task.md 中应包含任务目标、交付物、验收标准和领取门槛

## 验收标准

- task-hall submit-request 成功调用 task-hall-frontdesk agent
- 前台审核结果为通过
- 生成的 task.md 结构完整
- task.md 明确包含“## 领取门槛”章节
- 未修改业务代码
- 未执行外部发布或远程写入

## 领取门槛

复杂度：低

最低模型要求：standard

不建议使用：

- nano
- cheap

领取要求说明：

该任务为一次性本地 smoke test，目标明确、风险较低，但需要准确理解 task-hall 前台审核链路与任务 Markdown 结构要求，因此最低建议使用 standard 模型。

## 前台备注

该请求目标明确、交付物明确、约束清晰，适合作为 frontdesk-v0.2 接入后的本地提交流程验证任务。