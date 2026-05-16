# CLI-Anything 项目研究报告

研究时间：2026-04-20  
研究对象：`D:\agent_workspace\projects\CLI-Anything`

## 1. 项目概览

CLI-Anything 是一个面向 AI Agent 的 CLI harness 生态项目。它的目标不是只提供单个命令行程序，而是把各种 GUI 软件、本地工具、Web 服务和专业应用包装成 Agent 友好的命令行接口，让 OpenClaw、Claude Code、Codex、OpenCode、Cursor 等 Agent 能以稳定、结构化、可测试的方式操作真实软件。

README_CN 中的核心表达是：“让所有软件都能被 Agent 驱动”。项目把 CLI 视为人类和 AI Agent 的共同接口，因为 CLI 具备可组合、自描述、轻量、确定性强、适合结构化 JSON 输出等特点。

本地目录不是 git 仓库，或 `.git` 未随压缩包一起提供，所以本报告未包含提交历史分析。

## 2. 项目形态

这个仓库是一个“生态型 monorepo”，主要由以下几类内容组成：

1. `cli-anything-plugin/`：面向 Claude Code 等 Agent 的生成插件和方法论。
2. `cli-hub/`：用于发现、安装、更新、卸载 CLI harness 的包管理器。
3. `<software>/agent-harness/`：每个软件独立的 Python CLI 包，例如 `gimp`、`blender`、`freecad`、`obsidian`、`zotero` 等。
4. `skills/`：给 AI Agent 读取的 `SKILL.md`，描述各 harness 的能力和用法。
5. `registry.json`：CLI-Hub 使用的主注册表，记录仓库内和部分外部 harness。
6. `public_registry.json`：补充登记第三方或官方 CLI，例如 Lark、Shopify、Sentry、Android CLI 等。
7. `codex-skill/`、`openclaw-skill/`、`opencode-commands/`、`qoder-plugin/`：不同 Agent 平台的适配入口。

因此，CLI-Anything 更像“生成规范 + 工具市场 + harness 集合”，而不是 OpenCLI 那种统一运行时框架。

## 3. 技术栈与运行要求

项目主技术栈如下：

| 类别 | 内容 |
|---|---|
| 主语言 | Python |
| CLI 框架 | Click |
| 交互式 REPL | prompt-toolkit、项目内统一 `repl_skin.py` |
| 测试 | pytest |
| 包管理 | pip / setuptools / pyproject.toml |
| Agent 描述 | SKILL.md |
| 注册表 | JSON registry |
| 辅助语言 | 少量 JavaScript、Shell、PowerShell |

README_CN 中给出的基本要求：

- Python 3.10+
- 目标软件或服务已安装/可访问
- 支持的 Agent 平台之一，例如 Claude Code、OpenClaw、OpenCode、Codex、Qodercli 等

单个 harness 通常是独立 Python 包，安装方式类似：

```bash
pip install git+https://github.com/HKUDS/CLI-Anything.git#subdirectory=gimp/agent-harness
```

安装后暴露独立 entry point，例如：

```bash
cli-anything-gimp
cli-anything-blender
cli-anything-freecad
```

## 4. 代码规模与资产统计

基于本地文件扫描：

| 指标 | 数量 |
|---|---:|
| 总文件数 | 1210 |
| `agent-harness` 目录数 | 47 |
| `setup.py` 文件数 | 46 |
| `pyproject.toml` 文件数 | 4 |
| `SKILL.md` 文件数 | 97 |
| 测试相关文件数 | 199 |
| Python 文件数 | 828 |
| JavaScript 文件数 | 5 |
| Markdown 文件数 | 294 |

基于 `registry.json`：

| 指标 | 数量 |
|---|---:|
| CLI 条目数 | 48 |
| 分类数 | 27 |
| 有 skill_md 的条目 | 43 |
| 标记为独立 source_url 的条目 | 1 |
| registry 更新时间 | 2026-03-31 |

基于 `public_registry.json`：

| 指标 | 数量 |
|---|---:|
| 公共 CLI 条目数 | 15 |
| 分类数 | 9 |
| registry 更新时间 | 2026-04-18 |

`registry.json` 中数量最多的分类包括：

