# clawhub

## Summary

`mycli clawhub` wraps the npm `clawhub` CLI through `npx`. Use it to search, inspect, install, update, uninstall, sync, and publish OpenClaw/ClawHub skills.

Upstream package:

- npm: `clawhub`
- homepage: `https://clawhub.ai`
- repository: `https://github.com/openclaw/clawhub`

The upstream CLI also exposes the legacy `clawdhub` binary, but this package standardizes on `clawhub`.

## Default Behavior

The wrapper runs:

```powershell
npx clawhub ...
```

If `clawhub` is not installed globally, `npx` can download and run the current npm package on demand.

ClawHub defaults:

- site: `https://clawhub.ai`
- workdir: current directory unless `--workdir <dir>` or `CLAWHUB_WORKDIR` is set
- install dir: `skills` under workdir unless `--dir <dir>` is set
- config path on Windows: `%APPDATA%\clawhub\config.json`

## State and install paths

- Upstream config: `%APPDATA%\clawhub\config.json`
- Default install path: `<workdir>\skills\<slug>`
- Local capability-library install path: `D:\agent_workspace\capability-library\skill-library\<slug>` when using `--workdir D:\agent_workspace\capability-library --dir skill-library`

## Important Workspace Convention

For temporary experiments, install into `D:\agent_workspace\tmp\...`:

```powershell
mycli clawhub install copenhagen-denmark --workdir D:\agent_workspace\tmp\clawhub-test
```

For skills that should become part of the local capability library, install into `capability-library` with `--dir skill-library`, then refresh the local skill index:

```powershell
mycli clawhub install <slug> --workdir D:\agent_workspace\capability-library --dir skill-library
mycli skill-library register
mycli skill-library search <keyword>
```

This produces:

```text
D:\agent_workspace\capability-library\skill-library\<slug>\SKILL.md
```

Do not install random registry skills into the permanent `skill-library` unless the user asks for it or the skill has been inspected and is appropriate.

## Command List

- `native` — pass all arguments to upstream `clawhub`
- `search` — search skills by query
- `explore` — browse latest or popular skills
- `inspect` — inspect metadata and files without installing
- `install` — install a skill
- `update` — update one or all installed skills
- `list-installed` — list installed skills in the selected workdir
- `uninstall` — uninstall a skill
- `sync` — scan local skills and publish new/updated skills
- `login` — authenticate for publishing/account operations

## Common Commands

Discover skills:

```powershell
mycli clawhub explore --limit 10
mycli clawhub explore --limit 10 --json
mycli clawhub search "postgres backups"
```

Inspect before installing:

```powershell
mycli clawhub inspect copenhagen-denmark
mycli clawhub inspect copenhagen-denmark --files
mycli clawhub inspect copenhagen-denmark --file SKILL.md
mycli clawhub inspect copenhagen-denmark --versions --limit 20
```

Install into a temporary workspace:

```powershell
mycli clawhub install copenhagen-denmark --workdir D:\agent_workspace\tmp\clawhub-test
mycli clawhub list-installed --workdir D:\agent_workspace\tmp\clawhub-test
```

Install into the local capability library:

```powershell
mycli clawhub install <slug> --workdir D:\agent_workspace\capability-library --dir skill-library
mycli skill-library register
```

Update installed skills:

```powershell
mycli clawhub update <slug> --workdir D:\agent_workspace\capability-library --dir skill-library
mycli clawhub update --all --no-input --force --workdir D:\agent_workspace\capability-library --dir skill-library
```

Raw passthrough:

```powershell
mycli clawhub native --help
mycli clawhub native install --help
mycli clawhub native package explore --family skill
mycli clawhub native package inspect @openclaw/example-plugin
```

## Publishing and Auth

Publishing requires authentication:

```powershell
mycli clawhub login
mycli clawhub login --token <token>
```

Safety rules:

- Do not print or log ClawHub tokens.
- Prefer browser login where possible.
- Use `sync --dry-run` or publish dry-runs before real publishing.
- Publishing, deleting, hiding, transferring ownership, uninstalling permanent skills, or account changes require explicit user authorization.
- `uninstall` removes installed skill files from the selected workdir; confirm target `--workdir` / `--dir` before running.

Useful upstream examples:

```powershell
mycli clawhub sync --root D:\agent_workspace\capability-library\skill-library --all --dry-run
mycli clawhub native skill publish .\my-skill-pack --slug my-skill-pack --name "My Skill Pack" --version 1.2.0 --changelog "Fixes + docs"
```

## Verification Example

This command was verified successfully during integration:

```powershell
mycli clawhub install copenhagen-denmark --workdir D:\agent_workspace\tmp\clawhub-test
mycli clawhub list-installed --workdir D:\agent_workspace\tmp\clawhub-test
mycli clawhub inspect copenhagen-denmark --files
```

Expected installed layout:

```text
<workdir>\skills\<slug>\_meta.json
<workdir>\skills\<slug>\.clawhub\
<workdir>\skills\<slug>\SKILL.md
```
