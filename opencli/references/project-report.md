# OpenCLI 项目研究报告

研究时间：2026-04-20  
研究对象：`D:\agent_workspace\projects\OpenCLI`

## 1. 项目概览

OpenCLI 是一个基于 Node.js/TypeScript 的命令行工具，包名为 `@jackwener/opencli`，当前源码中的版本是 `1.7.4`。它的核心目标是把网站、浏览器会话、Electron 桌面应用和本地 CLI 工具统一包装成可脚本化、可给 AI Agent 调用的确定性命令接口。

从 README 和代码实现看，项目不是单纯的网页爬虫集合，而是一个“CLI 枢纽”：

- 对普通用户：提供 `opencli list`、`opencli <site> <command>`、`opencli doctor` 等稳定入口。
- 对 AI Agent：提供 `opencli browser ...` 这一组底层浏览器操作原语，用已登录 Chrome/Chromium 会话完成导航、点击、输入、提取、截图等任务。
- 对开发者：支持通过适配器、插件、探索与生成流程，把新网站能力沉淀为可复用 CLI。
- 对桌面应用：通过 Chrome DevTools Protocol 控制 Cursor、Codex、ChatGPT、Notion 等 Electron 应用。

本地目录不是 git 仓库，或 `.git` 未随压缩包一起提供，所以本报告未包含提交历史分析。

## 2. 技术栈与运行要求

项目主要技术栈如下：

| 类别 | 内容 |
|---|---|
| 运行时 | Node.js `>=21.0.0` |
| 语言 | TypeScript / JavaScript，ESM 模块 |
| CLI 框架 | `commander` |
| 输出/配置 | `js-yaml`、自定义 output formatter |
| 浏览器通信 | Browser Bridge 扩展、本地 daemon、WebSocket、CDP |
| 测试 | `vitest`，分 unit / extension / adapter / e2e / smoke 多项目 |
| 文档 | VitePress 文档目录 `docs/`，中英文 README |

`package.json` 中的主入口是 `dist/src/main.js`，命令行 bin 为：

```json
{
  "opencli": "dist/src/main.js"
}
```

常用脚本：

- `npm run dev`：通过 `tsx src/main.ts` 运行源码。
- `npm run build`：清理 dist、编译 TypeScript、复制 YAML、构建 manifest。
- `npm test`：运行 unit、extension、adapter 测试。
- `npm run test:e2e`：运行 e2e 测试。
- `npm run docs:dev` / `docs:build` / `docs:preview`：文档站点开发与构建。

## 3. 代码规模与资产统计

基于本地文件扫描：

| 指标 | 数量 |
|---|---:|
| 总文件数 | 1251 |
| `src/` 文件数 | 131 |
| `clis/` 适配器目录数 | 102 |
| 测试文件数 | 232 |
| `docs/` 文档文件数 | 139 |
| `skills/` 技能目录数 | 6 |

基于 `cli-manifest.json`：

| 指标 | 数量 |
|---|---:|
| 命令总数 | 604 |
| 站点数 | 100 |

命令策略分布：

| 策略 | 命令数 | 含义 |
|---|---:|---|
| `cookie` | 357 | 复用浏览器登录态，适合登录后站点 |
| `public` | 152 | 直接访问公开接口或公开页面 |
| `ui` | 80 | 通过 UI/DOM 或桌面应用交互完成 |
| `intercept` | 10 | 拦截网络请求，常见于复杂 GraphQL/XHR 站点 |
| `local` | 4 | 本地工具或本地能力 |
| `header` | 1 | 自定义 header/API key 类认证 |

命令数量最多的站点包括：`twitter`、`instagram`、`nowcoder`、`tiktok`、`reddit`、`lesswrong`、`boss`、`bilibili`、`youtube`、`douyin`、`notebooklm`、`xiaohongshu` 等。

## 4. 总体架构

项目文档把 OpenCLI 描述为“双引擎架构”：既支持声明式 pipeline，也支持编程式 TypeScript/JavaScript adapter。

核心分层可以理解为：

