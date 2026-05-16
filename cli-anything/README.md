# mycli cli-anything

`mycli cli-anything` wraps an embedded copy of the CLI-Anything `cli-hub` package plus local registry snapshots under this package:

```text
D:\agent_workspace\capability-library\mycli\cli-anything\source
```

It does not depend on `D:\agent_workspace\projects\CLI-Anything` for normal command execution. The wrapper runs the embedded `cli_hub.cli` module with local registry caches seeded from:

```text
source\registry.json
source\public_registry.json
```

## Commands

```powershell
mycli cli-anything native [args...]
mycli cli-anything version
mycli cli-anything hub-list [args...]
mycli cli-anything search <query> [args...]
mycli cli-anything info <name>
mycli cli-anything launch <name> [args...]
mycli cli-anything install <name>
mycli cli-anything update <name>
mycli cli-anything uninstall <name>
```

## Usage

Forward any native cli-hub command:

```powershell
mycli cli-anything native --version
mycli cli-anything native list
mycli cli-anything native search blender
mycli cli-anything native info blender
```

Convenience wrappers:

```powershell
mycli cli-anything version
mycli cli-anything hub-list
mycli cli-anything hub-list --json
mycli cli-anything search image
mycli cli-anything info blender
mycli cli-anything launch blender --help
```

`hub-list` is used instead of `list` because `mycli <package> list` is reserved for showing mycli subpackages and registered commands.

## Safety

- `install`, `update`, and `uninstall` modify the Python/npm/user environment. Use only when that is intended.
- Many CLI-Anything harnesses require external applications or services such as Blender, GIMP, FreeCAD, LibreOffice, WireMock, API keys, or local servers.
- `native` is the lossless escape hatch. Future per-harness package registration should still use passthrough wrappers so upstream harnesses keep owning their command behavior.
