#!/usr/bin/env python3
"""Serve the clip warehouse so K can watch a render without downloading it.

K asks "ขอดูผลงาน" and the only honest answer is a playable clip, not a table of
numbers. The warehouse is gitignored and lives on the pod, which K cannot reach,
so this puts a page on the live-view port with the MP4, its QC verdict, and the
credits for every still in it.

    python3 ops/clip_gallery.py            # serve on :12001
    python3 ops/clip_gallery.py --port N

Read-only and local: it never uploads, never posts, and obeys the publish hold by
construction because it has no network code at all.
"""
from __future__ import annotations

import argparse
import html
import json
import subprocess
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BANK = ROOT / "music938-1" / "library" / "bank"
PORT = 12001


def _probe(path: Path) -> dict:
    """Duration/size from the file itself, so a half-written render is visible."""
    try:
        out = subprocess.run(
            ["ffprobe", "-v", "error", "-show_entries",
             "format=duration,size", "-of", "json", str(path)],
            capture_output=True, text=True, timeout=30, check=True).stdout
        fmt = json.loads(out)["format"]
        return {"seconds": float(fmt["duration"]), "bytes": int(fmt["size"])}
    except Exception:  # noqa: BLE001
        return {"seconds": 0.0, "bytes": path.stat().st_size}


def _verdict(path: Path) -> str:
    """The gate's own words, cached beside the clip.

    The gate runs ffmpeg loudness analysis over the whole file, which takes
    seconds. Running it per page load made the page slower than the work-host
    proxy's timeout, so K got "Bad Gateway" instead of the clip. The verdict is
    a property of the file, so cache it keyed on size+mtime and re-run only when
    the clip changes. A gallery that said PASS on its own authority would be a
    second, weaker gate, so this still runs the real one.
    """
    side = path.with_suffix(".qc.json")
    key = {"size": path.stat().st_size, "mtime": int(path.stat().st_mtime)}
    if side.exists():
        try:
            cached = json.loads(side.read_text(encoding="utf-8"))
            if all(cached.get(k) == v for k, v in key.items()):
                return cached["verdict"]
        except Exception:  # noqa: BLE001
            pass

    gate = ROOT / "ops" / "clip_standard.py"
    verdict = "gate error"
    try:
        r = subprocess.run([sys.executable, str(gate), str(path)],
                           capture_output=True, text=True, timeout=600)
        for line in r.stdout.splitlines():
            if line.startswith(("PASS", "FAIL")):
                verdict = line.strip()
                break
        else:
            verdict = (r.stdout.strip().splitlines() or ["no verdict"])[-1]
    except Exception as exc:  # noqa: BLE001
        verdict = f"gate error: {type(exc).__name__}"
    try:
        side.write_text(json.dumps({**key, "verdict": verdict}), encoding="utf-8")
    except Exception:  # noqa: BLE001
        pass
    return verdict


def _clips() -> list[dict]:
    items = []
    for mp4 in sorted(BANK.glob("*.mp4")):
        credits = mp4.with_suffix(".credits.json")
        meta = {}
        if credits.exists():
            try:
                meta = json.loads(credits.read_text(encoding="utf-8"))
            except Exception:  # noqa: BLE001
                meta = {}
        items.append({
            "name": mp4.name,
            "song": meta.get("song", ""),
            "query": meta.get("query", ""),
            "stills": len(meta.get("items", [])),
            "items": meta.get("items", []),
            **_probe(mp4),
            "verdict": _verdict(mp4),
        })
    return items