1. CLI 层：`src/main.ts` 和 `src/cli.ts`
2. 注册与发现层：`src/registry.ts`、`src/discovery.ts`、`src/build-manifest.ts`
3. 命令执行层：`src/execution.ts`、`src/commanderAdapter.ts`
4. 适配器层：`clis/<site>/<command>.js`、pipeline adapter、插件 adapter
5. 浏览器与桌面连接层：`src/browser/`、`src/daemon.ts`、`extension/`、CDP launcher
6. 输出与诊断层：`src/output.ts`、`src/errors.ts`、`src/diagnostic.ts`

这种设计的优点是把“命令注册”“命令执行”“输出渲染”“浏览器会话”拆得比较清楚：Commander 只负责 CLI 表面，真正执行逻辑集中在 `execution.ts`。

## 5. 启动链路

入口文件是 `src/main.ts`。启动流程大致如下：

1. 非 Windows 平台补齐常见系统 PATH，避免 GUI/IDE 环境中缺少 `/usr/local/bin` 等路径。
2. 处理快速路径：
   - `opencli --version` / `-V`
   - `opencli completion <shell>`
   - `--get-completions`
3. 快速路径无法满足时，动态导入重模块，降低普通命令启动成本。
4. 并行执行用户目录准备、用户适配器目录准备、内置适配器发现。
5. 依次发现用户适配器和插件，保证覆盖顺序：内置适配器 < 用户适配器 < 插件。
6. 注册更新提醒、启动 hook。
7. 调用 `runCli(BUILTIN_CLIS, USER_CLIS)` 进入 Commander CLI。

值得注意的是，项目非常重视启动性能。`cli-manifest.json` 用于避免每次启动都扫描和加载全部适配器，适配器模块会被延迟加载到首次执行时。

## 6. 注册与发现机制

`src/registry.ts` 定义了核心命令模型：

- `Strategy`：`public`、`local`、`cookie`、`header`、`intercept`、`ui`
- `Arg`：命令参数定义
- `CliCommand`：站点、命令名、描述、策略、参数、输出列、执行函数、pipeline 等
- `cli(opts)`：适配器注册入口
- `registerCommand(cmd)`：统一注册命令，并处理 alias 与策略归一化

策略归一化是重要设计点。`normalizeCommand()` 会根据 strategy 推导：

- 是否需要浏览器会话：`browser`
- 是否需要预导航：`navigateBefore`

例如，`cookie` 或 `header` 策略且有 `domain` 时，会默认预导航到 `https://<domain>`；非 public/local 策略通常需要浏览器上下文。

`src/discovery.ts` 支持两条发现路径：

- 生产/构建后：优先从 `cli-manifest.json` 加载命令元数据，并懒加载模块。
- 开发/回退：扫描 `clis/<site>/*.js`，发现包含 `cli(...)` 或 hook 的模块并导入。

用户适配器目录在 `~/.opencli/clis`，插件目录在 `~/.opencli/plugins`。项目还会在 `~/.opencli/node_modules/@jackwener/opencli` 创建指向当前包的链接，让用户适配器能够通过包导出路径导入 OpenCLI API。

## 7. 命令执行机制

`src/commanderAdapter.ts` 是 Registry 到 Commander 的桥接层。它负责：

- 为每个 site 创建 Commander 子命令。
- 把 `CliCommand.args` 转成 positional argument 或 option。
- 收集参数，调用 `prepareCommandArgs()`。
- 执行 `executeCommand()`。
- 调用 `output.render()` 渲染 table/json/yaml/md/csv/plain。
- 捕获错误，并输出结构化 YAML error envelope。

`src/execution.ts` 是真正的执行中心。它负责：

- 参数类型转换和 required/choices 校验。
- required environment 校验。
- 懒加载 adapter 模块。
- 判断是否需要浏览器会话。
- 对浏览器命令做预导航。
- 对命令执行加 timeout。
- 执行 pipeline 或 adapter 函数。
- 触发 lifecycle hooks。
- 在诊断模式下收集上下文。

命令执行路径可以概括为：

