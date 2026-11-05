#!/usr/bin/env python3
"""Serve the rendered songs so K can listen from a phone.

Rule #1 and the account's delivery rule both say: decide the channel before
generating media. The pod-local URL dies on a recycle, so this is for review,
not for delivery — the durable copy goes to the release rail and Drive.

It serves ONLY the rendered songs and their covers; nothing else in the repo is
reachable, so a session cookie or a key in another directory cannot leak.

    python3 ops/serve_songs.py            # port 12001, the work-2 host
    python3 ops/serve_songs.py --port 12001
"""
from __future__ import annotations

import argparse
import html
import json
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import unquote

ROOT = Path(__file__).resolve().parent.parent
SONGS = ROOT / "music938-1" / "library" / "songs"
LYRICS = ROOT / "music938-1" / "lyrics"
GENRES = ROOT / "music938-1" / "channel" / "genres.json"


def header(path: Path) -> dict:
    meta: dict = {}
    if not path.exists():
        return meta
    for raw in path.read_text(encoding="utf-8").splitlines():
        s = raw.strip()
        if s.startswith("["):
            break
        if s.startswith("#") and ":" in s:
            k, _, v = s[1:].partition(":")
            meta[k.strip().upper()] = v.strip()
    return meta


def genre_names() -> dict:
    try:
        data = json.loads(GENRES.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return {}
    return {g["id"]: g.get("name_th", g["id"]) for g in data.get("genres", [])}


def page() -> str:
    names = genre_names()
    rows = []
    for mp3 in sorted(SONGS.glob("song-*.mp3")):
        slug = mp3.stem[len("song-"):]
        meta = header(LYRICS / f"{slug}.txt")
        g = (meta.get("GENRE") or meta.get("MOOD") or "").lower()
        label = names.get(g, g)
        size = mp3.stat().st_size / 1e6
        rows.append(
            "<div class=song>"
            f"<h3>{html.escape(meta.get('TITLE', slug))} "
            f"<span class=g>{html.escape(label)}</span></h3>"
            f"<div class=meta>{html.escape(slug)} · {size:.1f} MB"
            f" · {html.escape(meta.get('TEMPO',''))} BPM</div>"
            f"<audio controls preload=none src='/songs/{mp3.name}'></audio>"
            "</div>")
    if not rows:
        rows = ["<p>ยังไม่มีเพลงที่เรนเดอร์เสร็จ</p>"]
    return f"""<!doctype html><html lang=th><meta charset=utf-8>
<meta name=viewport content='width=device-width,initial-scale=1'>
<title>AERIS Music — ฟังเพลง</title>
<style>
 body{{font-family:system-ui,-apple-system,'Noto Sans Thai',sans-serif;
   background:#0f1115;color:#e8e8ea;margin:0;padding:16px;line-height:1.5}}
 h1{{font-size:20px;margin:0 0 4px}} .sub{{color:#9aa0aa;font-size:13px;margin-bottom:18px}}
 .song{{background:#171a21;border:1px solid #232733;border-radius:12px;
   padding:12px 14px;margin-bottom:12px}}
 h3{{font-size:16px;margin:0 0 2px}} .g{{font-size:12px;color:#7fd1a0;font-weight:400}}
 .meta{{color:#8b909a;font-size:12px;margin-bottom:8px}}
 audio{{width:100%}}
</style>
<h1>AERIS Music</h1>
<div class=sub>ฟังเพลงที่สร้างเสร็จ · หน้านี้อยู่บน pod ชั่วคราว ปิดเมื่อ pod ถูก recycle</div>
{''.join(rows)}
</html>"""


class Handler(BaseHTTPRequestHandler):
    def _send(self, code: int, body: bytes, ctype: str) -> None:
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Accept-Ranges", "bytes")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = unquote(self.path.split("?")[0])
        if path in ("/", "/index.html"):
            return self._send(200, page().encode("utf-8"), "text/html; charset=utf-8")
        if path.startswith("/songs/"):
            name = Path(path).name
            f = SONGS / name
            if f.suffix == ".mp3" and f.exists():
                return self._send(200, f.read_bytes(), "audio/mpeg")
        self._send(404, b"not found", "text/plain")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--port", type=int, default=12001)
    a = ap.parse_args()
    srv = ThreadingHTTPServer(("0.0.0.0", a.port), Handler)
    print(f"serving {SONGS} on 0.0.0.0:{a.port}", flush=True)
    srv.serve_forever()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
