---
name: opencli-project
description: Work with the local OpenCLI project at D:\agent_workspace\projects\OpenCLI. Use when Codex needs to inspect, run, test, fix, extend, or explain OpenCLI, including its TypeScript/Node CLI runtime, adapter registry, browser bridge, plugins, command manifest, OpenCLI skills, or Windows setup/test issues.
---

# OpenCLI Project

## Project Root

Use `D:\agent_workspace\projects\OpenCLI` as the project root.

OpenCLI is a TypeScript/Node CLI platform for turning websites, browser sessions, Electron apps, and local CLIs into deterministic agent-friendly commands. Read `references/project-report.md` when you need the full research summary, architecture map, statistics, or risk notes.

## Environment

The local environment has been prepared:

```powershell
cd D:\agent_workspace\projects\OpenCLI
npm ci --ignore-scripts
npm run build
```

Important local state:

- Node.js: v24.14.0
- npm: 11.9.0
- `node_modules/` exists
- `dist/` exists
- `cli-manifest.json` has 604 generated entries

The original `prepare` script used Unix shell syntax and failed on Windows. It has been changed to a cross-platform Node one-liner in `package.json`.

## Common Commands

Run these from the project root:

```powershell
node .\dist\src\main.js --version
node .\dist\src\main.js list
npm run build
npm run typecheck
npm test
```

Use `node .\dist\src\main.js ...` when testing the built CLI. Use `npm run dev -- ...` only when intentionally running TypeScript source through `tsx`.

## Code Map

Start with these files for most tasks:

- `src/main.ts`: top-level entry, fast paths, discovery, startup hooks
- `src/cli.ts`: built-in commands and browser command surface
- `src/registry.ts`: command model, strategy normalization, alias registration
- `src/discovery.ts`: manifest loading, filesystem adapter discovery, plugin discovery
- `src/execution.ts`: argument validation, lazy loading, browser session lifecycle, hooks, diagnostics
- `src/commanderAdapter.ts`: Registry to Commander bridge and output/error handling
- `src/browser/`: Browser Bridge, CDP, DOM snapshot, daemon client, page abstraction
- `src/pipeline/`: declarative pipeline executor and steps
- `clis/`: site adapters
- `extension/`: Chrome/Chromium Browser Bridge extension
- `docs/`: VitePress docs
- `skills/`: OpenCLI-provided agent skills

## Testing Notes

`npm run typecheck` passes in the prepared environment.

`npm test` currently runs but is not fully green on this Windows setup:

- 1625 tests passed, 4 skipped, 20 failed across 8 files.
- Many failures are `EPERM: operation not permitted, symlink ...` from Windows symlink permissions. Enable Windows Developer Mode or run as administrator before treating these as product failures.
- The remaining failures are path-separator assumptions in tests that expect POSIX `/` while Windows returns `\`.

Do not claim the OpenCLI full test suite is green on Windows unless these issues are addressed and rerun.

## Development Guidance

- Prefer existing project patterns in `src/registry.ts`, `src/execution.ts`, and nearby adapter tests.
- Keep adapter changes scoped to the relevant `clis/<site>/` directory unless the framework layer must change.
- For Windows fixes, prefer test normalization or cross-platform path handling over forcing POSIX paths in runtime behavior.
- Browser or cookie strategies often require Chrome/Chromium, the Browser Bridge extension, and user login state. Use public/non-browser commands for lightweight smoke checks.
- If working on plugins, remember the implementation relies on symlinks and may need Windows Developer Mode for tests.

## Reference

- `references/project-report.md`: full Chinese research report covering architecture, startup flow, registry/discovery, browser integration, tests, risks, and follow-up directions.
