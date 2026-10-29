#!/usr/bin/env python3
"""Write a Thai index page for the finished song pack.

Run:  python3 scripts/pack_index.py [OUT_DIR]

OUT_DIR defaults to the staging tree the serve script uses. The page links each
song's mp3, its karaoke mp3 and its 1080p karaoke video, so the pack can be
checked on a phone without a Drive account.
"""
from __future__ import annotations

import html
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import common  # noqa: E402


def build(out: Path) -> Path:
    entries = common.read_json(common.LIBRARY / "songs" / "manifest.json")["entries"]
    rows = []
    for e in entries:
        slug = e["id"].removeprefix("song-")
        minutes, seconds = divmod(int(e["duration_seconds"]), 60)
        rows.append(
            f'<tr><td class="n">{slug.split("-")[0]}</td>'
            f'<td class="t">{html.escape(e["title"])}</td>'
            f"<td>{minutes}:{seconds:02d}</td>"
            f'<td class="l"><a href="songs/song-{slug}.mp3">เพลง</a> · '
            f'<a href="songs/karaoke-{slug}.mp3">คาราโอเกะ mp3</a> · '
            f'<a href="karaoke/karaoke-{slug}.mp4">วิดีโอ 1080p</a></td></tr>'
        )
    doc = f"""<!doctype html><html lang="th"><meta charset="utf-8">
<title>music938-1 — 20 เพลงคาราโอเกะ</title>
<style>
body{{font-family:system-ui,'Noto Sans Thai',sans-serif;margin:0;background:#0f1116;color:#e8e8ee}}
header{{padding:28px 24px 12px;border-bottom:1px solid #262a35}}
h1{{margin:0 0 6px;font-size:22px}}
p.sub{{margin:0;color:#9aa0ad;font-size:14px}}
table{{border-collapse:collapse;width:100%;max-width:900px;margin:12px auto 60px}}
td,th{{padding:11px 12px;border-bottom:1px solid #1e222b;font-size:15px;vertical-align:middle}}
th{{text-align:left;color:#8b91a0;font-weight:600;font-size:13px;text-transform:uppercase;letter-spacing:.04em}}
td.n{{color:#6f7686;width:44px}} td.t{{font-weight:600}} td.l{{font-size:14px}}
a{{color:#7cc4ff;text-decoration:none}} a:hover{{text-decoration:underline}}
</style>
<header><h1>music938-1 — 20 เพลงไทย + คาราโอเกะ</h1>
<p class="sub">เพลง 3.5–5 นาที · คาราโอเกะซับคำ · วิดีโอ 1920×1080 · เนื้อร้องและทำนองสร้างด้วยเอนจินในเครื่อง</p></header>
<table><tr><th>#</th><th>ชื่อเพลง</th><th>เวลา</th><th>ดาวน์โหลด</th></tr>
{''.join(rows)}</table></html>"""
    out.mkdir(parents=True, exist_ok=True)
    page = out / "index.html"
    page.write_text(doc, encoding="utf-8")
    return page


def main() -> int:
    out = Path(sys.argv[1]) if len(sys.argv) > 1 else Path("/tmp/deliver")
    page = build(out)
    print(f"wrote {page}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
