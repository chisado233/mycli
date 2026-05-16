import argparse
import base64
import hmac
import http.server
import json
import os
import subprocess
import sys
import urllib.parse
from datetime import datetime

DEFAULT_HOST = "10.66.0.2"
DEFAULT_PORT = 18082
DEFAULT_ALLOWED_CLIENTS = {"10.66.0.1"}


def json_response(handler, code, payload):
    body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
    handler.send_response(code)
    handler.send_header("Content-Type", "application/json; charset=utf-8")
    handler.send_header("Content-Length", str(len(body)))
    handler.end_headers()
    handler.wfile.write(body)


def decode_command(value):
    raw = base64.urlsafe_b64decode(value.encode("ascii") + b"=" * (-len(value) % 4))
    return raw.decode("utf-8")


class CommandHandler(http.server.BaseHTTPRequestHandler):
    server_version = "RemotePcCommandServer/0.1"

    def log_message(self, fmt, *args):
        line = f"[{datetime.now().isoformat()}] {self.client_address[0]} {fmt % args}\n"
        if self.server.log_path:
            with open(self.server.log_path, "a", encoding="utf-8") as f:
                f.write(line)

    def _check_client(self):
        client_ip = self.client_address[0]
        return client_ip in self.server.allowed_clients

    def _check_token(self, parsed):
        if not self.server.token:
            return True
        qs = urllib.parse.parse_qs(parsed.query)
        token = qs.get("token", [""])[0]
        return hmac.compare_digest(token, self.server.token)

    def do_GET(self):
        parsed = urllib.parse.urlparse(self.path)
        if not self._check_client():
            json_response(self, 403, {"ok": False, "error": f"client {self.client_address[0]} is not allowed"})
            return
        if not self._check_token(parsed):
            json_response(self, 401, {"ok": False, "error": "invalid token"})
            return

        if parsed.path == "/health":
            json_response(self, 200, {
                "ok": True,
                "host": self.server.server_address[0],
                "port": self.server.server_address[1],
                "allowedClients": sorted(self.server.allowed_clients),
                "time": datetime.now().isoformat(),
            })
            return

        if parsed.path != "/run":
            json_response(self, 404, {"ok": False, "error": "not found", "paths": ["/health", "/run?cmd64=..."]})
            return

        qs = urllib.parse.parse_qs(parsed.query)
        cmd = qs.get("cmd", [""])[0]
        cmd64 = qs.get("cmd64", [""])[0]
        if cmd64:
            try:
                cmd = decode_command(cmd64)
            except Exception as exc:
                json_response(self, 400, {"ok": False, "error": f"invalid cmd64: {exc}"})
                return
        if not cmd.strip():
            json_response(self, 400, {"ok": False, "error": "missing cmd/cmd64"})
            return

        timeout = self.server.command_timeout
        started = datetime.now()
        try:
            result = subprocess.run(
                [self.server.pwsh, "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", cmd],
                cwd=self.server.cwd,
                capture_output=True,
                text=True,
                encoding="utf-8",
                errors="replace",
                timeout=timeout,
            )
            json_response(self, 200, {
                "ok": result.returncode == 0,
                "command": cmd,
                "cwd": self.server.cwd,
                "exitCode": result.returncode,
                "startedAt": started.isoformat(),
                "finishedAt": datetime.now().isoformat(),
                "stdout": result.stdout,
                "stderr": result.stderr,
            })
        except subprocess.TimeoutExpired as exc:
            json_response(self, 504, {
                "ok": False,
                "command": cmd,
                "cwd": self.server.cwd,
                "error": f"timeout after {timeout}s",
                "stdout": exc.stdout,
                "stderr": exc.stderr,
            })
        except Exception as exc:
            json_response(self, 500, {"ok": False, "command": cmd, "cwd": self.server.cwd, "error": repr(exc)})


def main():
    parser = argparse.ArgumentParser(description="Remote PC command server bound to WireGuard IP")
    parser.add_argument("--host", default=os.environ.get("REMOTE_PC_COMMAND_HOST", DEFAULT_HOST))
    parser.add_argument("--port", type=int, default=int(os.environ.get("REMOTE_PC_COMMAND_PORT", DEFAULT_PORT)))
    parser.add_argument("--allow", action="append", default=[], help="Allowed client IP. Repeatable.")
    parser.add_argument("--token", default=os.environ.get("REMOTE_PC_COMMAND_TOKEN", ""))
    parser.add_argument("--cwd", default=os.environ.get("REMOTE_PC_COMMAND_CWD", r"D:\agent_workspace"))
    parser.add_argument("--timeout", type=int, default=int(os.environ.get("REMOTE_PC_COMMAND_TIMEOUT", "120")))
    parser.add_argument("--pwsh", default=os.environ.get("REMOTE_PC_COMMAND_PWSH", "pwsh"))
    parser.add_argument("--log", default=os.environ.get("REMOTE_PC_COMMAND_LOG", ""))
    args = parser.parse_args()

    allowed = set(args.allow) if args.allow else set(DEFAULT_ALLOWED_CLIENTS)
    httpd = http.server.ThreadingHTTPServer((args.host, args.port), CommandHandler)
    httpd.allowed_clients = allowed
    httpd.token = args.token
    httpd.cwd = args.cwd
    httpd.command_timeout = args.timeout
    httpd.pwsh = args.pwsh
    httpd.log_path = args.log
    print(json.dumps({
        "ok": True,
        "event": "started",
        "host": args.host,
        "port": args.port,
        "allowedClients": sorted(allowed),
        "cwd": args.cwd,
        "timeout": args.timeout,
        "log": args.log,
    }, ensure_ascii=False), flush=True)
    httpd.serve_forever()


if __name__ == "__main__":
    main()


