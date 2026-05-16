# src 迁移记录

## 来源

已从以下位置复制基础多 agent 运行框架：

```text
D:\agent_workspace\projects\mult_agent\src
```

## 目标

复制到小说写作 agent 子包：

```text
D:\agent_workspace\capability-library\mycli\novel-writing\agent\src
```

## 当前用途

这份 `src` 暂作为小说写作 agent-loop、关联判断 agent、写作 agent、审核 agent、状态更新 agent 的实现基础。

后续需要在此基础上改造：

- 底层模型调用统一封装为 `mycli agent-cli llm-call`。
- 增加小说项目文件读取与 YAML 解析。
- 增加关联判断结果留存。
- 增加提示词留存。
- 增加候选稿输出。
- 增加状态追踪文件更新建议。
- 去除或隔离与小说写作无关的 demo / benchmark / 测试残留。

## 注意

当前只是复制基础代码，还没有完成小说写作适配。
