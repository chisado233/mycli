# 项目进度

## 项目文件地图

```
source/
├── apps/
│   ├── desktop/electron/
│   │   ├── local-agent.ts       ← Bridge 核心(SSE/透传/session)
│   │   ├── agent.ts             ← 入口
│   │   └── main.ts              ← Electron 窗口
│   └── mobile/src/
│       ├── App.tsx              ← 手机 UI + reducer
│       └── styles.css           ← 暗色主题
├── server/api/src/index.ts      ← 云服务器
├── shared/
│   ├── protocol/src/index.ts    ← 事件协议
│   └── core/src/index.ts        ← ChatClient
├── progress.md                  ← 详细进度跟踪
└── docs/                        ← 项目文档
```

## 关键决策记录

### 2026-06-06: 放弃 agent-cli，使用 opencode serve SSE
- **内容**：原始方案通过 agent-cli 调用 opencode，JSONL 不输出 text 事件
- **决策**：改为 `opencode serve` → `GET /event` SSE 实时流，bridge 透传
- **原因**：JSONL 只有 step_start/tool_use/step_finish，无 text

### 2026-06-06: 云服务器 DB JSON 格式
- **内容**：db.json 用 PowerShell 写入被破坏
- **决策**：用 node.js writeFileSync 操作，PS1 禁止直接写 JSON

### 2026-06-06: agentId/modelId 不生效
- **内容**：prompt_async 接受 agentId/modelId 但 serve 忽略
- **决策**：/agent /model 只做状态栏显示，实际切换需改 opencode.json

## 当前进度

- **当前目标**：稳定运行，修复遗留问题
- **已完成**：SSE 流 + 后台保活 + session 管理 + markdown + 命令面板 + 开机自启
- **进行中**：无
- **下一步**：通知功能、agent/model 真实切换
- **阻塞/风险**：无
- **测试结果**：
  - SSE token 级流：通过
  - 后台保活：通过
  - 回前台补消息：通过
  - /session new：通过
  - /abort：通过
  - 开机自启：通过
  - 通知：暂缓