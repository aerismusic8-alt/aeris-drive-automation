#!/usr/bin/env python3
"""Index the finished music938-1 pack: manifest.json plus a Thai index page.

Run after build_songs.py has produced audio:

    python3 scripts/manifest.py

Each song contributes its duration, loudness, cover and SHA-256. A track outside
the 3.5-5 min brief is reported and makes the exit code non-zero, so this can
gate a release.
"""
from __future__ import annotations

import hashlib
import html
import json
import re
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SONGS = ROOT / "library" / "songs"
COVERS = ROOT / "library" / "covers"
LYRICS = ROOT / "lyrics"
MIN_S, MAX_S = 210.0, 300.0


def probe(path: Path, *entries: str) -> str:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", ",".join(entries),
         "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True, check=True).stdout.strip()
    return out


def duration(path: Path) -> float:
    return float(probe(path, "format=duration"))


def lufs(path: Path) -> float | None:
    r = subprocess.run(
        ["ffmpeg", "-hide_banner", "-i", str(path), "-af",
         "loudnorm=print_format=summary", "-f", "null", "-"],
        capture_output=True, text=True)
    m = re.search(r"Input Integrated:\s*(-?\d+(?:\.\d+)?)", r.stderr)
    return float(m.group(1)) if m else None


def sha256(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def meta(slug: str) -> dict:
    head = {}
    p = LYRICS / f"{slug}.txt"
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            m = re.match(r"#\s*([A-Z]+):\s*(.+)", line)
            if m:
                head[m.group(1).lower()] = m.group(2).strip()
    return head


def main() -> int:
    entries, problems = [], []
    for song in sorted(SONGS.glob("song-*.mp3")):
        slug = song.stem.removeprefix("song-")
        kar = SONGS / f"karaoke-{slug}.mp3"
        cover = COVERS / f"cover-{slug}.jpg"
        m = meta(slug)
        secs = duration(song)
        if not MIN_S <= secs <= MAX_S:
            problems.append(f"{slug}: {secs:.0f}s outside {MIN_S:.0f}-{MAX_S:.0f}s")
        if not kar.exists():
            problems.append(f"{slug}: no karaoke mix")
        if not cover.exists():
            problems.append(f"{slug}: no cover")
        entries.append({
            "id": f"song-{slug}",
            "number": slug.split("-")[0],
            "title": m.get("title", slug),
            "subtitle": m.get("subtitle", ""),
            "key": m.get("key", ""),
            "mood": m.get("mood", ""),
            "voice": m.get("voice", ""),
            "duration_seconds": round(secs, 1),
            "lufs": lufs(song),
            "bytes": song.stat().st_size,
            "sha256": sha256(song),
            "karaoke": f"karaoke-{slug}.mp3" if kar.exists() else None,
            "cover": f"../covers/cover-{slug}.jpg" if cover.exists() else None,
        })

    SONGS.mkdir(parents=True, exist_ok=True)
    (SONGS / "manifest.json").write_text(
        json.dumps({"songs": entries}, ensure_ascii=False, indent=1), encoding="utf-8")

    rows = []
    for e in entries:
        slug = e["id"].removeprefix("song-")
        mins, secs = divmod(int(e["duration_seconds"]), 60)
        cover = (f'<img src="covers/cover-{slug}.jpg" alt="">' if e["cover"] else "")
        rows.append(
            f'<tr><td>{cover}</td><td class="n">{e["number"]}</td>'
            f'<td class="t">{html.escape(e["title"])}<span>{html.escape(e["subtitle"])}</span></td>'
            f"<td>{mins}:{secs:02d}</td>"
            f'<td class="l"><a href="songs/song-{slug}.mp3">เพลง</a> · '
            f'<a href="songs/karaoke-{slug}.mp3">คาราโอเกะ</a></td></tr>')

    doc = f"""<!doctype html><html lang="th"><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>music938-1 — เพลงไทย + คาราโอเกะ</title>
<style>
body{{font-family:system-ui,'Noto Sans Thai',sans-serif;margin:0;background:#0f1116;color:#e8e8ee}}
header{{padding:28px 24px 12px;border-bottom:1px solid #262a35}}
h1{{margin:0 0 6px;font-size:22px}} p.sub{{margin:0;color:#9aa0ad;font-size:14px}}
table{{border-collapse:collapse;width:100%;max-width:940px;margin:12px auto 60px}}
td,th{{padding:10px 12px;border-bottom:1px solid #1e222b;font-size:15px;vertical-align:middle}}
th{{text-align:left;color:#8b91a0;font-weight:600;font-size:13px;text-transform:uppercase;letter-spacing:.04em}}
td img{{width:52px;height:52px;border-radius:8px;display:block}}
td.n{{color:#6f7686;width:36px}} td.t{{font-weight:600}} td.t span{{display:block;font-weight:400;color:#8b91a0;font-size:12px}}
a{{color:#7cc4ff;text-decoration:none}} a:hover{{text-decoration:underline}}
</style>
<header><h1>music938-1 — {len(entries)} เพลงไทย + คาราโอเกะ</h1>
<p class="sub">เพลง 3.5–5 นาที · ร้องจริงด้วย Flow Music · คาราโอเกะตัดเสียงร้อง</p></header>
<table><tr><th></th><th>#</th><th>ชื่อเพลง</th><th>เวลา</th><th>ดาวน์โหลด</th></tr>
{chr(10).join(rows)}
</table></html>"""
    (ROOT / "library" / "index.html").write_text(doc, encoding="utf-8")

    print(f"{len(entries)} songs indexed -> library/songs/manifest.json, library/index.html")
    for p in problems:
        print("  ! " + p)
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
