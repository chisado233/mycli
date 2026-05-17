# proxy

## Summary

`mycli proxy` is the unified local proxy command surface. It routes commands to one of two backends:

- `mihomo` — standalone Mihomo core, default backend, mixed proxy `127.0.0.1:7891`, controller `127.0.0.1:60220`
- `clash` — existing Clash for Windows backend, mixed proxy `127.0.0.1:7890`, controller from Clash config

The active backend is stored under `D:\agent_workspace\var\mycli\proxy\proxy-state.json`.

## Commands

```powershell
mycli proxy backend
mycli proxy backend mihomo
mycli proxy backend clash
mycli proxy status
mycli proxy config
mycli proxy version
mycli proxy core-version
mycli proxy start
mycli proxy stop
mycli proxy restart
mycli proxy selectors
mycli proxy selector GLOBAL
mycli proxy proxies
mycli proxy countries
mycli proxy country 日本
mycli proxy test "Silver-日本-LMT-03" "https://www.gstatic.com/generate_204" 5000
mycli proxy use GLOBAL "Silver-日本-LMT-03"
mycli proxy country-use GLOBAL 日本
mycli proxy mode
mycli proxy mode-set rule
mycli proxy providers
mycli proxy rules 10
mycli proxy check-config
```

Any command can override the active backend:

```powershell
mycli proxy status --backend clash
mycli proxy status --backend mihomo
```

## Notes

- Default backend is `mihomo`.
- Use `mycli proxy backend clash` only when you want the unified command surface to point at the existing Clash for Windows instance.
- `start/stop/restart/use/mode-set/country-use/auto-start/auto-stop` can affect local proxy behavior.