| 分类 | 数量 |
|---|---:|
| ai | 5 |
| video | 4 |
| image | 3 |
| office | 3 |
| graphics | 3 |
| devops | 3 |
| web | 3 |
| network | 2 |
| automation | 2 |
| 3d | 2 |
| diagrams | 2 |

## 5. 核心方法论：Agent Harness

`cli-anything-plugin/HARNESS.md` 是整个项目最关键的方法论文档。它定义了把 GUI 或复杂软件转成 Agent 可用 CLI 的标准流程。

标准流程分为几个阶段：

1. 代码库分析：识别后端引擎、GUI 操作到 API 的映射、数据模型、已有 CLI 工具、undo/redo 命令体系。
2. CLI 架构设计：选择 REPL、子命令或两者结合；规划命令分组、状态模型和输出格式。
3. 实现：先做数据层和 inspect 命令，再做 mutation 命令、后端 wrapper、导出渲染、session 管理、REPL。
4. 测试计划：先写 `TEST.md`，规划单元测试和端到端测试。
5. 测试实现：`test_core.py` 做无后端单元测试，`test_full_e2e.py` 做真实工作流和真实软件后端验证。
6. 测试文档：把实际 pytest 结果追加回 `TEST.md`。
7. SKILL.md 生成：让 Agent 能发现并正确调用 harness。
8. 发布：生成 `setup.py`，安装到 PATH，并补 registry。

这个方法论有一个非常明确的设计取向：不鼓励 Agent 直接点 GUI，而是优先寻找真实软件的底层 API、文件格式、脚本接口或命令行后端，把它们包装成可重复调用的 CLI。

## 6. 单个 Harness 的典型结构

贡献文档要求每个仓库内 harness 放在：

```text
<software>/
└── agent-harness/
    ├── <SOFTWARE>.md
    ├── setup.py
    └── cli_anything/
        └── <software>/
            ├── README.md
            ├── __init__.py
            ├── __main__.py
            ├── <software>_cli.py
            ├── core/
            ├── utils/
            ├── skills/
            └── tests/
```

以 `gimp/agent-harness` 为例：

- `setup.py` 包名是 `cli-anything-gimp`
- `console_scripts` 暴露 `cli-anything-gimp=cli_anything.gimp.gimp_cli:main`
- 依赖 `click>=8.0.0`、`prompt-toolkit>=3.0.0`
- 可选开发依赖包含 `pytest`、`pytest-cov`、`Pillow`、`numpy`
- package data 包含 packaged skill 文件

`gimp_cli.py` 和 `blender_cli.py` 体现了常见模式：

- 顶层 `@click.group(invoke_without_command=True)`
- 全局 `--json`
- 全局 `--project`
- 全局 `--dry-run`
- 没有子命令时默认进入 REPL
- 有全局 session 状态
- 命令结束后自动保存修改
- 通过 `handle_error` 把错误转成普通文本或 JSON
- 命令分组按软件领域组织，例如 project/layer/filter/canvas/export，或 scene/object/material/render

这说明 CLI-Anything 的 harness 目标不是简单包装一次性命令，而是构建“有状态的专业软件操作界面”。

## 7. CLI-Hub 包管理器

`cli-hub/` 是 CLI-Anything 的包管理器，包名为 `cli-anything-hub`，entry point 是：

```text
cli-hub=cli_hub.cli:main
```

它提供的主要命令：

- `cli-hub list`
- `cli-hub list --json`
- `cli-hub search <query>`
- `cli-hub info <name>`
- `cli-hub install <name>`
- `cli-hub update <name>`
- `cli-hub uninstall <name>`
- `cli-hub launch <name> [args...]`

实现上，`cli_hub.cli` 负责 Click 命令表面，`registry.py` 负责读取 registry，`installer.py` 负责安装/卸载/更新，`analytics.py` 负责匿名事件统计。

`cli-hub` 的设计很轻：它不把所有 harness 打包进一个大包，而是通过 registry 解析安装命令，然后让 pip 或其它 package manager 安装各自独立的 CLI 包。这种方式有利于单个 harness 独立演进，但也意味着版本一致性和跨平台安装质量取决于每个 harness 自身。

## 8. Registry 体系

`registry.json` 是 CLI-Hub 的主数据源，字段包括：

- `name`
- `display_name`
- `version`
- `description`
- `requires`
- `homepage`
- `source_url`
- `install_cmd`
- `entry_point`
- `skill_md`
- `category`
- `contributors`

