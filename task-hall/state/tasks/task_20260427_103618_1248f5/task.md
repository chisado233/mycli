# Middle Builder 调试任务

## 背景
测试 agent 是否会通过 task-link report 结束任务。

## 目标
在任务目录写一个 hello.txt，内容为 ok，然后提交 report。

## 交付物
- 任务目录下 hello.txt
- 任务目录下 report.md

## 验收标准
- hello.txt 存在且内容为 ok
- 通过 mycli task-hall task-link report 提交

## 领取门槛
最低模型要求：standard
