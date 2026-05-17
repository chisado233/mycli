# mycli workspace-config 与包拆解迁移计划

日期：2026-05-16  
范围：仅针对新版 `D:\agent_workspace\capability-library\mycli`。`D:\agent_workspace\capability-library\mycli-old` 是回退与历史保留副本，禁止修改、删除、迁移或清理。

## 1. 当前进度

已完成：

- 新版 `mycli` 已推送到 GitHub 私有仓库：`https://github.com/chisado233/mycli`。
- 已创建旧版保留 worktree：`D:\agent_workspace\capability-library\mycli-old`。
- 已在新版 `mycli` 中加入 `mycli-old.ps1` / `mycli-old.cmd` wrapper。
- 已新增 `mycli workspace` 包，用于统一生成与查询 workspace 路径。
- 已确定标准 workspace 顶层类型：
  - `tmp`
  - `var`
  - `logs`
  - `cache`
  - `config`
  - `data`
  - `downloads`
  - `backups`
- 已确定 scoped namespace：
  - `mycli`
  - `projects`
  - `skills`
  - `agents`
  - `shared`
- 已为新版 `mycli` 的 31 个包生成标准 workspace 目录，验证结果为 `31 packages * 8 types = 248 dirs`。
- 已清空 `D:\agent_workspace\tmp` 和 `D:\agent_workspace\downloads` 中无关内容，仅保留标准 namespace 空目录：`agents`、`mycli`、`projects`、`shared`、`skills`。

## 2. 新增规则：workspace-config

### 2.1 规则目标

每个 `mycli` 包、project、skill、agent 都应有自己的默认 config 区域，并有一份自动生成的 workspace-config，用来记录该对象在 workspace 中的各类路径。

脚本不得把中间产物、下载物、日志、状态、缓存、数据等路径写死在源码包目录里；脚本应默认读取对应对象的 workspace-config，再把产物写入 workspace-config 指向的位置。

### 2.2 默认路径模型

对 `mycli` 包 `<package-path>`：

```text
D:\agent_workspace\<type>\mycli\<package-path>\
```

其中 `<type>` 包括：

```text
tmp, var, logs, cache, config, data, downloads, backups
```

默认 workspace-config 建议放在：

```text
D:\agent_workspace\config\mycli\<package-path>\workspace-config.json
```

该文件记录此包可用的标准路径，例如：

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
    "backups": "D:\\agent_workspace\\backups\\mycli\\channels\\QQ"
  }
}
```

### 2.3 脚本撰写规则

为 `mycli` 包编写脚本时必须遵守：

1. 源码包目录只放源码、README、命令注册文件、模板、静态资源，以及确实需要随 Git 同步的轻量文件。
2. 本机真实配置、账号、token、端口、本机路径等放入 `config` 对应目录，默认不入 Git。
3. 长期有效数据、采集结果、registry/search/export 等按性质放入 `data`。
4. pid、session、queue、mount/scheduler state 等运行时状态放入 `var`。
5. stdout/stderr、detached logs、trace 等放入 `logs`。
6. 可重建缓存放入 `cache`。
7. 临时实验、中间输入输出、一次性 patch/prompt/sandbox 放入 `tmp`。
8. 下载物、release artifact、安装包、外部原始包放入 `downloads`。
9. 迁移前快照、导出副本、备份放入 `backups`。
10. 脚本默认先读取本包 workspace-config；如果不存在，应通过 `mycli workspace ensure-package <package-path>` 或等价内部函数生成。
11. 不得在脚本中写死 `D:\agent_workspace\tmp\...`、`D:\agent_workspace\downloads\...` 等路径；应从 workspace-config 的 `paths` 字段取得。

## 3. 新的子包注册流程

新版流程应调整为：

1. 子包注册：创建包目录、`cli.package.json`、`README.md`。
2. workspace 目录生成：为该包生成 `tmp/var/logs/cache/config/data/downloads/backups` 对应目录。
3. workspace-config 生成：在 `config\mycli\<package-path>\workspace-config.json` 写入标准路径映射。
4. 脚本撰写：脚本读取 workspace-config，不再把运行产物写入源码包目录。
5. 命令注册：把脚本注册进 `cli.package.json`。
6. 文档更新：README 说明该包使用 workspace-config 的路径规则。
7. 验证：执行 `--help`、`list`、代表性只读命令，并确认产物写入 workspace 对应位置。

后续应把 `mycli package register` / `register-full` 与 `mycli workspace ensure-package`、workspace-config 生成流程集成起来。

## 4. 即将删除的废弃新版包

仅删除新版 `mycli` 下的废弃包，不触碰 `mycli-old`：

```text
D:\agent_workspace\capability-library\mycli\opencode
D:\agent_workspace\capability-library\mycli\task-hall
D:\agent_workspace\capability-library\mycli\PowerShell-cli
```

删除前需要再次确认：这些包在新版 `mycli` 中确认为废弃，且可由 `mycli-old` 或其他新版包替代。

## 5. 剩余包拆解迁移原则

目标：把剩余新版 `mycli` 包中的有效 config/data 迁移到 workspace 对应位置；无效 tmp、旧运行记录、中间过程输出、历史日志、pid/session 等可以删除。

严格要求：不允许“一通乱删”。对每个包操作时必须先做精准 inventory。

对每个包执行以下流程：

1. 获取该包目录下所有文件名与相对路径。
2. 按文件名、目录名、扩展名、内容意图判断分类：
   - 源码/命令注册/README：保留在包内。
   - config：迁移到 `D:\agent_workspace\config\mycli\<package-path>`。
   - data：迁移到 `D:\agent_workspace\data\mycli\<package-path>`。
   - var：运行状态可迁移或删除；旧运行记录默认删除。
   - logs：历史日志默认删除，除非有明确审计/诊断价值。
   - cache：可重建则删除。
   - tmp：删除。
   - downloads：真实下载物迁移到 downloads；无效下载中间件删除。
   - backups：迁移前必要快照放到 backups。
3. 给出该包的迁移/删除清单。
4. 执行精准移动或删除。
5. 修改该包脚本，使其读取 workspace-config。
6. 运行该包 `--help`、`list`、代表性只读命令。
7. 检查源码包目录不再新增 runtime/config/data 输出。

## 6. 优先处理顺序

建议顺序：

1. 完成 workspace-config 能力：生成、读取、查询、文档。
2. 删除明确废弃包：`opencode`、`task-hall`、`PowerShell-cli`。
3. 对剩余包逐个 inventory。
4. 先迁移风险较低、结构清晰的包。
5. 再处理含外部服务、账号、bridge、daemon、startup/cron 的包。
6. 每个包完成后立即验证，不批量赌结果。

## 7. 下一步任务清单

- [ ] 实现或扩展 `mycli workspace`：生成 `workspace-config.json`。
- [ ] 更新 `mycli workspace` README 与顶层 README，写明 workspace-config 规则。
- [ ] 更新 `common/technical-manual.md`，把新注册流程改为 workspace-aware。
- [ ] 同步更新 `C:\Users\38188\.config\opencode\agent\private-assistant.md` 中的重要长期规则。
- [ ] 删除新版废弃包：`opencode`、`task-hall`、`PowerShell-cli`。
- [ ] 重新枚举剩余包列表。
- [ ] 逐包生成文件 inventory，并按 inventory 精准迁移 config/data、删除无效 runtime/tmp/log/cache 输出。
- [ ] 逐包改脚本，使中间产物路径从 workspace-config 读取。
- [ ] 全量回归 `mycli <package> --help`、`mycli <package> list` 与代表性只读命令。
- [ ] 最终检查 `mycli-old` 未被修改。
