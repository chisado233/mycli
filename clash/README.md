# clash

## Summary

`mycli clash` wraps the local Clash for Windows installation and its REST controller into one command surface.

This package uses:

- local app: `D:\software_inf\clash\clash\Clash for Windows`
- local config: `C:\Users\38188\.config\clash`
- local controller: value read from `config.yaml`, currently `127.0.0.1:60657`

## What It Can Do

- inspect runtime status, version, config, mode, providers, rules, and selectors
- list leaf proxies and test delay for a specific node
- switch selector groups such as `GLOBAL` or `TapFog`
- validate the local config with the bundled `clash-win64.exe`
- start, stop, restart, or directly pass arguments to the Clash core

## Command List

- `status`
- `version`
- `config`
- `mode`
- `mode-set`
- `selectors`
- `selector`
- `use`
- `proxies`
- `countries`
- `country`
- `country-use`
- `test`
- `providers`
- `rules`
- `auto-start`
- `auto-stop`
- `auto-status`
- `start`
- `stop`
- `restart`
- `check-config`
- `native`

## Common Examples

```powershell
mycli clash status
mycli clash selectors
mycli clash selector GLOBAL
mycli clash use GLOBAL "Silver-日本-商宽-01"
mycli clash proxies 香港
mycli clash countries
mycli clash country 香港
mycli clash country 日本 TapFog
mycli clash country-use TapFog 日本
mycli clash test "Bronze-香港-HKT-02"
mycli clash mode
mycli clash mode-set rule
mycli clash providers
mycli clash rules 15
mycli clash auto-start TapFog 日本 60 4000
mycli clash auto-status
mycli clash auto-stop
mycli clash check-config
mycli clash native -v
```

## Auto Switch

`auto-start` 会启动一个后台 PowerShell 进程，持续做这几件事：

- 只看指定 `selector` 下面、指定 `country` 的节点
- 定时跑延迟测试
- 自动切到当前同国家里最快且健康的节点
- 如果当前节点测速失败或超时，也会自动切走

状态文件位置：

- `D:\agent_workspace\capability-library\mycli\clash\state\auto-state.json`

## State Paths

- Clash app: `D:\software_inf\clash\clash\Clash for Windows`
- Clash config: `C:\Users\38188\.config\clash`
- Auto switcher state: `D:\agent_workspace\capability-library\mycli\clash\state\auto-state.json`

## Notes

- REST calls are made without system proxy, so local controller access does not get looped back through Clash itself.
- The package reads `external-controller` and `secret` from `C:\Users\38188\.config\clash\config.yaml` each time it runs.
- `use` works for selector-like groups exposed by Clash, including `Selector`, `URLTest`, `Fallback`, and `LoadBalance`.
- 国家归并目前按节点名里的常见国家关键词做识别，比如 `香港`、`日本`、`美国`、`新加坡`、`台湾`、`韩国` 等。
- `auto-start` starts a background PowerShell process; use `auto-status` to inspect and `auto-stop` to stop it.
- `mode-set` and `use` change live network routing and may affect agent/provider connectivity.
- `check-config` validates the local config with the bundled core; it does not switch proxies by itself.
