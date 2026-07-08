"""Local HTTP daemon the game calls for styled artwork (portraits/boons/tombstones).

    uv run python -m wordplay_art.server          # serves 127.0.0.1:7770
    GET /health                                   -> {"ok": true}
    GET /image?kind=<...>&subject=<...>           -> image/png
        kind is one of artwork.PROMPTS (creature, weapon, boon, tombstone);
        optional &style=<...>&model=<...>

Cache hits are lock-free; generation (misses) serialize behind a lock since Draw
Things is a single GPU.
"""
from __future__ import annotations

import argparse
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlparse

from . import artwork as A
from .client import DEFAULT_PORT as DT_PORT

_gen_lock = threading.Lock()


class Handler(BaseHTTPRequestHandler):
    dt_port = DT_PORT  # set by main() before serving

    def _send(self, code: int, ctype: str, body: bytes) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:
        u = urlparse(self.path)
        q = parse_qs(u.query)
        style = (q.get("style") or [A.DEFAULT_STYLE])[0]
        model = (q.get("model") or [A.MODEL])[0]
        if u.path == "/health":
            self._send(200, "application/json", b'{"ok": true}')
        elif u.path == "/image":
            kind = (q.get("kind") or [""])[0]
            subject = (q.get("subject") or [""])[0]
            if kind not in A.PROMPTS or not subject:
                self._send(400, "text/plain", b"need kind (one of PROMPTS) and subject")
                return
            self._serve_image(
                lambda: A.cached_path(kind, subject, style, model),
                lambda: A.image(kind, subject, style=style, model=model, port=self.dt_port))
        else:
            self._send(404, "text/plain", b"not found")

    ## Send a cached PNG if present (lock-free), else generate one behind the lock
    ## (Draw Things is single-GPU) and send that. Any failure -> 500.
    def _serve_image(self, hit, make) -> None:
        try:
            path = hit()
            if path is None:
                with _gen_lock:  # re-check inside the lock — another request may have made it
                    path = hit() or make()
            self._send(200, "image/png", path.read_bytes())
        except Exception as e:  # noqa: BLE001 - report any failure to the client
            self._send(500, "text/plain", str(e).encode())

    def log_message(self, *a):  # keep the console quiet
        pass


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="Wordplay art daemon.")
    p.add_argument("--host", default="127.0.0.1")
    p.add_argument("--port", type=int, default=7770)
    p.add_argument("--dt-port", type=int, default=DT_PORT, help="Draw Things gRPC port")
    a = p.parse_args(argv)
    Handler.dt_port = a.dt_port
    srv = ThreadingHTTPServer((a.host, a.port), Handler)
    print(f"art daemon on http://{a.host}:{a.port}  (Draw Things :{a.dt_port})", flush=True)
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
