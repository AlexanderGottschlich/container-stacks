#!/usr/bin/env python3
from http.server import BaseHTTPRequestHandler, HTTPServer
import subprocess

PORT = 9333

class Handler(BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/exit":
            self.send_response(200)
            self.end_headers()
            self.wfile.write(b"OK")

            # Kiosk-Browser beenden
            subprocess.call(["pkill", "-f", "firefox.*--kiosk"])
            subprocess.call(["pkill", "-f", "chromium.*--kiosk"])
            return

        self.send_response(404)
        self.end_headers()
        self.wfile.write(b"404")

    def log_message(self, format, *args):
        pass  # kein Logging

HTTPServer(("127.0.0.1", PORT), Handler).serve_forever()
