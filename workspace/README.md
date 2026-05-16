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
mycli workspace ensure
mycli workspace ensure mycli channels/QQ
mycli workspace ensure-package channels/QQ
mycli workspace ensure-project daily-hot-news
mycli workspace ensure-project D:\agent_workspace\projects\daily-hot-news
mycli workspace ensure-skill novel-writing
mycli workspace ensure-skill D:\agent_workspace\capability-library\skill-library\novel-writing\SKILL.md
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
D:\agent_workspace\tools      # 外部工具本体，可选
D:\agent_workspace\models     # 模型文件，可选
```

`tmp`、`var`、`logs`、`cache`、`config`、`data`、`downloads`、`backups` 下固定使用这些 namespace：

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

这些命令会为对象创建 `tmp`、`var`、`logs`、`cache`、`config`、`data`、`downloads`、`backups` 下的对应空目录。
