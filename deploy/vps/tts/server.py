"""Piper behind a tiny HTTP API for the dental app (2026-11-17).

POST /synthesize {"text": "...", "length_scale": 1.0} -> audio/wav
GET  /health -> ok

Only the app container reaches it (no published port). One Piper process
per sentence: nothing stays in memory between calls.
"""
import json
import os
import subprocess
import tempfile
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PIPER = os.environ.get("PIPER_BIN", "/opt/piper/piper")
MODEL = os.environ.get("PIPER_MODEL", "/opt/voices/ar_JO-kareem-medium.onnx")
MAX_CHARS = 400


class Handler(BaseHTTPRequestHandler):
    def _send(self, code, body, ctype="text/plain; charset=utf-8"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            self._send(200, b"ok")
        else:
            self._send(404, b"not found")

    def do_POST(self):
        if self.path != "/synthesize":
            return self._send(404, b"not found")
        try:
            length = int(self.headers.get("Content-Length", "0"))
            data = json.loads(self.rfile.read(min(length, 20000)) or b"{}")
            text = " ".join(str(data.get("text", "")).split())[:MAX_CHARS]
            scale = min(2.0, max(0.5, float(data.get("length_scale", 1.0))))
        except Exception:
            return self._send(400, b"bad request")
        if not text:
            return self._send(400, b"no text")
        with tempfile.TemporaryDirectory() as tmp:
            out = os.path.join(tmp, "out.wav")
            proc = subprocess.run(
                [PIPER, "--model", MODEL, "--output_file", out, "--length_scale", str(scale)],
                input=text.encode("utf-8"),
                capture_output=True,
                timeout=60,
            )
            if proc.returncode != 0 or not os.path.exists(out):
                return self._send(500, proc.stderr[-500:] or b"piper failed")
            with open(out, "rb") as f:
                self._send(200, f.read(), "audio/wav")

    def log_message(self, fmt, *args):
        pass


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 5000), Handler).serve_forever()
