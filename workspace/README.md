# workspace

`workspace` 管理 `D:\agent_workspace` 的标准 runtime / data 路径。它把源码、能力本体与运行状态、日志、缓存、配置、采集数据、下载物、备份等中间产物分开，避免这些内容散落到 `capability-library` 或项目源码树里。

## Commands

```powershell
mycli workspace root
mycli workspace paths
mycli workspace paths --json
mycli workspace path logs mycli channels/QQ
mycli workspace inspect mycli channels/QQ
mycli workspace inspect projects daily-hot-news --json
mycli workspace config-path mycli channels/QQ
mycli workspace config mycli channels/QQ
mycli workspace config mycli channels/QQ --json
mycli workspace ensure
mycli workspace ensure mycli channels/QQ
mycli workspace ensure-package channels/QQ
mycli workspace ensure-project daily-hot-news
mycli workspace ensure-project D:\agent_workspace\projects\daily-hot-news
mycli workspace ensure-skill novel-writing
mycli workspace ensure-skill D:\agent_workspace\capability-library\skill-library\novel-writing\SKILL.md
mycli workspace ui start
mycli workspace ui status
mycli workspace ui open 46000
mycli workspace ui stop
```

## Standard roots

```text
D:\agent_workspace\tmp        # 临时实验、一次性中间产物
D:\agent_workspace\var        # 运行时状态、session、pid、队列状态
D:\agent_workspace\logs       # 日志、stdout/stderr、trace
D:\agent_workspace\cache      # 可重建缓存
D:\agent_workspace\config     # 本机配置、密钥、账号、本机路径配置
D:\agent_workspace\data       # 采集数据、语料、数据集、exports
D:\agent_workspace\downloads  # 下载物、安装包、压缩包
D:\agent_workspace\backups    # 备份、快照
D:\agent_workspace\ui         # UI 接入清单和按对象组织的 UI 元数据
D:\agent_workspace\tools      # 外部工具本体，可选
D:\agent_workspace\models     # 模型文件，可选
```

`tmp`、`var`、`logs`、`cache`、`config`、`data`、`downloads`、`backups`、`ui` 下固定使用这些 namespace：

```text
mycli/
projects/
skills/
agents/
shared/
```

## Path convention

mycli 包：

```text
D:\agent_workspace\logs\mycli\channels\QQ
D:\agent_workspace\var\mycli\channels\QQ
D:\agent_workspace\cache\mycli\github
D:\agent_workspace\config\mycli\remote-pc
```

projects：

```text
D:\agent_workspace\logs\projects\daily-hot-news
D:\agent_workspace\var\projects\daily-hot-news
D:\agent_workspace\data\projects\daily-hot-news
```

skills：

```text
D:\agent_workspace\data\skills\novel-writing
D:\agent_workspace\cache\skills\indextts
D:\agent_workspace\config\skills\some-skill
```

## Default policy

- 源码树只存放可长期维护、应跨机器同步的源码、文档、配置模板、命令注册和少量必要索引。
- 运行状态写入 `var`。
- 日志写入 `logs`。
- 缓存写入 `cache`。
- 本机真实配置、token、密钥、账号和本机路径配置写入 `config`，默认不入 Git；可同步模板放源码树的 `*.example.*` 或 `templates/`。
- 采集数据、语料、数据集写入 `data`。
- 下载物、安装包、外部压缩包写入 `downloads`。
- 备份和快照写入 `backups`。
- 一次性实验和临时中间产物写入 `tmp`。
- 不要默认把这些内容写回 `capability-library` 或项目源码目录。

## Registering new objects

新增 mycli 包后运行：

```powershell
mycli workspace ensure-package <package-path>
```

新增 project 后运行：

```powershell
mycli workspace ensure-project <project-id-or-path>
```

新增 skill 后运行：

```powershell
mycli workspace ensure-skill <skill-name-or-path>
```

这些命令会为对象创建 `tmp`、`var`、`logs`、`cache`、`config`、`data`、`downloads`、`backups`、`ui` 下的对应空目录。

`--help` / `-h` / `help` 永远只用于查看帮助；即使附加在 `ensure-package`、`ensure-project`、`ensure-skill` 等子命令后，也不能被当作对象名生成目录。

## Workspace UI

`workspace ui` 是 workspace 包内置的统一 UI 总控台 / launcher。目录：

```text
D:\agent_workspace\capability-library\mycli\workspace\ui
```

常用命令：

```powershell
mycli workspace ui start
mycli workspace ui start 46000
mycli workspace ui status
mycli workspace ui open
mycli workspace ui open 46000
mycli workspace ui stop
```

默认地址：`http://127.0.0.1:46000`，健康快照 API：`/api/snapshot`。

`workspace ui` 只做统一发现和调度，不实现具体业务 UI。具体子 UI 仍由对应包或项目自己实现，例如 `channels monitor-ui`、`cron ui`、`startup ui`。

子 UI 接入清单统一放在：

```text
D:\agent_workspace\ui\mycli\*.json
D:\agent_workspace\ui\projects\*.json
D:\agent_workspace\ui\mycli\cron\ui.json
D:\agent_workspace\ui\mycli\startup\ui.json
```

每个 manifest 用 `target.domain` 与 `target.path` 绑定到具体 mycli 包或项目节点，例如：

