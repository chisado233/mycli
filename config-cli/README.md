# config-cli

`config-cli` 用于自动发现 `D:\agent_workspace\config` 下的 JSON 配置文件，并返回每个配置的名称、描述和路径。

检测是**递归且实时**的：只要把新的 `*.json` 文件放到 `D:\agent_workspace\config` 或其任意子目录下，下一次运行 `config-cli` 命令时就会自动检测到，不需要手工注册单个 config 文件。

## Config Contract

每个配置文件必须是 JSON 文件，并且必须在顶层包含 `description` 字段：

```json
{
  "description": "这个配置文件的用途说明"
}
```

配置名称默认取相对路径（不含 `.json`）。例如 `D:\agent_workspace\config\agents\models.json` 的默认名称是 `agents\models`。如果 JSON 顶层包含非空 `name` 字段，则优先使用该字段作为配置名称。

## Usage

```powershell
mycli config-cli --help
mycli config-cli configs
mycli config-cli configs --json
mycli config-cli find models
mycli config-cli find models --json
mycli config-cli validate
mycli config-cli native --help
mycli config-cli native list
```

## Commands

- `configs` — 列出所有配置的 `name`、`description`、`path`。
- `find <name>` — 按配置名或文件名查找配置，并返回 `name`、`description`、`path`。
- `validate` — 校验所有 JSON 配置是否都有顶层 `description` 字段。
- `native` — 原样透传给底层 `config-cli.ps1`，例如 `mycli config-cli native list`。

注意：`mycli config-cli list` 是 mycli 的包级内置列表命令，会显示该包的命令清单；列出配置请用 `mycli config-cli configs` 或 `mycli config-cli native list`。

## Config Root

- `D:\agent_workspace\config`

## Auto Detection

- 自动递归扫描：`D:\agent_workspace\config\**\*.json`
- 每次执行命令时重新扫描，不维护静态索引。
- 每个 JSON 顶层必须有非空 `description` 字段；否则 `configs` / `find` / `validate` 会报错并提示具体路径。
- 输出字段固定为：`name`、`description`、`path`。

## Safety notes

- `configs`、`find`、`validate` 都是只读命令，不修改 JSON 配置文件。
- `--json` 可用于 `configs` 和 `find`，方便 agent 或脚本解析输出。
- 配置文件可能包含 key、token、路径等敏感信息；`config-cli` 只输出名称、描述和路径，不打印完整配置内容。
