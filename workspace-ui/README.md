# workspace-ui

`workspace-ui` 是 `agent-workspace` 的统一 UI 总控台。它以树形目录展示 `capability-library`、`mycli` 包树和 `projects` 项目区，并负责发现、启动、停止、打开各节点自己暴露的子 UI。

它不实现具体业务 UI；例如 channels 消息监控仍由 `channels monitor-ui` 自己实现，workspace-ui 只负责把它作为可启动的子 UI 接入。

## Commands

```powershell
mycli workspace-ui start [port]
mycli workspace-ui stop
mycli workspace-ui open [port]
mycli workspace-ui status
```

默认地址：

```text
http://127.0.0.1:46000
```

## UI manifest

有子 UI 的包或项目可以在自己的目录下放置 `.agent-ui.json`：

```json
{
  "id": "mycli.channels.monitor-ui",
  "name": "Channels Monitor UI",
  "description": "监控 channels 消息、状态与配置",
  "type": "mycli-ui",
  "url": "http://127.0.0.1:45990",
  "health": {
    "url": "http://127.0.0.1:45990/api/snapshot"
  },
  "commands": {
    "start": ["channels", "monitor-ui"],
    "stop": ["channels", "monitor-ui-stop"],
    "open": ["channels", "monitor-ui-open"]
  }
}
```

`commands` 推荐使用 mycli 参数数组。workspace-ui 会通过 `mycli.ps1` 执行这些命令。

## Scope

- `capability-library/mycli`：展示包树，扫描 `.agent-ui.json`。
- `projects`：展示一级项目目录；只有存在 `.agent-ui.json` 的项目才显示启动、停止、打开按钮。
- 已接入 `channels monitor-ui`、`cron ui`、`startup ui`。

## Workspace UI style guide

所有接入 `workspace-ui` 的本地子 UI 应尽量与总控台保持同一套视觉语言。目标不是完全复制页面结构，而是让用户从任意子 UI 返回总控台时仍感觉属于同一个 agent-workspace 控制面。

### 设计方向

- 关键词：**Control Atlas / local control plane / capability console**。
- 气质：深色、玻璃质感、带轻微工业控制台感，但不要做成普通后台表格。
- 页面应给人“本机能力驾驶舱”的感觉：明确、可控、有状态反馈。

### 色彩规范

推荐使用以下 CSS 变量作为基础色板：

```css
:root {
  --bg: #10110e;
  --bg2: #1c2017;
  --panel: rgba(243, 232, 205, 0.09);
  --panel-strong: rgba(243, 232, 205, 0.14);
  --line: rgba(243, 232, 205, 0.18);
  --text: #f3e8cd;
  --muted: #a8a08b;
  --green: #a5ff62;
  --amber: #ffcb5b;
  --blue: #7ed7ff;
  --red: #ff7d6e;
  --shadow: 0 24px 80px rgba(0,0,0,.45);
}
```

使用规则：

- `--green`：在线、可用、成功、已接入 UI、主操作。
- `--amber`：等待、可启动、警告、下次运行时间。
- `--blue`：链接、打开外部 UI、信息性状态。
- `--red`：失败、停止、危险动作。
- 背景使用深色径向光晕，不使用纯白后台，不使用浅色普通 admin 模板。

推荐背景：

```css
background:
  radial-gradient(circle at 15% 10%, rgba(165,255,98,.22), transparent 28%),
  radial-gradient(circle at 85% 0%, rgba(126,215,255,.16), transparent 26%),
  linear-gradient(135deg, var(--bg), var(--bg2) 55%, #080908);
```

### 字体规范

- 标题/正文优先使用有书卷感的 serif：`Cambria, "Iowan Old Style", Georgia, serif`。
- 小标签、状态、路径、日志、按钮优先使用 monospace：`Consolas, "Courier New", monospace`。
- 避免默认 Arial/Roboto/Inter 风格的普通 SaaS 后台感。

### 布局规范

- 主体使用 14px 左右外边距，卡片间距保持 14px 的紧凑控制台节奏。
- 关键容器使用大圆角：外层 `28px-32px`，内部卡片 `20px-26px`，按钮 `14px-16px`。
- 子 UI 可按业务选择布局，但建议保留：
  - 顶部 hero / 标题区，说明当前 UI 的职责。
  - 状态统计卡片区，显示 total / enabled / online / failed 等核心数字。
  - 主内容区，显示列表、详情或日志。
  - 执行回显区，用于展示 mycli 调用结果。

### 组件规范

- 卡片使用玻璃质感：

```css
border: 1px solid var(--line);
background: linear-gradient(180deg, rgba(255,255,255,.08), rgba(255,255,255,.035));
backdrop-filter: blur(18px);
box-shadow: var(--shadow);
```

- 按钮使用 monospace，hover 时轻微上浮：

```css
button {
  border: 1px solid var(--line);
  color: var(--text);
  background: rgba(255,255,255,.08);
  border-radius: 14px;
  transition: transform .18s ease, background .18s ease, border-color .18s ease;
}
button:hover:not(:disabled) {
  transform: translateY(-1px);
  border-color: rgba(165,255,98,.55);
}
```

- 状态徽章使用 pill 形状：online 用 green，waiting/warning 用 amber，link/info 用 blue，error 用 red。
- 路径、命令、日志必须可换行或横向滚动，避免撑破布局。

### 交互规范

- 子 UI 启动/停止/运行任务等动作应显示执行回显，不要静默失败。
- 所有列表都应有刷新按钮。
- 能从 `mycli` 获取 JSON 的地方优先使用 JSON API；前端不要解析表格文本作为主方案。
- “打开子 UI”应默认新开网页，不在总控台或子 UI 中强制 iframe 嵌入。
- 危险动作如果后续加入，应使用明确按钮文案和 red 状态，不要隐藏在普通按钮里。

### 接入一致性

- 子 UI 的目录建议为对应包下的 `ui/`，例如 `cron/ui`、`startup/ui`。
- 子 UI 应提供 `start.ps1`、`stop.ps1`、`start-open.ps1`、`status.ps1` 四个脚本，并注册为 `ui`、`ui-stop`、`ui-open`、`ui-status` 命令。
- 子 UI 应提供 `/api/snapshot` 作为健康与总览接口，供 `.agent-ui.json` 的 `health.url` 使用。
- 接入 `workspace-ui` 的 manifest 推荐放在包根目录 `.agent-ui.json`，如果 UI 是包内部子能力，也可以放在具体 UI 目录下。

### 当前总控台特性

- 左侧目录支持搜索。
- 左侧目录支持“只看已接入 UI”，开启后会隐藏未接入 UI 的叶子目录，只保留已接入节点及其父级路径。
- 有 UI manifest 的节点会显示发光绿点，并在右侧显示启动、停止、打开按钮。