```json
{
  "id": "mycli.channels.monitor-ui",
  "name": "Channels Monitor UI",
  "target": { "domain": "mycli", "path": "channels/monitor-ui" },
  "url": "http://127.0.0.1:45990",
  "health": { "url": "http://127.0.0.1:45990/api/snapshot" },
  "commands": {
    "start": ["channels", "monitor-ui"],
    "stop": ["channels", "monitor-ui-stop"],
    "open": ["channels", "monitor-ui-open"]
  }
}
```

`ui` 和 `tmp`、`cache` 等同级，并使用同样的 namespace 结构：`ui/mycli/<package-path>/ui.json`、`ui/projects/<project-id>/ui.json`、`ui/skills/<skill-name>/ui.json`、`ui/agents/<agent-name>/ui.json`、`ui/shared/<name>/ui.json`。为兼容简单单文件登记，`ui/mycli/<package-ui>.json` 也会被识别，但新接入优先使用目录树形式。

为兼容旧接入方式，服务仍读取节点目录下的 `.agent-ui.json` / `ui.manifest.json`，但新接入统一写入 `D:\agent_workspace\ui\...`。

## workspace-config

每个已注册对象都应有一个自动生成的 `workspace-config.json`，默认位于该对象的 `config` 目录：

```text
D:\agent_workspace\config\mycli\<package-path>\workspace-config.json
D:\agent_workspace\config\projects\<project-id>\workspace-config.json
D:\agent_workspace\config\skills\<skill-name>\workspace-config.json
```

可用命令：

```powershell
mycli workspace config-path mycli channels/QQ
mycli workspace config mycli channels/QQ
mycli workspace config mycli channels/QQ --json
```

`ensure`、`ensure-package`、`ensure-project`、`ensure-skill` 会在创建标准目录时同步写入 `workspace-config.json`。典型内容：

```json
{
  "schema": "mycli.workspace-config.v1",
  "domain": "mycli",
  "name": "channels/QQ",
  "workspaceRoot": "D:\\agent_workspace",
  "paths": {
    "tmp": "D:\\agent_workspace\\tmp\\mycli\\channels\\QQ",
    "var": "D:\\agent_workspace\\var\\mycli\\channels\\QQ",
    "logs": "D:\\agent_workspace\\logs\\mycli\\channels\\QQ",
    "cache": "D:\\agent_workspace\\cache\\mycli\\channels\\QQ",
    "config": "D:\\agent_workspace\\config\\mycli\\channels\\QQ",
    "data": "D:\\agent_workspace\\data\\mycli\\channels\\QQ",
    "downloads": "D:\\agent_workspace\\downloads\\mycli\\channels\\QQ",
    "backups": "D:\\agent_workspace\\backups\\mycli\\channels\\QQ",
    "ui": "D:\\agent_workspace\\ui\\mycli\\channels\\QQ"
  }
}
```

mycli 包脚本规则：

- 默认读取本包的 `workspace-config.json` 获取路径。
- 不要把 tmp、logs、downloads、cache、var、data、config 等产物路径写死到脚本中。
- 注册命令的 `--help` 必须是非侵入式的：只能输出帮助/参数说明，不得启动 UI/服务、发起远程连接、写 state/log/tmp/cache、安装依赖、构建、下载、删除或修改外部环境。
- 源码包目录只放源码、README、命令注册、模板、静态资源和应随 Git 同步的轻量文件。
- 本机真实配置、token、secret、账号、本机路径配置写入 `paths.config`。
- 中间产物写入 `paths.tmp`，运行状态写入 `paths.var`，日志写入 `paths.logs`，可重建缓存写入 `paths.cache`，有效长期数据写入 `paths.data`。

PowerShell 脚本推荐直接复用公共 helper：

```powershell
$PackageRoot = Split-Path -Parent $PSScriptRoot
$WorkspaceConfigModule = Join-Path (Split-Path -Parent $PackageRoot) "common\workspace-config.ps1"
. $WorkspaceConfigModule
$WorkspaceConfig = Get-MyCliWorkspaceConfig -PackagePath 'channels/QQ'
$ConfigDir = [string]$WorkspaceConfig.paths.config
$StateDir = [string]$WorkspaceConfig.paths.var
$LogDir = [string]$WorkspaceConfig.paths.logs
```

JavaScript / Node 脚本推荐读取同一个 JSON：

```javascript
const fs = require('fs');
const path = require('path');
const workspaceConfigPath = path.join('D:\\agent_workspace', 'config', 'mycli', 'channels', 'QQ', 'workspace-config.json');
const workspaceConfig = JSON.parse(fs.readFileSync(workspaceConfigPath, 'utf8'));
const configDir = workspaceConfig.paths.config;
const stateDir = workspaceConfig.paths.var;
const logDir = workspaceConfig.paths.logs;
```

新增/重整包的标准流程：

1. 注册子包并维护 `cli.package.json` / `README.md`。
2. 运行 `mycli workspace ensure-package <package-path>` 生成 workspace 目录和 `workspace-config.json`。
3. 脚本读取 workspace-config，把 config/data/var/logs/cache/tmp/downloads/backups 写入对应位置。
4. 把可同步配置模板留在源码树，例如 `*.example.*`、`templates/`。
5. 把本机真实配置和有效 registry/cache/data 迁移到 workspace 对应目录。
6. 删除旧运行记录、无效 tmp、旧 logs、可重建 cache；删除前必须按包 inventory 文件名和相对路径，不允许批量乱删。
7. 回归 `mycli <package> --help`、`mycli <package> list` 和代表性只读命令。
8. 对所有注册命令执行 `mycli <package> <command> --help` 逐条验证，确认不会误执行真实动作，也不会生成 `--help` 目录。