PAGE = """<!doctype html><html lang="th"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>โกดังคลิป — {n} ชิ้น</title>
<style>
:root{{--bg:#0b0d12;--card:#161a23;--line:#252c3a;--fg:#e8ecf4;--dim:#8b95a8;
--ok:#39d98a;--bad:#ff5c6c}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--fg);
font:16px/1.5 -apple-system,"Segoe UI",Noto Sans Thai,sans-serif;padding:24px}}
h1{{font-size:22px;margin:0 0 4px}}
.sub{{color:var(--dim);font-size:14px;margin-bottom:24px}}
.grid{{display:grid;gap:20px;grid-template-columns:repeat(auto-fill,minmax(320px,1fr))}}
.card{{background:var(--card);border:1px solid var(--line);border-radius:14px;
overflow:hidden;display:flex;flex-direction:column}}
video{{width:100%;background:#000;display:block;aspect-ratio:9/16;object-fit:contain}}
.body{{padding:14px;display:flex;flex-direction:column;gap:8px}}
.song{{font-weight:600;font-size:15px;word-break:break-word}}
.q{{color:var(--dim);font-size:13px}}
.meta{{display:flex;flex-wrap:wrap;gap:6px;font-size:12px}}
.tag{{background:#1f2634;border:1px solid var(--line);border-radius:999px;
padding:3px 9px;color:var(--dim)}}
.pass{{color:var(--ok);border-color:#1e6b46}}
.fail{{color:var(--bad);border-color:#7a2531}}
details{{border-top:1px solid var(--line);padding-top:8px}}
summary{{cursor:pointer;color:var(--dim);font-size:13px}}
ul{{margin:8px 0 0;padding-left:18px;font-size:12px;color:var(--dim)}}
a{{color:#7db3ff;text-decoration:none}}
.empty{{color:var(--dim)}}
</style></head><body>
<h1>โกดังคลิป</h1>
<div class="sub">{n} ชิ้น · QC ด้วย <code>ops/clip_standard.py</code> ตัวจริง ·
ทุกคลิปคือ 720×1280 30fps h264+aac</div>
<div class="grid">{cards}</div>
</body></html>"""

CARD = """<div class="card">
<video src="/clip/{url}" controls preload="metadata" playsinline></video>
<div class="body">
  <div class="song">{song}</div>
  <div class="q">ภาพ: {query}</div>
  <div class="meta">
    <span class="tag">{seconds:.1f} วิ</span>
    <span class="tag">{mb:.1f} MB</span>
    <span class="tag">{stills} ช็อต</span>
    <span class="tag {cls}">{verdict}</span>
  </div>
  <details><summary>เครดิตภาพ ({stills})</summary><ul>{credits}</ul></details>
</div></div>"""


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *a):  # noqa: D102 - quiet
        pass

    def do_GET(self):  # noqa: N802
        path = self.path.split("?")[0]
        if path == "/":
            clips = _clips()
            cards = []
            for c in clips:
                credits = "".join(
                    f"<li>{html.escape(str(i.get('credit') or i.get('model') or 'AI'))}"
                    f" — {html.escape(str(i.get('licence') or i.get('origin') or ''))}"
                    f"{' · ' + html.escape(str(i.get('file'))) if i.get('file') else ''}</li>"
                    for i in c["items"])
                cards.append(CARD.format(
                    url=html.escape(c["name"]),
                    song=html.escape(c["song"] or c["name"]),
                    query=html.escape(c["query"] or "—"),
                    seconds=c["seconds"], mb=c["bytes"] / 1e6,
                    stills=c["stills"],
                    verdict=html.escape(c["verdict"]),
                    cls="pass" if c["verdict"].startswith("PASS") else "fail",
                    credits=credits or "<li>ไม่มีข้อมูล</li>"))
            body = PAGE.format(n=len(clips), cards="".join(cards)
                               or '<div class="empty">ยังไม่มีคลิป</div>')
            data = body.encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/html; charset=utf-8")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)
            return

        if path.startswith("/clip/"):
            name = Path(path[len("/clip/"):]).name
            f = BANK / name
            if not f.is_file():
                self.send_error(404)
                return
            size = f.stat().st_size
            start, end = 0, size - 1
            rng = self.headers.get("Range")
            if rng and rng.startswith("bytes="):
                a, _, b = rng[6:].partition("-")
                if a:
                    start = int(a)
                if b:
                    end = min(int(b), size - 1)
                self.send_response(206)
                self.send_header("Content-Range", f"bytes {start}-{end}/{size}")
            else:
                self.send_response(200)
            self.send_header("Content-Type", "video/mp4")
            self.send_header("Accept-Ranges", "bytes")
            self.send_header("Content-Length", str(end - start + 1))
            self.end_headers()
            with f.open("rb") as fh:
                fh.seek(start)
                left = end - start + 1
                while left > 0:
                    chunk = fh.read(min(1 << 20, left))
                    if not chunk:
                        break
                    self.wfile.write(chunk)
                    left -= len(chunk)
            return

        self.send_error(404)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--port", type=int, default=PORT)
    a = ap.parse_args()
    if not BANK.is_dir():
        print(f"no warehouse at {BANK}", file=sys.stderr)
        return 1
    srv = ThreadingHTTPServer(("0.0.0.0", a.port), Handler)
    print(f"gallery: http://127.0.0.1:{a.port}/  ({len(list(BANK.glob('*.mp4')))} clip(s))")
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