贡献文档明确支持两种贡献模式：

1. 仓库内 harness：代码放在 `<software>/agent-harness/`，registry 的 `source_url` 通常为 `null`。
2. 独立仓库 harness：只向本仓库提交 registry 条目，代码由贡献者自己的仓库维护。

`public_registry.json` 则收录更广义的公开 CLI，不一定是 CLI-Anything harness，例如 Feishu/Lark CLI、Shopify CLI、Sentry CLI、Android CLI、Suno CLI、Obsidian CLI 等。它让 CLI-Hub 从“自研 harness 市场”扩展为“Agent 可发现 CLI 目录”。

## 9. Agent 平台集成

CLI-Anything 明显重视多个 Agent 平台的接入：

| 平台 | 仓库入口 |
|---|---|
| Claude Code | `cli-anything-plugin/` |
| OpenCode | `opencode-commands/` |
| OpenClaw | `openclaw-skill/` |
| Codex | `codex-skill/` |
| Qodercli | `qoder-plugin/` |
| Claude 插件市场 | `.claude-plugin/`、`cli-anything-plugin/.claude-plugin/` |

`codex-skill/SKILL.md` 是给 Codex 使用的浓缩版方法论。它要求 Codex 在构建 harness 时：

- 使用 `cli_anything.<software>` namespace package 布局
- 用 `setup.py` 暴露 `cli-anything-<software>` entry point
- 实现 Click CLI、默认 REPL、`--json`、session 状态
- 优先使用真实软件后端，不要轻易重写软件能力
- 先写测试计划，再写测试，再运行验证

这和 `HARNESS.md` 的大方法论保持一致，只是更适合 Codex 执行。

## 10. 测试体系

项目对测试的要求相当明确：

- `test_core.py`：单元测试，尽量不依赖真实后端软件。
- `test_full_e2e.py`：端到端测试，应该调用真实软件或真实后端。
- CLI subprocess 测试：通过已安装的 `cli-anything-<software>` 命令验证真实用户路径。
- `TEST.md`：先写测试计划，再追加测试运行结果。

HARNESS.md 里强调端到端测试不能只检查命令退出码，而要验证真实输出：

- 文件存在且大小大于 0
- PDF magic bytes、OOXML ZIP 结构、图片/视频像素分析、音频 RMS 等
- 打印 artifact 路径供人工检查
- 不建议因为后端未安装而“优雅跳过”真实后端测试

这套测试文化很适合 Agent 场景，因为 Agent 很容易被“命令成功但产物不可用”误导。

## 11. 安全模型

`SECURITY.md` 明确指出 CLI-Anything 的特殊风险：AI Agent 可能基于不可信输入自主构造和执行命令。关键攻击面包括：

- subprocess 参数注入
- GIMP Script-Fu 注入
- XML/SVG/Draw.io/MLT 等结构化内容注入
- 文件路径遍历
- 凭证泄露

安全建议包括：

- 不使用 `shell=True`
- subprocess 参数使用 list
- 对 codec、filter、路径、参数做 allowlist 校验
- 嵌入脚本或 XML/SVG 前做转义
- 对文件路径做 `abspath`/必要时 `realpath`
- 不在日志或 JSON 输出中暴露 API key
- 对凭证配置文件设置 `0o600` 权限

这些约束很重要，因为 harness 不是只读工具，很多命令会写文件、导出媒体、调用外部软件、访问网络服务或代表用户操作账户。

## 12. 优势判断

CLI-Anything 的主要优势：

1. 方法论完整：从分析、设计、实现、测试、文档、skill 到发布都有明确流程。
2. Agent 原生：默认要求 `--json`、REPL、SKILL.md、subprocess 测试和可发现 registry。
3. 生态覆盖面广：已覆盖图像、视频、3D、办公、网络、AI、科学、DevOps、浏览器、游戏等多个领域。
4. 单个 harness 独立包化：每个软件的 CLI 可以独立安装、测试、发布。
5. 鼓励真实后端：优先使用实际软件 API、文件格式、CLI 或脚本接口，减少“仿真但不兼容”的风险。
6. 对测试结果质量有要求：强调真实产物验证，而非只看 exit code。
7. 多 Agent 平台入口：Claude Code、OpenCode、OpenClaw、Codex、Qodercli 都有对应接入文件。

