# codex-register

## Summary

Wraps `D:\agent_workspace\projects\codex-register-main`, a Node.js tool for registering OpenAI/Codex accounts, generating auth files, uploading auth files to CLIProxyAPI, and checking Codex auth quota through CPA management APIs.

Use this package instead of running raw `npm` commands when working from the agent workspace.

## Important safety notes

- `config.json` contains mail-provider credentials, registration passwords, proxy settings, and `cliproxyApiManagementKey`; do not print or commit it.
- `run-once`, `dev`, `start`, and `batch` may create external accounts or trigger provider-side actions. Use them only when the user explicitly asks.
- `check-cpa -- --refresh` may update auth files in CLIProxyAPI. CPA mode may also disable, enable, or delete auth entries according to quota/status rules.

## First-time setup

```powershell
mycli codex-register init-config
mycli codex-register install
mycli codex-register build
```

Then edit the project config if needed:

```text
D:\agent_workspace\projects\codex-register-main\config.json
```

Required fields usually include:

- `provider`
- `defaultProxyUrl`
- `defaultPassword`
- provider-specific credentials such as `2925EmailAddress` / `2925Password`, Gmail, Hotmail, GPTMail, or Cloudflare fields
- `cliproxyApiBaseUrl`
- `cliproxyApiManagementKey`

## CPA integration

Enable automatic upload of generated auth files to CLIProxyAPI:

```powershell
mycli codex-register enable-cpa-upload
```

The command sets:

```json
{
  "cliproxyApiAutoUploadAuth": true,
  "cliproxyApiBaseUrl": "http://localhost:8317",
  "cliproxyApiManagementKey": "<copied from CLIProxyAPI config when available>"
}
```

The key is read from:

```text
D:\agent_workspace\projects\CLIProxyAPI\config.yaml
```

## Common commands

```powershell
mycli codex-register status
mycli codex-register test-proxy
mycli codex-register test-cpa
mycli codex-register install
mycli codex-register build
mycli codex-register run-once
mycli codex-register start -- --n 1
mycli codex-register dev -- --n 1
mycli codex-register check -- --table
mycli codex-register check-cpa -- --refresh --limit 20 -c 8 --table
```

## Command list

- `status` — show project/config/Node/npm/CPA status without exposing key values.
- `init-config` — copy `config.example.json` to `config.json` if missing and fill CPA key from CLIProxyAPI when available.
- `enable-cpa-upload` — set `cliproxyApiAutoUploadAuth=true` and fill CPA base/key.
- `test-proxy` — test `config.json.defaultProxyUrl` against `https://auth.openai.com`.
- `test-cpa` — test whether `cliproxyApiBaseUrl` is reachable.
- `install` — run `npm install` in the project.
- `build` — run `npm run build`.
- `dev` — run `npm run dev -- <args>`.
- `start` — run `npm run start -- <args>`.
- `run-once` — run `npm run start -- --n 1`.
- `check` — run `npm run check -- <args>`.
- `check-cpa` — run `npm run check:cpa -- <args>`.
- `batch` — run `npm run batch -- <args>`.
- `native` — raw `npm` passthrough from the project root.

## Raw passthrough examples

```powershell
mycli codex-register native install
mycli codex-register native run dev -- --n 1
mycli codex-register native run check:cpa -- --refresh --table
```
