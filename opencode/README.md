# opencode

`mycli opencode` 是现有 `opencode` CLI 的 forwarding package。它同时提供常用 mapped commands 和完整 native passthrough。

## Source

```text
D:\agent_workspace\projects\opencode
Native CLI: C:\Users\38188\AppData\Roaming\npm\opencode.ps1
```

## Usage

```powershell
mycli opencode --help
mycli opencode list
mycli opencode native --help
mycli opencode native run hello
mycli opencode start
mycli opencode start D:\agent_workspace\projects\opencode
mycli opencode run "hello"
mycli opencode agent --help
mycli opencode providers --help
mycli opencode models --help
mycli opencode session --help
mycli opencode export <sessionID>
mycli opencode import <file-or-url>
mycli opencode serve
mycli opencode web
mycli opencode stats
```

## Command model

- `native`：把所有剩余参数原样传给已安装的 `opencode` CLI。
- `start [project]`：启动默认 opencode TUI，或打开指定项目路径。
- direct mapped commands：`run`、`agent`、`providers`、`models`、`session`、`export`、`import`、`serve`、`web`、`completion`、`acp`、`mcp`、`attach`、`debug`、`upgrade`、`uninstall`、`stats`、`github`、`pr`、`plugin`、`db`。

这些 mapped commands 本质上是通过 `prefixArgs` 转发到同名 opencode 原生子命令。

## When to use agent-cli instead

如果目标是“统一调用 agent、指定模型、管理 session、定时唤起、直接 LLM 调用”，优先用：

```powershell
mycli agent-cli run --agent opencode/private-assistant --prompt "..."
mycli agent-cli llm-call --model MoreCode/gpt-5.4 --prompt "..."
```

`mycli opencode ...` 更适合需要原生 opencode CLI 行为或调试 opencode 本身的场景。

## Safety notes

- `providers`、`mcp`、`plugin`、`upgrade`、`uninstall` 等可能修改 opencode 配置或安装状态，执行前确认用户意图。
- `serve` / `web` 会启动服务或 UI；注意端口、进程和访问范围。
- `native` 是完整透传，能力边界等同原生 opencode CLI。
