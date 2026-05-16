# QQ channel

QQ channel integration using NapCat OneBot v11 and `qq-bridge.js` to forward QQ messages to an OpenCode agent.

## Source

`D:\agent_workspace\capability-library\mycli\channels\QQ`

## Main files

- `bridge.config.json` — bridge configuration, including wake word, agent, default group, and NapCat WebSocket URL.
- `qq-bridge.js` — OneBot WebSocket bridge that builds prompts and calls OpenCode.
- `napcat\` — NapCat runtime.
- `logs\` — bridge/NapCat logs.
- `state\` — session, PID, and task state files.

## Commands

```powershell
mycli channels QQ start-detached [qq]
mycli channels QQ stop-detached
mycli channels QQ status-detached

mycli channels QQ install-task [qq]
mycli channels QQ start-task
mycli channels QQ stop-task
mycli channels QQ status-task

mycli channels QQ avatar <qq> [size] [out]
mycli channels QQ members [group-id] [--format json|table|md] [--out <file>] [--raw]
```

## Typical usage

Start in detached mode:

```powershell
mycli channels QQ start-detached
mycli channels QQ status-detached
```

Install and use Windows Task Scheduler mode:

```powershell
mycli channels QQ install-task
mycli channels QQ start-task
mycli channels QQ status-task
```

Stop everything:

```powershell
mycli channels QQ stop-detached
mycli channels QQ stop-task
```

Download a QQ avatar:

```powershell
mycli channels QQ avatar 381889153
mycli channels QQ avatar 381889153 100
mycli channels QQ avatar 381889153 640 D:\agent_workspace\tmp\qq-avatar\381889153.jpg
```

List QQ group members through NapCat `get_group_member_list`:

```powershell
mycli channels QQ members
mycli channels QQ members 895102465 --format json
mycli channels QQ members 895102465 --format md --out D:\agent_workspace\tmp\qq-members.md
```

Member fields include `user_id` (QQ号), `nickname`, `card` (群名片), `role`, `join_time`, `last_sent_time`, and `is_robot`.
