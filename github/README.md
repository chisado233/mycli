# github

## Summary

`mycli github` wraps the official GitHub CLI (`gh`) for repository, issue, pull request, GitHub Actions, search, and direct API operations.

The wrapper uses the installed GitHub CLI executable and defaults GitHub network calls through the local Clash mixed proxy (`127.0.0.1:7890`) when no proxy environment variables are already set.

## Installed CLI

- Upstream: `https://cli.github.com/`
- Local executable: `C:\Program Files\GitHub CLI\gh.exe`
- Wrapper script: `D:\agent_workspace\capability-library\mycli\github\scripts\gh-wrapper.ps1`
- GitHub CLI auth state: `%APPDATA%\GitHub CLI\hosts.yml`

## Command List

- `native` — pass all arguments to upstream `gh`
- `version` — show GitHub CLI version
- `auth` — login/status/refresh/setup-git/token operations
- `browse` — open repositories, issues, pull requests, and more in the browser
- `codespace` — connect to and manage GitHub Codespaces
- `gist` — list/view/create/edit/clone/delete gists
- `repo` — list/view/clone/create/fork/sync/edit repositories
- `issue` — list/view/create/edit/comment/close issues
- `pr` — list/view/checks/diff/create/review/merge/checkout pull requests
- `org` — manage or inspect organizations
- `project` — work with GitHub Projects
- `release` — list/view/create/upload/download/edit/delete releases
- `run` — list/view/log/rerun/watch/cancel GitHub Actions runs
- `workflow` — list/view/run/enable/disable GitHub Actions workflows
- `cache` — manage GitHub Actions caches
- `co` — alias for `pr checkout`
- `agent-task` — work with agent tasks (preview)
- `alias` — create command shortcuts
- `api` — direct GitHub REST or GraphQL API calls
- `attestation` — work with artifact attestations
- `completion` — generate shell completion scripts
- `config` — manage GitHub CLI configuration
- `copilot` — run the GitHub Copilot CLI (preview)
- `extension` — manage gh extensions
- `gpg-key` — manage GitHub GPG keys
- `label` — manage repository labels
- `licenses` — view third-party license information
- `preview` — execute previews for gh features
- `ruleset` — view repository rulesets
- `search` — search repositories, issues, PRs, commits, or code
- `secret` — manage GitHub secrets
- `ssh-key` — manage GitHub SSH keys
- `status` — print relevant issues, pull requests, and notifications across repositories
- `variable` — manage GitHub Actions variables
- `skill` — install and manage GitHub CLI agent skills (preview)

## Native GitHub CLI Command Surface

The upstream command is:

```powershell
gh <command> <subcommand> [flags]
```

`mycli github native ...` passes arguments to `gh` unchanged. For discoverability, the main native command groups from `gh --help` are also mapped as `mycli github <command> ...` commands.

### Core commands

| Native gh command | mycli mapping | Upstream meaning |
|---|---|---|
| `gh auth ...` | `mycli github auth ...` | Authenticate `gh` and git with GitHub |
| `gh browse ...` | `mycli github browse ...` | Open repositories, issues, pull requests, and more in the browser |
| `gh codespace ...` | `mycli github codespace ...` | Connect to and manage Codespaces |
| `gh gist ...` | `mycli github gist ...` | Manage gists |
| `gh issue ...` | `mycli github issue ...` | Manage issues |
| `gh org ...` | `mycli github org ...` | Manage organizations |
| `gh pr ...` | `mycli github pr ...` | Manage pull requests |
| `gh project ...` | `mycli github project ...` | Work with GitHub Projects |
| `gh release ...` | `mycli github release ...` | Manage releases |
| `gh repo ...` | `mycli github repo ...` | Manage repositories |
| `gh skill ...` | `mycli github skill ...` | Install and manage agent skills (preview) |

### GitHub Actions commands

| Native gh command | mycli mapping | Upstream meaning |
|---|---|---|
| `gh cache ...` | `mycli github cache ...` | Manage GitHub Actions caches |
| `gh run ...` | `mycli github run ...` | View details about workflow runs |
| `gh workflow ...` | `mycli github workflow ...` | View details about GitHub Actions workflows |

### Alias commands

