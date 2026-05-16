# cliproxyapi

## Summary

Wraps the local CLIProxyAPI Go server at:

```text
D:\agent_workspace\projects\CLIProxyAPI
```

CLIProxyAPI provides OpenAI/Gemini/Claude/Codex-compatible API interfaces, OAuth-backed auth files, Management API routes, and multi-account load balancing.

## Safety notes

- `config.yaml` contains API keys, upstream credentials, and the Management API `secret-key`; do not print or commit real secrets.
- `set-management-key` writes a plaintext key to `config.yaml`; CLIProxyAPI may hash it on startup. The wrapper also caches the plaintext locally in `.management-key.local.txt` for local operator reference.
- `stop` kills processes from the PID file and the configured listening port.
- `test` may take time because it runs `go test ./...`.

## First-time setup

```powershell
mycli cliproxyapi init-config
mycli cliproxyapi mod-download
mycli cliproxyapi set-api-key
mycli cliproxyapi set-management-key
```

## Common operations

```powershell
mycli cliproxyapi status
mycli cliproxyapi start
mycli cliproxyapi test-api
mycli cliproxyapi logs
mycli cliproxyapi stop
mycli cliproxyapi restart
```

Default background start command maps to:

```powershell
go run ./cmd/server --config config.yaml --no-browser --local-model
```

Logs are written to:

```text
D:\agent_workspace\projects\CLIProxyAPI\server.out.log
D:\agent_workspace\projects\CLIProxyAPI\server.err.log
```

## Key commands

Set a local client API key for `Authorization: Bearer <key>`:

```powershell
mycli cliproxyapi set-api-key my-local-key
```

Generate one automatically:

```powershell
mycli cliproxyapi set-api-key
```

Set the Management API key used by tools such as codex-register:

```powershell
mycli cliproxyapi set-management-key my-management-key
```

Generate one automatically:

```powershell
mycli cliproxyapi set-management-key
```

## Development commands

```powershell
mycli cliproxyapi build
mycli cliproxyapi run --config config.yaml --no-browser --local-model
mycli cliproxyapi test
mycli cliproxyapi native version
```

## Docker commands

Docker can be used when Docker Desktop and Docker Hub access work:

```powershell
mycli cliproxyapi docker-up
mycli cliproxyapi docker-down
```

In this workspace, direct Go startup is usually more reliable than Docker because registry pulls may fail.

## Command list

- `status` — show project/config/Go/port/key/listener status without revealing key values.
- `init-config` — create `config.yaml` from `config.example.yaml` if missing.
- `set-api-key [key]` — set local client API key; generate one if omitted.
- `set-management-key [key]` — set Management API key; generate one if omitted.
- `start [extra flags]` — background start via `go run ./cmd/server --config config.yaml --no-browser --local-model`.
- `stop` — stop by PID file and configured listening port.
- `restart [extra flags]` — stop then start.
- `test-api` — call `/v1/models` with configured local API key.
- `logs` — show stdout/stderr logs.
- `build` — build `cli-proxy-api.exe`.
- `run [args]` — foreground `go run ./cmd/server` passthrough.
- `test` — run `go test ./...`.
- `mod-download` — run `go mod download`.
- `docker-up` / `docker-down` — Docker Compose lifecycle.
- `native` — raw `go` passthrough from project root.
