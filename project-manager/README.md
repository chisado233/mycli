# project-manager

## Summary

Register, query, and manage durable agent projects in `D:\agent_workspace`.

`project-manager` uses per-project `.agent-project/project.json` files as source of truth and a generated global `registry.json` as a query cache.

## Commands

```powershell
mycli project-manager init <project-root> --id <id> --name <name> --type <type> --mode finite|ongoing
mycli project-manager register <project-root>
mycli project-manager scan [roots...]
mycli project-manager refresh [roots...]
mycli project-manager list
mycli project-manager query [filters]
mycli project-manager get <id-or-name>
mycli project-manager status <id-or-name>
mycli project-manager update-status <id-or-name> [status fields]
mycli project-manager task-list <id-or-name>
mycli project-manager task-add <id-or-name> --title <title>
mycli project-manager task-update <id-or-name> <task-id> [fields]
mycli project-manager next-list <id-or-name>
mycli project-manager next-add <id-or-name> --title <title>
mycli project-manager next-update <id-or-name> <next-id> [fields]
mycli project-manager context-add <id-or-name> --title <title> --phase <phase>
mycli project-manager context-list <id-or-name> [--phase <phase>]
mycli project-manager context-get <id-or-name> <context-id>
mycli project-manager current <id-or-name>
mycli project-manager agent-guide <id-or-name> [--phase <phase>]
mycli project-manager maintenance-guide <id-or-name>
mycli project-manager native <args...>
```

## Command details

### Initialize and register

```powershell
mycli project-manager init <project-root> --id <id> --name <name> --type <type> --mode finite|ongoing [--register]
mycli project-manager register <project-root>
mycli project-manager scan [roots...]
mycli project-manager refresh [roots...]
```

`init` creates `.agent-project/project.json`, `status.md`, and support directories. Use `--register` to immediately add the project to the global registry.

### Query

```powershell
mycli project-manager query --name <text>
mycli project-manager query --type capability
mycli project-manager query --mode ongoing
mycli project-manager query --lifecycle active --phase operations
mycli project-manager query --health red --attention needs_maintenance
mycli project-manager query --tag automation
mycli project-manager query --json
```

Supported filters include `--id`, `--name`, `--type`, `--mode`, `--owner`, `--domain`, `--priority`, `--tag`, `--registration`, `--lifecycle`, `--phase`, `--activity`, `--health`, `--delivery`, `--attention`, `--last-run-status`, `--stale`, and `--missing`.

### Maintain status

```powershell
mycli project-manager update-status <id> --lifecycle active --phase construction --activity in_progress --summary "..."
```

### Maintain tasks and next actions

```powershell
mycli project-manager task-add <id> --title "Implement feature" --type implement --priority high --set-current
mycli project-manager task-list <id>
mycli project-manager task-update <id> task-0001 --status done

mycli project-manager next-add <id> --title "Run validation" --type validate --set-current
mycli project-manager next-list <id>
mycli project-manager next-update <id> next-0001 --status done
```

### Dynamic context and agent handoff

Use dynamic context to record stage-specific assumptions, requirements, feasibility findings, architecture notes, validation results, operation notes, and maintenance rules.

```powershell
mycli project-manager context-add <id> --title "Architecture decision context" --phase architecture --type architecture --summary "Use file-based registry first" --file README.md --tag registry
mycli project-manager context-list <id> --phase architecture
mycli project-manager context-get <id> context-0001
```

When an agent team takes over a project, start with:

```powershell
mycli project-manager current <id>
mycli project-manager agent-guide <id>
mycli project-manager agent-guide <id> --phase validation
mycli project-manager maintenance-guide <id>
```

`agent-guide` prints project management rules, current status, open tasks, open next actions, and dynamic context for the requested phase.

## Examples

```powershell
mycli project-manager init D:\agent_workspace\projects\daily-hot-news --id daily-hot-news --name "每日新闻热点收集" --type research --mode ongoing --register
mycli project-manager query --mode ongoing
mycli project-manager query --lifecycle active --phase operations
mycli project-manager query --attention needs_user_decision
mycli project-manager get daily-hot-news
mycli project-manager status daily-hot-news
mycli project-manager update-status daily-hot-news --health yellow --activity degraded --attention needs_maintenance
mycli project-manager task-add daily-hot-news --title "Fix source parser" --type maintenance --priority high --set-current
mycli project-manager next-add daily-hot-news --title "Check tomorrow's scheduled run" --type operation_check --set-current
```

## Important fields

- `project_mode`: `finite | ongoing`
- `lifecycle`: `proposed | planned | active | paused | completed | retired | archived`
- `phase`: `intake | requirements | feasibility | architecture | planning | construction | validation | launch | operations | maintenance | retirement | closure`
- `activity`: `queued | in_progress | scheduled | stable | running | waiting | blocked | degraded | paused | needs_attention`
- `health`: `green | yellow | red | gray`
- `delivery`: `none | concept | draft | prototype | usable | delivered | verified | published | deprecated`

Rule: ongoing projects should not be marked `completed`; they eventually become `retired`.

## Storage

Per-project truth:

```text
{project-root}\.agent-project\project.json
```

Global registry cache:

```text
D:\agent_workspace\capability-library\mycli\project-manager\registry.json
```

If registry and project files disagree, trust `project.json` and run `mycli project-manager refresh`.

## Safety notes

- `list`、`query`、`get`、`status`、`current`、`agent-guide`、`maintenance-guide` 是读取操作。
- `init` 会在项目目录下创建 `.agent-project/project.json`、`status.md` 和支持目录；通常配合 `--register`。
- `register` / `refresh` 会更新全局 registry cache；不会修改项目源码。
- `update-status`、`task-add`、`task-update`、`next-add`、`next-update`、`context-add` 会修改项目的 `.agent-project/project.json` 或相关状态文件。
- 对 ongoing 项目不要使用 `completed` 作为生命周期终态；停止服务时使用 `retired`。