| Native gh command | mycli mapping | Upstream meaning |
|---|---|---|
| `gh co ...` | `mycli github co ...` | Alias for `pr checkout` |

### Additional commands

| Native gh command | mycli mapping | Upstream meaning |
|---|---|---|
| `gh agent-task ...` | `mycli github agent-task ...` | Work with agent tasks (preview) |
| `gh alias ...` | `mycli github alias ...` | Create command shortcuts |
| `gh api ...` | `mycli github api ...` | Make authenticated REST or GraphQL API requests |
| `gh attestation ...` | `mycli github attestation ...` | Work with artifact attestations |
| `gh completion ...` | `mycli github completion ...` | Generate shell completion scripts |
| `gh config ...` | `mycli github config ...` | Manage configuration for `gh` |
| `gh copilot ...` | `mycli github copilot ...` | Run the GitHub Copilot CLI (preview) |
| `gh extension ...` | `mycli github extension ...` | Manage gh extensions |
| `gh gpg-key ...` | `mycli github gpg-key ...` | Manage GPG keys |
| `gh label ...` | `mycli github label ...` | Manage labels |
| `gh licenses ...` | `mycli github licenses ...` | View third-party license information |
| `gh preview ...` | `mycli github preview ...` | Execute previews for gh features |
| `gh ruleset ...` | `mycli github ruleset ...` | View information about repository rulesets |
| `gh search ...` | `mycli github search ...` | Search repositories, issues, and pull requests |
| `gh secret ...` | `mycli github secret ...` | Manage GitHub secrets |
| `gh ssh-key ...` | `mycli github ssh-key ...` | Manage SSH keys |
| `gh status ...` | `mycli github status ...` | Print relevant issues, pull requests, and notifications |
| `gh variable ...` | `mycli github variable ...` | Manage GitHub Actions variables |

### Help topics

Upstream help topics are available through native passthrough:

```powershell
mycli github native help accessibility
mycli github native help actions
mycli github native help environment
mycli github native help exit-codes
mycli github native help formatting
mycli github native help reference
mycli github native help telemetry
```

## Common Commands

Authentication and identity:

```powershell
mycli github version
mycli github auth status
mycli github auth login --hostname github.com --web --git-protocol https
mycli github api user --jq .login
```

Repositories:

```powershell
mycli github repo list
mycli github repo view owner/repo
mycli github repo clone owner/repo D:\agent_workspace\projects\repo-name
```

Issues and pull requests:

```powershell
mycli github issue list --repo owner/repo --state open
mycli github issue view 123 --repo owner/repo
mycli github pr list --repo owner/repo --state open
mycli github pr checks 55 --repo owner/repo
mycli github pr diff 55 --repo owner/repo
```

GitHub Actions:

```powershell
mycli github run list --repo owner/repo --limit 10
mycli github run view <run-id> --repo owner/repo
mycli github run view <run-id> --repo owner/repo --log-failed
mycli github workflow list --repo owner/repo
```

Direct API:

```powershell
mycli github api user
mycli github api repos/owner/repo --jq .default_branch
mycli github api graphql -f query='query { viewer { login } }'
```

Native passthrough:

```powershell
mycli github native --help
mycli github native repo --help
mycli github native help reference
```

## Defaults and Safety

- Always specify `--repo owner/repo` when not running inside the target git repository, or use full GitHub URLs.
- The wrapper sets `HTTPS_PROXY`, `HTTP_PROXY`, and `ALL_PROXY` to `http://127.0.0.1:7890` only when none of those variables are already present.
- Do not print tokens. `gh auth status` masks tokens; avoid `gh auth token` unless the user explicitly requests a token for a controlled purpose.
- Read-only operations can usually run directly.
- Write operations such as creating/editing issues, comments, PRs, repos, branches, releases, workflow dispatches, or files require a clear target from the user.
- High-risk or destructive operations require explicit confirmation: deleting repositories, branches, releases, packages, secrets, or collaborators; force pushing or rewriting history; merging PRs; transferring ownership; changing organization/team permissions.
- Prefer `--json` and `--jq` for structured output when another command or agent will consume the result.

## Verification

This integration should pass:

```powershell
mycli github version
mycli github auth status
mycli github api user --jq .login
```
