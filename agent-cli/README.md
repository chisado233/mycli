# agent-cli

## Summary

`agent-cli` unifies local coding-agent providers behind one `mycli` package.

Current sources:

- `claude`
- `codex`
- `opencode`

Current first-class features:

- sync provider agents into one mapped registry
- list, inspect, and select the current default agent
- run mapped agents with unified session parameters
- choose between streamed output and silent final-report output for tracked provider runs
- store tracked event streams for later session/round replay
- schedule future agent wake-ups for specific agents, models, sessions, and prompts through Windows Task Scheduler
- mount an agent/session with periodic lifecycle heartbeats that wake it only when needed
- create new `opencode` agents from a minimal template
- call configured LLM APIs directly by `provider/model` for text, vision, and image generation/editing
- pass through to native provider CLIs when needed

## Core Ideas

- `source`
  a provider such as `claude`, `codex`, or `opencode`
- `mapped agent`
  a unified agent name exposed by `agent-cli`, such as `claude/default`, `codex/default`, or `opencode/private-assistant`
- `registry`
  synchronized local cache of mapped agents
- `mapping-config.json`
  editable JSON that defines providers, sync behavior, and mapping rules

## Commands

- `mycli agent-cli agents`
- `mycli agent-cli current`
- `mycli agent-cli sync`
- `mycli agent-cli run ...`
- `mycli agent-cli session events ...`
- `mycli agent-cli schedule ...`
- `mycli agent-cli mount ...`
- `mycli agent-cli llm-call ...`
- `mycli agent-cli native ...`
- `mycli agent-cli codex-auto ...`
- `mycli agent-cli agent list`
- `mycli agent-cli agent show <name>`
- `mycli agent-cli agent use <name>`
- `mycli agent-cli agent create --source opencode ...`
- `mycli agent-cli source list`
- `mycli agent-cli source show <name>`

## Unified Run Parameters

The current first-pass unified run layer supports:

- `--agent`
- `--model`
- `--session_name`
- `--prompt`
- `--cwd`
- `--continue`
- `--session`
- `--fork`
- `--return_mode`

Examples:

```powershell
mycli agent-cli run --agent opencode/private-assistant --model openai/gpt-5.4 --session_name "repo-review" --prompt "review this repo" --return_mode stream
mycli agent-cli run --agent codex/default --model gpt-5.4 --session_name "bugfix-1" --prompt "fix failing tests"
mycli agent-cli run --agent claude/default --model sonnet --session_name "repo-review" --prompt "review this repo"
mycli agent-cli run --agent opencode/private-assistant --continue --prompt "continue and summarize progress" --return_mode silent
mycli agent-cli run --session ses_123 --fork --session_name "alt-fix" --prompt "try a safer implementation"
```

## Direct LLM Calls

`agent-cli llm-call` performs a single direct model API call without loading an
agent prompt, session, or tool loop. Models are resolved from:

- `D:\agent_workspace\config\models.json`

Use `--model <provider/model>` where `provider` is a provider key in that file
and `model` is a model key under the provider. The API protocol is inferred from
the provider's `npm` field; there is no separate protocol/provider argument.
`options.baseURL` and `options.apiKey` are read from `models.json`.

Useful discovery commands:

```powershell
mycli agent-cli llm-call --list-models
mycli agent-cli llm-call --model "custom-aiapi-meccy-top/gpt-5.4" --show-model
```

Common options:

- `--model <provider/model>`
- `--task chat|vision|image-generate|image-edit`
- `--prompt <text>`
- `--prompt-file <path>`
- `--prompt-url <url>`
- `--system <text>` / `--system-file <path>`
- `--image <path>` / `--image-url <url>`; repeat for multiple images
- `--output text|json|raw`
- `--stream`
- `--out <file>` / `--out-dir <dir>`
- `--size <size>`, `--n <number>`, `--temperature <number>`, `--max-tokens <number>`
- `--image-api auto|images|chat` for OpenAI-compatible image calls

If `--task` is omitted, text-only input defaults to `chat` and text plus images
defaults to `vision`. Image generation and image edit should be requested
explicitly with `--task image-generate` or `--task image-edit`.

Generated or edited images are saved to `--out`, `--out-dir`, or the default
directory:

- `D:\agent_workspace\tmp\llm-picture`

Examples:

```powershell
mycli agent-cli llm-call --model "volcengine-plan/doubao-seed-2.0-pro" --prompt "用三句话解释 Transformer"

mycli agent-cli llm-call --model "custom-aiapi-meccy-top/gpt-5.4" --prompt "请总结下面文档：" --prompt-file "D:\agent_workspace\tmp\doc.md"

mycli agent-cli llm-call --model "custom-aiapi-meccy-top/gemini-3-flash" --prompt "描述这张图" --image "D:\agent_workspace\tmp\a.png"

mycli agent-cli llm-call --model "custom-aiapi-meccy-top/gemini-2.5-flash-image" --task image-generate --prompt "雨夜东京街头，赛博朋克风格，电影感"

mycli agent-cli llm-call --model "MoreCode/gpt-image-2" --task image-generate --prompt "一只可爱的白色小猫，水彩风格" --size "1024x1024"

mycli agent-cli llm-call --model "custom-aiapi-meccy-top/gemini-2.5-flash-image" --task image-edit --prompt "把背景改成雨夜霓虹城市" --image "D:\agent_workspace\tmp\source.png" --out "D:\agent_workspace\tmp\edited.png"
```

Notes:

- `MoreCode/gpt-image-2` is available for image generation through the OpenAI-compatible MoreCode endpoint.
- When `--out`/`--out-dir` is omitted, generated images are saved under `D:\agent_workspace\tmp\llm-picture` with an automatic filename.
- Use `--output json` to get a normalized result object containing saved image paths, token usage, and the raw API response.

## Scheduled Agent Wake-ups

`agent-cli schedule` registers a Windows Task Scheduler task that calls back into `agent-cli run` at a future time. This is intended for agent self-reminders and delayed continuations, for example: “wake this agent/session in two hours and send this prompt”.

Examples:

```powershell
mycli agent-cli schedule add --in 2h --agent opencode/private-assistant --model MoreCode/gpt-5.4-pro --session ses_123 --prompt "Continue this task and report progress" --cwd D:\agent_workspace --return_mode silent
mycli agent-cli schedule add --at "2026-04-25 18:30" --agent claude/default --model sonnet --prompt "Run the evening review" --return_mode silent
mycli agent-cli schedule list
mycli agent-cli schedule cancel agentcli-continue-this-task-1a2b3c4d
```

Supported scheduling forms:

- `--in <delay>` for relative delay, e.g. `30m`, `2h`, `1d`
- `--at <datetime>` for an absolute local time parseable by PowerShell/.NET `DateTime`

The scheduled wake-up accepts the same main run options as `agent-cli run`: `--agent`, `--model`, `--session_name`, `--prompt`, `--cwd`, `--continue`, `--session`, `--fork`, and `--return_mode`. If `--agent` is omitted, the current default agent is resolved and stored at schedule creation time.

Schedule metadata is recorded under:

