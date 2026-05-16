# mycli opencli

`mycli opencli` wraps an embedded copy of OpenCLI under this package:

```text
D:\agent_workspace\capability-library\mycli\opencli\source
```

It does not depend on `D:\agent_workspace\projects\OpenCLI` for normal command execution. The wrapper runs:

```powershell
node .\source\dist\src\main.js ...
```

## Commands

```powershell
mycli opencli native [args...]
mycli opencli version
mycli opencli doctor [args...]
mycli opencli opencli-list [args...]
mycli opencli browser [args...]
mycli opencli site <site> <command> [args...]
```

## Usage

Forward any native OpenCLI command:

```powershell
mycli opencli native --version
mycli opencli native list
mycli opencli native doctor
```

Convenience wrappers:

```powershell
mycli opencli version
mycli opencli doctor
mycli opencli opencli-list
mycli opencli browser --help
mycli opencli site youtube search "lofi"
mycli opencli site mytokenland pricing gpt-5 --limit 5
mycli opencli site morecode pricing gpt-5 --limit 5
```

`opencli-list` is used instead of `list` because `mycli <package> list` is reserved for showing mycli subpackages and registered commands.

### MyTokenLand

`mytokenland` wraps `https://api.mytokenland.com/` for account and model metadata checks.
Authenticated commands read credentials from environment variables and intentionally do not store passwords in source code:

```powershell
$env:MYTOKENLAND_USERNAME = "<username>"  # optional; defaults to chisado
$env:MYTOKENLAND_PASSWORD = "<password>"

mycli opencli site mytokenland login
mycli opencli site mytokenland balance
mycli opencli site mytokenland models
mycli opencli site mytokenland models gpt --limit 20
mycli opencli site mytokenland pricing
mycli opencli site mytokenland pricing gpt-5 --limit 5
```

`pricing` uses the public pricing endpoint. `login`, `balance`, and `models` log in with the supplied credentials for each invocation and pass the required `New-API-User` header without printing the password.

### MoreCode

`morecode` wraps `http://www.1314mc.net:3333/` for the same New API account and model metadata checks.
Authenticated commands read credentials from environment variables and intentionally do not store passwords in source code:

```powershell
$env:MORECODE_USERNAME = "<username>"
$env:MORECODE_PASSWORD = "<password>"

mycli opencli site morecode login
mycli opencli site morecode balance
mycli opencli site morecode models
mycli opencli site morecode models gpt --limit 20
mycli opencli site morecode pricing
mycli opencli site morecode pricing gpt-5 --limit 5
```

`pricing` uses the public pricing endpoint. `login`, `balance`, and `models` log in with the supplied credentials for each invocation and pass the required `New-API-User` header without printing the password.

## Notes

- OpenCLI browser/cookie/ui commands may require Chrome/Chromium, the Browser Bridge extension, daemon state, and existing website login sessions.
- `native` is the lossless escape hatch. Prefer it when a native OpenCLI subcommand is not explicitly wrapped yet.
- Future per-site package registration should still use passthrough wrappers so OpenCLI keeps owning its command behavior.
