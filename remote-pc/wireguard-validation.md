# WireGuard Tencent Relay Validation

Date: 2026-05-14

## Current Status

- Tencent server public IP: 49.232.183.40
- Server WireGuard IP: 10.66.0.1/24
- Local A WireGuard IP: 10.66.0.2/32
- Server service: wg-quick@wg0 active
- Local service: WireGuardTunnel$client-a.local running
- Local portable WireGuard binaries: D:\agent_workspace\tmp\wireguard-portable
- Local client config: D:\agent_workspace\capability-library\mycli\remote-pc\wireguard\client-a.local.conf

## Verified

1. A -> server WireGuard ping succeeds:
   - ping 10.66.0.1: 0% loss, about 4ms
2. Server `wg show` reports latest handshake for A.
3. A exposed a temporary HTTP file service bound to 10.66.0.2:18080.
4. Server fetched A file over WireGuard:
   - URL: http://10.66.0.2:18080/from-a-via-wireguard.txt
   - content: hello from A via WireGuard relay ...

## Temporary Test State

A temporary Python HTTP server may be running on local A:

```powershell
netstat -ano | Select-String ':18080'
```

Stop it by PID if no longer needed:

```powershell
Stop-Process -Id <PID> -Force
```

Firewall rule added for this test:

```text
Remote Bridge Test HTTP 18080 WireGuard
```

It allows TCP 18080 inbound from 10.66.0.1.

## Useful Commands

Local:

```powershell
Get-Service -Name "WireGuardTunnel*"
ping 10.66.0.1
ipconfig | Select-String -Pattern "client-a.local|10.66.0.2" -Context 0,4
```

Server:

```bash
systemctl status wg-quick@wg0 --no-pager
wg show
curl -sS --max-time 10 http://10.66.0.2:18080/from-a-via-wireguard.txt
```