## 13. 潜在风险与关注点

1. harness 之间一致性可能漂移：虽然有方法论，但每个 harness 独立实现，错误处理、JSON schema、REPL 行为可能不完全一致。
2. 外部软件依赖重：Blender、GIMP、FreeCAD、QGIS、LibreOffice 等安装体积大，CI 和用户环境很容易不一致。
3. 跨平台复杂：很多后端命令在 Windows/macOS/Linux 上路径、参数、依赖不同。
4. 真实 E2E 成本高：项目要求真实后端验证，这有助于质量，但也增加贡献和维护成本。
5. 安全面广：Agent 可自动调用本地软件、写文件、执行外部命令，需要每个 harness 持续遵守安全规则。
6. registry 与实际代码可能不同步：如果 harness 更新但 registry 版本、entry point、skill 路径未同步，CLI-Hub 安装体验会受影响。
7. public registry 当前混合多种安装方式：npm、brew、pip、bundled、script、cargo 等，安装策略和卸载/更新体验需要额外适配。
8. 本地源码不是 git 仓库，后续开发或 PR 应重新 clone 原仓库，避免丢失版本上下文。

## 14. 与 OpenCLI 的区别

如果把它和前面研究的 OpenCLI 对比：

| 维度 | CLI-Anything | OpenCLI |
|---|---|---|
| 项目形态 | harness 生态、生成方法论、CLI-Hub 市场 | 统一 Node.js CLI 运行时 |
| 主语言 | Python | TypeScript/Node.js |
| 核心入口 | 多个独立 `cli-anything-*` 包 + `cli-hub` | 单个 `opencli` 命令 |
| 目标对象 | GUI 软件、本地工具、Web 服务、专业应用 | 网站、浏览器会话、Electron、本地 CLI |
| 状态模型 | 每个 harness 自己管理 session/project | 统一 Registry/Execution/BrowserBridge |
| Agent 接入 | 多平台 skill/plugin/commands | OpenCLI skills + browser 原语 |
| 发布模式 | 每个 harness 独立 pip 包 | 单 npm 包 + adapters/plugins |

两者都服务于“让 Agent 操作真实软件”，但抽象层不同：CLI-Anything 更像生产 CLI harness 的工厂和市场，OpenCLI 更像一个统一执行内核和适配器平台。

## 15. 适合继续深入的方向

建议按目标继续研究：

1. 如果目标是使用现有 CLI：先安装 `cli-anything-hub`，运行 `cli-hub list --json`、`cli-hub info <name>`、`cli-hub install <name>`。
2. 如果目标是给某个软件生成 CLI：重点读 `cli-anything-plugin/HARNESS.md`、`codex-skill/SKILL.md`，再选一个结构清晰的 harness 作为模板。
3. 如果目标是维护 registry：重点读 `CONTRIBUTING.md` 的 registry 字段要求，并验证 `install_cmd`、`entry_point`、`skill_md` 是否真实可用。
4. 如果目标是提升质量：优先统一各 harness 的 JSON error schema、session 文件锁、path 安全策略和 subprocess allowlist。
5. 如果目标是做本地验证：从依赖轻的 harness 开始，例如 Mermaid、Ollama、Exa、WireMock 或纯 API 类工具，再逐步验证 GIMP/Blender/FreeCAD 这类重后端。

## 16. 结论

CLI-Anything 是一个围绕“Agent 原生 CLI”构建的生态仓库。它的价值不只是已有 48 个 registry harness，而是把“如何把复杂软件变成 Agent 可操作 CLI”沉淀成了可复用 SOP、插件命令、skills、测试标准和包管理入口。

从本地代码看，它已经形成了比较清晰的模式：每个软件一个独立 Python 包，Click 提供一-shot 命令，REPL 处理有状态交互，`--json` 服务 Agent，真实后端保证能力有效，`SKILL.md` 负责 Agent 发现，`registry.json` 负责 CLI-Hub 分发。

它最大的挑战是生态一致性和真实软件依赖的维护成本。若后续要在这个项目上开发，建议从一个具体 harness 入手，严格按 `HARNESS.md` 的测试与安全要求推进；如果要做平台层改进，则优先增强 `cli-hub` 的 registry 校验、安装验证和 JSON schema 统一能力。
