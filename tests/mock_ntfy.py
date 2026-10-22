#!/usr/bin/env python3
"""Tiny stand-in for ntfy.sh used by tests/board_test: POST /<topic> stores a message, GET /<topic>/json returns them."""
import json, sys, time
from http.server import BaseHTTPRequestHandler, HTTPServer
store = []
class H(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    def log_message(self, *a): pass
    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode()
        store.append({"id": str(len(store)), "time": int(time.time()), "event": "message", "topic": self.path.strip("/"), "message": body})
        self.send_response(200); self.send_header("Content-Length", "2"); self.end_headers(); self.wfile.write(b"{}")
    def do_GET(self):
        if self.path.startswith("/ip"):
            self.send_response(200); self.send_header("Content-Length", "11"); self.end_headers(); self.wfile.write(b"203.0.113.7"); return
        data = "".join(json.dumps(m) + "\n" for m in store).encode()
        self.send_response(200); self.send_header("Content-Length", str(len(data))); self.end_headers(); self.wfile.write(data)
HTTPServer(("127.0.0.1", int(sys.argv[1])), H).serve_forever()