```text
opencli <site> <command>
  -> Commander 子命令
  -> commanderAdapter 收集参数
  -> execution.prepareCommandArgs
  -> execution.executeCommand
  -> browserSession 或 non-browser run
  -> adapter func 或 pipeline
  -> output.render
```

## 8. 浏览器与桌面应用集成

浏览器相关代码位于 `src/browser/`，对外 barrel 是 `src/browser/index.ts`，主要导出：

- `BrowserBridge`
- `CDPBridge`
- `Page`
- DOM snapshot、stealth、daemon health 等工具

`BrowserBridge` 的职责是自动确保本地 daemon 和浏览器扩展可用：

1. 先检查 daemon health。
2. 如果 daemon ready，直接创建 `Page`。
3. 如果 daemon 存在但扩展未连接，判断是否版本过旧，必要时重启 daemon。
4. 如果没有 daemon，自动 spawn `daemon.ts` 或 `daemon.js`。
5. 轮询等待扩展连接，否则抛出带修复提示的 `BrowserConnectError`。

这解释了为什么 OpenCLI 能复用用户已登录浏览器：凭证不需要由 CLI 保存或传递，而是由 Browser Bridge 与扩展在本地浏览器上下文内完成操作。

Electron 应用集成走 CDP。`execution.ts` 会根据 `isElectronApp(cmd.site)` 判断站点是否为桌面应用；如果是，优先使用 `OPENCLI_CDP_ENDPOINT`，否则尝试自动探测 Electron debugging endpoint。

## 9. Pipeline 与 Adapter

项目支持两类适配器：

1. 编程式 adapter：在 `clis/<site>/<command>.js` 中调用 `cli({ ... func })` 注册命令。
2. 声明式 pipeline：命令携带 `pipeline`，交给 `src/pipeline/executor.ts` 执行。

pipeline 目录包含：

- `executor.ts`
- `registry.ts`
- `template.ts`
- `steps/browser.ts`
- `steps/fetch.ts`
- `steps/transform.ts`
- `steps/download.ts`
- `steps/intercept.ts`
- `steps/tap.ts`

`src/capabilityRouting.ts` 会根据命令和 pipeline step 判断是否需要浏览器会话。`navigate`、`click`、`type`、`wait`、`press`、`snapshot`、`evaluate`、`intercept`、`tap` 等步骤被视为 browser-only。

## 10. 外部 CLI 枢纽能力

`src/external.ts` 支持把外部工具注册到 OpenCLI 下。它会加载：

- 内置 `src/external-clis.yaml`
- 用户自定义 `~/.opencli/external-clis.yaml`

执行时会检查 binary 是否安装，若未安装且有配置，会尝试自动安装。安装命令解析使用 `execFileSync` 参数数组，并拒绝包含 shell 操作符的命令字符串，这比直接 shell 执行更安全。

这部分让 OpenCLI 不只是网站自动化工具，也能成为 `gh`、`docker` 等本地工具的统一发现入口。

## 11. 文档与 Skill 生态

项目文档比较完整：

- 根目录 README：英文与中文。
- `docs/`：VitePress 文档，包含 guide、advanced、developer、adapters 等。
- `skills/`：面向 AI Agent 的技能说明。

README 中提到的主要 skill：

- `opencli-browser`：实时操作任意网站。
- `opencli-explorer`：探索并生成可复用 CLI。
- `opencli-oneshot`：从 URL 和目标快速生成适配器。
- `opencli-usage`：使用已有内置适配器。

本地 `skills/` 目录实际有 6 个目录，说明项目把“给 AI Agent 的操作规范”作为一等产物维护。

## 12. 测试体系

`vitest.config.ts` 将测试拆为 5 类：

| 项目 | 范围 |
|---|---|
| unit | `src/**/*.test.ts` |
| extension | `extension/src/**/*.test.ts` |
| adapter | `clis/**/*.test.{ts,js}` |
| e2e | 浏览器、插件管理、输出格式、公开命令等 |
| smoke | `tests/smoke/**/*.test.ts` |

