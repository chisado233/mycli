---
name: cli-anything-project
description: Work with the local CLI-Anything project at D:\agent_workspace\projects\CLI-Anything. Use when Codex needs to inspect, run, test, fix, extend, or explain CLI-Anything, including cli-hub, registry.json, public_registry.json, Python agent-harness packages, SKILL.md files, Claude/Codex/OpenClaw/OpenCode integrations, or harness generation methodology.
---

# CLI-Anything Project

## Project Root

Use `D:\agent_workspace\projects\CLI-Anything` as the project root.

CLI-Anything is an ecosystem repository for generating, collecting, and publishing agent-native CLI harnesses for GUI software, local tools, web services, and professional applications. Read `references/project-report.md` when you need the full research summary, architecture map, statistics, or risk notes.

## Environment

The local environment has been prepared:

```powershell
cd D:\agent_workspace\projects\CLI-Anything
python -m venv .venv
.\.venv\Scripts\python.exe -m pip install --upgrade pip setuptools wheel
$env:PYTHONUTF8='1'
.\.venv\Scripts\python.exe -m pip install -e .\cli-hub pytest
```

Important local state:

- Python: 3.12.4
- `.venv/` exists
- `cli-anything-hub` is installed editable from `cli-hub/`
- `pytest` is installed in the venv

`PYTHONUTF8=1` matters on Windows because some setup metadata reads UTF-8 markdown and can fail under the default GBK code page.

## Common Commands

Run these from the project root:

```powershell
.\.venv\Scripts\Activate.ps1
cli-hub --version
cli-hub list
cli-hub list --json
cli-hub search image
.\.venv\Scripts\python.exe -m pytest .\cli-hub\tests -q
```

The prepared `cli-hub` test suite passes:

```text
64 passed
```

Do not run every harness E2E test by default. Many harnesses require real external software such as Blender, GIMP, FreeCAD, QGIS, LibreOffice, OBS, or live API credentials.

## Code Map

Start with these files and directories:

- `cli-anything-plugin/HARNESS.md`: primary methodology for generating a harness
- `cli-anything-plugin/commands/`: Claude/OpenCode-style command prompts
- `cli-anything-plugin/repl_skin.py`: shared REPL UI helper copied into harnesses
- `cli-anything-plugin/skill_generator.py`: helper for generating SKILL.md from a CLI
- `cli-hub/`: package manager for discovering/installing CLI harnesses
- `cli-hub/cli_hub/cli.py`: Click entry point for `cli-hub`
- `cli-hub/cli_hub/registry.py`: registry loading and search
- `cli-hub/cli_hub/installer.py`: install/update/uninstall logic
- `registry.json`: main CLI-Hub registry for CLI-Anything harnesses
- `public_registry.json`: public/third-party CLI registry
- `<software>/agent-harness/`: independent Python package for each software harness
- `skills/`: canonical agent skill files for harnesses
- `codex-skill/SKILL.md`: condensed CLI-Anything methodology adapted for Codex

## Harness Pattern

Most harnesses are independent Python packages with this structure:

```text
<software>/agent-harness/
+-- setup.py
+-- cli_anything/<software>/
    +-- <software>_cli.py
    +-- core/
    +-- utils/
    +-- skills/
    +-- tests/
```

Expected behavior:

- Use Click for one-shot subcommands.
- Launch a REPL when no subcommand is given.
- Support `--json` for machine-readable agent output.
- Keep session/project state where the target software benefits from it.
- Prefer real software backends over reimplementation.
- Use `test_core.py` for lightweight unit tests and `test_full_e2e.py` for real backend workflows.

## Windows Patch Note

`cli-hub/cli_hub/analytics.py` was adjusted so `track_first_run()` honors `HOME` before falling back to `Path.home()`. This made the analytics tests pass on Windows and POSIX-like shells.

## Development Guidance

- Use the venv Python explicitly in automation: `.\.venv\Scripts\python.exe`.
- Set `$env:PYTHONUTF8='1'` before install/build/test commands that read markdown metadata.
- Keep `registry.json` synchronized with any harness changes: `version`, `install_cmd`, `entry_point`, `skill_md`, and `contributors`.
- Do not silently skip real-backend E2E tests when validating a harness release; CLI-Anything methodology expects real output verification.
- Follow `SECURITY.md`: avoid `shell=True`, validate subprocess arguments, escape content embedded in XML/SVG/scripts, and avoid logging secrets.

## Reference

- `references/project-report.md`: full Chinese research report covering project shape, cli-hub, registry, harness structure, testing, security, risks, and comparison with OpenCLI.
