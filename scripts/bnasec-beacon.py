#!/usr/bin/env python3
"""Tiny HTTP beacon listener: logs every request path+body to stdout.
Run inside the QEMU bash call so its output file survives; guest posts to 10.0.2.2."""
import http.server
import sys


class H(http.server.BaseHTTPRequestHandler):
    def _log(self, body=b""):
        line = f"BEACON {self.path} {body.decode('utf-8', 'replace')[:1200]}"
        print(line, flush=True)

    def do_GET(self):
        self._log()
        self.send_response(200)
        self.end_headers()

    def do_POST(self):
        n = int(self.headers.get("Content-Length", 0) or 0)
        body = self.rfile.read(n) if n else b""
        self._log(body)
        self.send_response(200)
        self.end_headers()

    def log_message(self, *a):
        pass


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8047
    http.server.HTTPServer(("0.0.0.0", port), H).serve_forever()
