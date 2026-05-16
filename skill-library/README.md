# skill-library

`mycli skill-library` 用于搜索、列出、注册本地 skill 索引。这里描述的是 **mycli 子包本身**，不是 `D:\agent_workspace\capability-library\skill-library` 目录内部每个具体技能的说明。

## Source and registry

```text
Skill source: D:\agent_workspace\capability-library\skill-library
Registry:     D:\agent_workspace\capability-library\mycli\skill-library\registry.json
Script:       D:\agent_workspace\capability-library\mycli\skill-library\scripts\skill-library.ps1
```

`registry.json` 是生成/索引数据；不要手工编辑作为主方案。需要刷新索引时运行 `register`。

## Usage

```powershell
mycli skill-library --help
mycli skill-library list
mycli skill-library skills
mycli skill-library search <keyword>
mycli skill-library search opencode
mycli skill-library register
mycli skill-library register <path>
mycli skill-library register D:\agent_workspace\capability-library\skill-library\opencode-capability-skill
```

注意：`mycli skill-library list` 是 mycli 框架的包级命令清单，不是列出技能。列出已注册技能用 `mycli skill-library skills`。

## Commands

### `skills`

读取 registry，列出已注册 skill 的：

- 名称
- 简介
- 主体摘要
- `skillMdPath`
- `skillRootPath`

### `search <keyword>`

按 skill 名称搜索。能直接匹配时返回匹配结果；搜不到时返回近似结果与路径。

### `register [path]`

刷新本地 skill 索引。

- 不传 `path`：扫描默认 source 下所有 `SKILL.md`。
- 传文件路径：注册指定 `SKILL.md`。
- 传目录路径：递归扫描目录下的 `SKILL.md`。

## Common flows

新增、删除、移动或修改 skill 后：

```powershell
mycli skill-library register
mycli skill-library skills
mycli skill-library search <keyword>
```

维护本 mycli 子包的发现/注册逻辑时，优先看：

```text
D:\agent_workspace\capability-library\mycli\skill-library\cli.package.json
D:\agent_workspace\capability-library\mycli\skill-library\scripts\skill-library.ps1
D:\agent_workspace\capability-library\mycli\skill-library\registry.json
```

## Safety notes

- `skills` / `search` 是只读操作。
- `register` 只刷新索引文件，不复制、不安装、不删除 skill 源文件。
- 需要使用某个具体 skill 时，再通过 `search` / `skills` 找到目标路径并读取该 skill 的 `SKILL.md`；不要把内部具体技能逐个写进本 README。
