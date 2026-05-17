# mihomo

## Summary

`mycli mihomo` is a standalone Mihomo proxy CLI using the downloaded Mihomo core while remaining compatible with the existing Clash for Windows subscription/profile nodes.

Current core:

- `D:\agent_workspace\tools\mycli\mihomo\mihomo.exe`
- downloaded from `MetaCubeX/mihomo` release `v1.19.25`

Existing node source:

- primary: latest real profile under `C:\Users\38188\.config\clash\profiles\*.yml` excluding `list.yml`
- fallback: `C:\Users\38188\.config\clash\config.yaml`

To avoid conflicting with the existing Clash for Windows instance, `mycli mihomo start` writes a runtime config and uses alternate local ports:

- mixed proxy: `127.0.0.1:7891`
- REST controller: `127.0.0.1:60220`
- runtime config: `D:\agent_workspace\config\mycli\mihomo\runtime\config.yaml`
- runtime logs: `D:\agent_workspace\logs\mycli\mihomo\mihomo.out.log`, `mihomo.err.log`
- runtime state: `D:\agent_workspace\var\mycli\mihomo\mihomo-runtime.json`, `mihomo.pid`

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
- `core-version`
- `write-runtime-config`

## Common Examples

```powershell
mycli mihomo core-version
mycli mihomo write-runtime-config
mycli mihomo check-config
mycli mihomo start
mycli mihomo status
mycli mihomo config
mycli mihomo selectors
mycli mihomo selector GLOBAL
mycli mihomo proxies
mycli mihomo countries
mycli mihomo country 日本
mycli mihomo test "Silver-日本-LMT-03" "https://www.gstatic.com/generate_204" 5000
mycli mihomo stop
```

## Compatibility Notes

- Existing paid nodes are read from the current Clash profile files, not from the minimal `config.yaml` wrapper.
- The generated runtime config rewrites only local listener settings such as `mixed-port`, `external-controller`, and `allow-lan`; proxy nodes, proxy groups, and rules are preserved from the selected Clash profile.
- `Country.mmdb` is copied from `C:\Users\38188\.config\clash\Country.mmdb` into the runtime config directory so `GEOIP` rules work without a fresh download.
- `status/selectors/proxies/countries/providers/rules/test/use/mode-set` talk to the Mihomo REST controller when the Mihomo process is running; otherwise they fall back to whatever controller is configured by the current config file.
- `start/stop/restart/use/mode-set/country-use/auto-start/auto-stop` can affect live local proxy behavior. The default Mihomo ports are separate from Clash for Windows to reduce disruption.

## Safety Notes

- `mycli mihomo start` starts a background Mihomo process.
- `mycli mihomo stop` stops the Mihomo process tracked by `mihomo.pid`.
- The existing Clash for Windows process and port `7890` are not stopped by this package.
- `native` is a raw Mihomo core passthrough; prefer `core-version`, `check-config`, and the registered high-level commands for routine use.
