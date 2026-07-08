#!/usr/bin/env python3
"""Static dev server that disables browser caching, so a plain refresh always shows
your latest edits (`python3 -m http.server` caches JS/CSS and needs a hard refresh).

    python3 serve.py          # -> http://localhost:8000/web_version/
    python3 serve.py 8001
"""
import sys
from http.server import SimpleHTTPRequestHandler, test


class NoCacheHandler(SimpleHTTPRequestHandler):
    def end_headers(self):
        self.send_header("Cache-Control", "no-store, no-cache, must-revalidate, max-age=0")
        self.send_header("Pragma", "no-cache")
        self.send_header("Expires", "0")
        super().end_headers()


if __name__ == "__main__":
    port = int(sys.argv[1]) if len(sys.argv) > 1 else 8000
    print(f"open http://localhost:{port}/web_version/")
    test(HandlerClass=NoCacheHandler, port=port)