扩展 e2e 测试通过 `OPENCLI_E2E=1` 开启，避免日常测试跑大量依赖网络和登录态的站点。

这套测试分层是合理的：核心框架可以快速单测，适配器单独测，真实浏览器/站点交互放到 opt-in e2e。

## 13. 优势判断

OpenCLI 的主要优势：

1. 架构边界清楚：Registry、Discovery、Execution、Commander Adapter、Browser Bridge 各自职责明确。
2. 启动性能有意识优化：manifest、fast path、lazy import、并行 I/O 都在降低 CLI 冷启动成本。
3. 适配器生态规模大：当前 manifest 已有 604 个命令、100 个站点。
4. 面向 AI Agent 的接口明确：browser 命令提供结构化 DOM 快照和可组合操作，而不是只给截图。
5. 认证策略现实：复用浏览器登录态，避免直接处理用户密码或 token。
6. 错误输出结构化：便于 Agent 或脚本根据 error code 做后续修复。
7. 插件和用户适配器机制完整：支持本地覆盖、插件覆盖、热更新用户 adapter。

## 14. 潜在风险与关注点

1. Node 版本要求较新：`>=21.0.0` 可能限制部分用户环境。
2. 浏览器型命令对本地状态依赖强：Chrome/Chromium、扩展、daemon、登录态、目标站点页面变化都会影响稳定性。
3. 适配器规模大，维护成本高：100 个站点、600+ 命令意味着站点改版会持续制造维护压力。
4. 部分 e2e 测试天然不稳定：网络、登录态、风控、地区差异都可能造成 flaky。
5. 插件/用户 adapter 通过动态 import 执行本地代码：灵活但也需要用户信任插件来源。
6. Cookie/browser session 策略虽然不直接泄露凭证，但命令能力本身可以代表用户执行操作，需要良好的权限边界和审计意识。
7. 当前本地源码不是 git 仓库，后续如果要开发或提交 PR，建议重新 clone 原仓库或初始化版本控制。

## 15. 适合继续深入的方向

建议后续按目标选择研究路径：

1. 如果目标是“使用 OpenCLI”：优先跑 `npm install`、`npm run build`、`npm run dev -- list`，再安装 Browser Bridge 扩展并执行 `opencli doctor`。
2. 如果目标是“给某个网站写适配器”：重点阅读 `docs/developer/ts-adapter.md`、`docs/developer/architecture.md`、`skills/opencli-explorer/`，并参考 `clis/hackernews`、`clis/bilibili`、`clis/xiaohongshu` 等目录。
3. 如果目标是“接入 AI Agent 浏览器控制”：重点研究 `src/cli.ts` 中 `browser` 命令、`src/browser/page.ts`、`src/browser/dom-snapshot.ts`、`extension/src/background.ts`。
4. 如果目标是“提升稳定性”：优先看 `src/errors.ts`、`src/diagnostic.ts`、`src/doctor.ts`、adapter 测试和 `OPENCLI_DIAGNOSTIC=1` 工作流。
5. 如果目标是“扩展插件系统”：重点看 `src/discovery.ts` 的 `discoverPlugins()`、`src/plugin.ts`、`src/plugin-manifest.ts`、`src/plugin-scaffold.ts`。

## 16. 结论

OpenCLI 是一个以“确定性 CLI 化”为中心的自动化框架。它把网站操作、浏览器登录态、Electron CDP、本地 CLI、AI Agent skill 和适配器生成流程组合在一起，形成了一个面向人类和 Agent 的统一执行层。

从代码结构看，项目不是简单堆适配器，而是有明确的平台化意图：命令注册统一、执行链路统一、输出统一、错误统一、扩展机制统一。它的最大价值在于把原本脆弱的网页/桌面操作，逐步沉淀为可复用、可测试、可被 Agent 调用的命令接口。

短板也很清楚：稳定性高度依赖浏览器扩展、站点结构和登录态；大规模站点适配器需要持续维护。如果要在本地继续开发，建议先恢复 git 仓库上下文，再从一个 public 策略或低风险站点 adapter 入手验证完整开发流程。