- `D:\agent_workspace\capability-library\mycli\agent-cli\state\schedules\`

The actual OS tasks are stored under Windows Task Scheduler path:

- `\agent-cli\`

## Mounted Agent Lifecycles

`agent-cli mount` keeps an agent/session under periodic lifecycle supervision. It creates a repeating Windows Task Scheduler heartbeat. Each tick checks whether the mounted session appears alive:

- if the session has a future `agent-cli schedule` wake-up for the same agent/session, the tick does nothing
- if the session has recent tracked work within `--quiet_minutes`, the tick does nothing
- otherwise the tick resumes the mounted session and sends a heartbeat prompt
- if the agent response contains the lifecycle-end marker, the mount clears the current session so the next heartbeat starts a fresh session for the same agent/model

Examples:

```powershell
mycli agent-cli mount add --agent opencode/private-assistant --model MoreCode/gpt-5.4-pro --session ses_123 --cwd D:\agent_workspace --interval_minutes 15 --quiet_minutes 30
mycli agent-cli mount add --agent opencode/private-assistant --model MoreCode/gpt-5.4-pro --session_name "persistent-worker" --interval_minutes 10
mycli agent-cli mount list
mycli agent-cli mount show agentmount-private-assistant-1a2b3c4d
mycli agent-cli mount logs agentmount-private-assistant-1a2b3c4d --last 3
mycli agent-cli mount logs agentmount-private-assistant-1a2b3c4d --report --last 1
mycli agent-cli mount logs agentmount-private-assistant-1a2b3c4d --raw --last 1
mycli agent-cli mount tick agentmount-private-assistant-1a2b3c4d
mycli agent-cli mount cancel agentmount-private-assistant-1a2b3c4d
```

Default heartbeat behavior tells the agent to:

1. inspect the current session context and continue useful pending work
2. create its own `agent-cli schedule` if it wants to pause and be woken later
3. stay idle or report status if no useful work exists
4. emit `AGENT_CLI_LIFECYCLE_END` when the current lifecycle/session should end and be replaced by a fresh session

Useful options:

- `--interval_minutes <n>`: heartbeat check interval; default `15`
- `--quiet_minutes <n>`: recent tracked work window considered alive; default `max(interval, 15)`
- `--heartbeat_prompt <text>`: custom heartbeat prompt
- `--end_marker <text>`: custom lifecycle-end marker; default `AGENT_CLI_LIFECYCLE_END`

Mount metadata is recorded under:

- `D:\agent_workspace\capability-library\mycli\agent-cli\state\mounts\`

The repeating OS tasks are stored under Windows Task Scheduler path:

- `\agent-cli\mount\`

Mount log commands:

- `mount show <mount-id>` prints mount state, task state, agent/model/session, last tick, and last run id.
- `mount logs <mount-id>` prints recent tracked run summaries and report previews.
- `mount logs <mount-id> --paths` prints the underlying `raw.log`, `events.jsonl`, and `report.txt` paths.
- `mount logs <mount-id> --report|--raw|--events --last <n>` prints the selected log content.

## Claude Support

Claude support is now provider-level rather than purely static:

- discovery: `agent-cli` syncs Claude agents from `claude agents`
- fallback: `claude/default` remains available if discovery yields nothing
- run mode: tracked non-interactive Claude runs via `claude --print`
- return modes:
  - `--return_mode silent` → Claude JSON result capture
  - `--return_mode stream` → Claude `stream-json` capture
- native passthrough: supported through `mycli agent-cli native`, with `--` required before raw provider args
- session continuation: mapped to Claude `--continue`, `--resume`, and `--fork-session`
- `--continue` follows Claude CLI's own idea of the latest session; for precise resume/fork behavior, prefer `--session <id>`
- working directory: applied at the process level when `--cwd` is provided

Examples:

```powershell
mycli agent-cli sync
mycli agent-cli run --agent claude/default --prompt "Reply with OK only"
mycli agent-cli run --agent claude/default --return_mode stream --prompt "Reply with READY only"
mycli agent-cli run --agent claude/default --session_name "claude-agent-cli-test" --prompt "Say FIRST only"
mycli agent-cli run --agent claude/default --session c6eb2358-7c56-441d-bbdf-38532e408320 --prompt "Say RESUMED only"
mycli agent-cli run --agent claude/default --session c6eb2358-7c56-441d-bbdf-38532e408320 --fork --prompt "Say FORKED only"
mycli agent-cli run --agent claude/default --continue --prompt "Continue Claude's latest session"
mycli agent-cli run --agent claude/explore --prompt "Summarize this workspace"
mycli agent-cli native --agent claude/default -- --help
```

## OpenCode and Claude Return Modes

`agent-cli` exposes two explicit output modes for tracked `opencode/*` and `claude/*` runs:

- `--return_mode stream`
  - prints structured event flow to the terminal as it happens
  - intended for debugging agent behavior
- `--return_mode silent`
  - suppresses live event output
  - prints only the final report plus session metadata at the end
  - intended for calling `agent-cli` from other agents without flooding context

Important:

- `silent` does **not** mean "do not record"
- tracked provider runs are still captured into local run-state files for later replay
- current structured event capture is implemented for `opencode/*` and `claude/*`; other providers keep their existing behavior

## Session Event Replay

`agent-cli` stores tracked run records under a local run-state directory and can replay stored event streams by session and round range.

Examples:

```powershell
mycli agent-cli session events --session ses_123 --last 1
mycli agent-cli session events --session ses_123 --last 3
mycli agent-cli session events --session ses_123 --round 2
mycli agent-cli session events --session ses_123 --all
```

Semantics:

- one `run` call = one recorded `round`
- `--last <n>` returns the latest `n` recorded rounds for that session
- `--round <n>` returns one specific recorded round
- `--all` returns all recorded rounds for that session

## Agent Naming

Mapped agent names keep the source prefix:

- `claude/default`
- `claude/explore`
- `claude/plan`
- `codex/default`
- `opencode/build`
- `opencode/private-assistant`

## Native Access

If the unified `run` layer is too narrow for a task, use native passthrough.

Examples:

```powershell
mycli agent-cli native --agent opencode/private-assistant -- run "analyze this repo" --format json
mycli agent-cli native --agent codex/default -- exec "review this repo"
mycli agent-cli native --agent claude/default -- --print "review this repo"
mycli agent-cli native --agent claude/default -- --version
mycli agent-cli native --source opencode -- agent list
```

## Agent Creation

First version rules:

- `opencode` supports `agent create`
- `claude` does not support `agent create` yet
- `codex` does not support `agent create` yet

Example:

```powershell
mycli agent-cli agent create --source opencode --name my-agent --description "Repository maintenance agent" --mode primary --tools bash,read,edit
```

This writes a minimal OpenCode native agent file into:

- `C:\Users\38188\.config\opencode\agent`

Then it auto-syncs the registry.

## Config Files

- `D:\agent_workspace\capability-library\mycli\agent-cli\mapping-config.json`
- `D:\agent_workspace\capability-library\mycli\agent-cli\registry.json`
- `D:\agent_workspace\capability-library\mycli\agent-cli\requirements.md`

## State Paths

- `D:\agent_workspace\capability-library\mycli\agent-cli\registry.json` — synchronized mapped-agent registry and current default agent.
- `D:\agent_workspace\capability-library\mycli\agent-cli\state\schedules\` — metadata for future `schedule` wake-ups.
- `D:\agent_workspace\capability-library\mycli\agent-cli\state\mounts\` — metadata for mounted lifecycle heartbeats.
- Tracked run records and event streams are stored under this package's local run-state directories and can be inspected with `mycli agent-cli session events ...`.

## Safety Notes

- `--return_mode silent` suppresses live event output but still records run events locally.
- `schedule add` creates a Windows Task Scheduler task under `\agent-cli\`; cancel it with `schedule cancel <id>` when no longer needed.
- `mount add` creates a repeating Windows Task Scheduler heartbeat under `\agent-cli\mount\`; cancel it with `mount cancel <id>` when no longer needed.
- Cancelling a schedule or mount removes future wake-ups; it does not forcibly kill an agent process that is already running.
- `llm-call` reads API keys from `D:\agent_workspace\config\models.json`; do not print or expose keys.
- `agent create --source opencode ...` writes native OpenCode agent files into `C:\Users\38188\.config\opencode\agent`.

## Reserved Commands

- `workflow` is reserved for a later phase; use `mycli agent-workflow ...` for real workflow execution.
- `recommend` is reserved for a later phase; do not rely on it for agent selection yet.

## Provider Environment

Providers can inject environment variables into native CLI launches through `mapping-config.json`.

Current setup:

- `codex` defaults to `auto` proxy mode
- `auto` mode reads Clash `mixed-port` from `C:\Users\38188\.config\clash\config.yaml`
- `auto` mode reuses `D:\agent_workspace\capability-library\mycli\clash\state\auto-state.json`
- if the Clash auto worker is configured but stopped, `agent-cli` will start it before launching Codex

That means:

- `mycli agent-cli run --agent codex/default ...`
- `mycli agent-cli native --agent codex/default -- ...`

will automatically run with the configured Clash proxy environment.

To configure the Codex auto node strategy directly:

```powershell
mycli agent-cli codex-auto status
mycli agent-cli codex-auto use GLOBAL 日本 60 5000
mycli agent-cli codex-auto stop
```

## Notes

- `workflow` is reserved for a later phase.
- `recommend` is reserved for a later phase.
- `session_name` is currently native for `opencode` and `claude`, but only tracked locally for `codex`.
- for OpenCode, `--return_mode` should be passed explicitly as `stream` or `silent`.
