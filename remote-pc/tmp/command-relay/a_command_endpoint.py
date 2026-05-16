import http.server
import json
import subprocess
import urllib.parse
from datetime import datetime

HOST = "10.66.0.2"
PORT = 18082
ALLOWED_CLIENTS = {"10.66.0.1", "127.0.0.1"}

class Handler(http.server.BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        return

    def _send(self, code, payload):
        body = json.dumps(payload, ensure_ascii=False, indent=2).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        client_ip = self.client_address[0]
        if client_ip not in ALLOWED_CLIENTS:
            self._send(403, {"ok": False, "error": f"client {client_ip} is not allowed"})
            return

        parsed = urllib.parse.urlparse(self.path)
        if parsed.path == "/health":
            self._send(200, {"ok": True, "host": HOST, "port": PORT, "time": datetime.now().isoformat()})
            return
        if parsed.path != "/run":
            self._send(404, {"ok": False, "error": "not found", "paths": ["/health", "/run?cmd=..."]})
            return

        qs = urllib.parse.parse_qs(parsed.query)
        cmd = qs.get("cmd", [""])[0]
        if not cmd.strip():
            self._send(400, {"ok": False, "error": "missing cmd"})
            return

        timeout = 20
        try:
            result = subprocess.run(
                ["pwsh", "-NoLogo", "-NoProfile", "-NonInteractive", "-Command", cmd],
                capture_output=True,
                text=True,
                timeout=timeout,
            )
            self._send(200, {
                "ok": result.returncode == 0,
                "command": cmd,
                "exitCode": result.returncode,
                "stdout": result.stdout,
                "stderr": result.stderr,
            })
        except subprocess.TimeoutExpired as exc:
            self._send(504, {"ok": False, "command": cmd, "error": f"timeout after {timeout}s", "stdout": exc.stdout, "stderr": exc.stderr})
        except Exception as exc:
            self._send(500, {"ok": False, "command": cmd, "error": repr(exc)})

if __name__ == "__main__":
    http.server.ThreadingHTTPServer((HOST, PORT), Handler).serve_forever()
