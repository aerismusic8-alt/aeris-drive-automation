#!/usr/bin/env python3
"""Build the A/B listening page: every song, original vs K's voice.

Copies the two takes of each song into voice-preview/ and writes an index.html
with a player for each, so K can compare on a phone. Serve the folder with
`python3 -m http.server 12001 --directory voice-preview` (work-2 host).

    python3 scripts/build_voice_preview.py
"""
from __future__ import annotations

import json
import shutil
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SONGS = ROOT / "library" / "songs"
KVOICE = ROOT / "library" / "songs-voice"
OUT = ROOT / "voice-preview"


def main() -> int:
    OUT.mkdir(parents=True, exist_ok=True)
    rows = []
    for meta in sorted(SONGS.glob("clipmeta-*.json")):
        slug = meta.stem.replace("clipmeta-", "")
        orig = SONGS / f"song-{slug}.mp3"
        kvo = KVOICE / f"song-{slug}-kvoice.mp3"
        if not (orig.exists() and kvo.exists()):
            continue
        title = json.loads(meta.read_text()).get("title") or slug
        shutil.copy2(orig, OUT / f"{slug}-original.mp3")
        shutil.copy2(kvo, OUT / f"{slug}-kvoice.mp3")
        rows.append((slug, title))

    cards = []
    for slug, title in rows:
        cards.append(f"""
    <div class="card">
      <h2>{title}</h2>
      <div class="pair">
        <div><span class="tag orig">Flow</span>
          <audio controls preload="none" src="{slug}-original.mp3"></audio></div>
        <div><span class="tag new">เสียง K</span>
          <audio controls preload="none" src="{slug}-kvoice.mp3"></audio></div>
      </div>
    </div>""")

    html = f"""<!doctype html>
<html lang="th"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>AERIS Music — เทียบเสียงนักร้อง</title>
<style>
  :root {{ color-scheme: dark; }}
  body {{ margin:0; font-family:system-ui,"Noto Sans Thai",sans-serif;
          background:#0e0e12; color:#f2f2f5; padding:18px; }}
  h1 {{ font-size:20px; margin:0 0 4px; }}
  p.sub {{ color:#9a9aa8; margin:0 0 18px; font-size:14px; }}
  .card {{ background:#1a1a22; border:1px solid #2a2a36; border-radius:14px;
           padding:14px; margin-bottom:14px; }}
  .card h2 {{ font-size:15px; margin:0 0 10px; }}
  .pair {{ display:grid; gap:10px; grid-template-columns:1fr 1fr; }}
  @media (max-width:640px) {{ .pair {{ grid-template-columns:1fr; }} }}
  audio {{ width:100%; margin-top:6px; }}
  .tag {{ font-size:12px; padding:2px 8px; border-radius:999px; }}
  .orig {{ background:#33334a; }}
  .new {{ background:#1f6f43; }}
</style></head><body>
  <h1>AERIS Music — เทียบเสียงนักร้อง</h1>
  <p class="sub">{len(rows)} เพลง · เสียงเดิมจาก Flow เทียบกับเสียงที่แปลงเป็นเสียงของ K</p>
  {''.join(cards)}
  <p class="sub">ลิงก์นี้เป็นเซิร์ฟเวอร์ชั่วคราวใน pod จะหายเมื่อ pod ถูกรีไซเคิล</p>
</body></html>
"""
    (OUT / "index.html").write_text(html)
    print(f"wrote {OUT/'index.html'} with {len(rows)} songs")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
