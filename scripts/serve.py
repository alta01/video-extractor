#!/usr/bin/env python3
"""
serve.py — serve the catalog with a local video download API
Usage: python3 scripts/serve.py [port]
Opens:  http://localhost:8765/catalog/catalog.html

API endpoints (only available when running via this server):
  GET /api/status?id=ID          — check download status for a video
  GET /api/download?id=ID&url=URL — trigger a yt-dlp download (non-blocking)
"""

import os, sys, json, subprocess, threading
from http.server import HTTPServer, SimpleHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

PROJECT_DIR = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
VIDEOS_DIR  = os.path.join(PROJECT_DIR, "videos")
COOKIES_FILE = os.environ.get("COOKIES_FILE",
               os.path.join(PROJECT_DIR, "cookies", "cookies.txt"))

VIDEO_EXTS = ("mp4", "mkv", "webm", "m4v")

os.makedirs(VIDEOS_DIR, exist_ok=True)

_state: dict[str, str] = {}   # id → "downloading" | "done" | "failed"
_lock = threading.Lock()


def local_path(vid_id: str) -> str | None:
    for ext in VIDEO_EXTS:
        p = os.path.join(VIDEOS_DIR, f"{vid_id}.{ext}")
        if os.path.exists(p):
            return f"/videos/{vid_id}.{ext}"
    return None


def trigger_download(vid_id: str, url: str) -> None:
    with _lock:
        if _state.get(vid_id) == "downloading":
            return
        _state[vid_id] = "downloading"

    def run() -> None:
        try:
            r = subprocess.run([
                "yt-dlp",
                "--cookies", COOKIES_FILE,
                "--format", "bestvideo[ext=mp4]+bestaudio[ext=m4a]/best[ext=mp4]/best",
                "--merge-output-format", "mp4",
                "-o", os.path.join(VIDEOS_DIR, f"{vid_id}.%(ext)s"),
                url,
            ], capture_output=True)
            status = "done" if r.returncode == 0 else "failed"
        except Exception:
            status = "failed"
        with _lock:
            _state[vid_id] = status

    threading.Thread(target=run, daemon=True).start()


class Handler(SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=PROJECT_DIR, **kwargs)

    def do_GET(self) -> None:
        parsed = urlparse(self.path)
        qs     = parse_qs(parsed.query)

        if parsed.path == "/api/status":
            vid_id = qs.get("id", [""])[0]
            path   = local_path(vid_id)
            with _lock:
                status = "done" if path else _state.get(vid_id, "none")
            self._json({"id": vid_id, "status": status, "path": path})

        elif parsed.path == "/api/download":
            vid_id = qs.get("id",  [""])[0]
            url    = qs.get("url", [""])[0]
            if not vid_id or not url:
                self.send_error(400, "Missing id or url")
                return
            if local_path(vid_id):
                self._json({"status": "done", "path": local_path(vid_id)})
                return
            trigger_download(vid_id, url)
            self._json({"status": "downloading"}, 202)

        else:
            super().do_GET()

    def _json(self, data: dict, code: int = 200) -> None:
        body = json.dumps(data).encode()
        self.send_response(code)
        self.send_header("Content-Type",  "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Access-Control-Allow-Origin", "*")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, fmt, *args) -> None:
        # Only log API calls, suppress noisy static-file requests
        if args and "/api/" in str(args[0]):
            super().log_message(fmt, *args)


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8765
    url  = f"http://localhost:{port}/catalog/catalog.html"
    print(f"[*] Serving project at http://localhost:{port}")
    print(f"[*] Catalog:  {url}")
    print(f"[*] Videos → {VIDEOS_DIR}")
    print(f"[*] Ctrl-C to stop")
    HTTPServer(("localhost", port), Handler).serve_forever()
