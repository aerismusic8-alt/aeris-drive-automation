#!/usr/bin/env python3
"""Publish a music video as a durable watch page on GitHub Pages.

The pod-local preview a reviewer is shown dies when `/tmp` is wiped (a pod
recycle took the first one out), so a link to a running `http.server` is not a
deliverable. The film itself lives in the durable `media-938` release and streams
(range requests, `video/mp4`), but a release URL downloads rather than plays.
This renders a real page — embedded 720p preview + poster, full 1080p linked —
and commits it to `site-aeris-music`, which is served by GitHub Pages. The link
then survives a recycle.

Usage
-----
    python3 ops/mv_page.py 26-ban-lang-lek-khong-rao          # build and push
    python3 ops/mv_page.py 26-ban-lang-lek-khong-rao --dry-run # render to /tmp only
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

REPO = "aerismusic8-alt/site-aeris-music"
RELEASE = "media-938"
DOWNLOADS = "aerismusic8-alt/aeris-drive-automation"
ROOT = Path(__file__).resolve().parent.parent / "music938-1"   # .../music938-1
MV_DIR = ROOT / "library" / "musicvideo"
sys.path.insert(0, str(ROOT / "scripts"))
from make_short import load_lyrics  # noqa: E402  (lyric header = the song's metadata)
CLONE = Path("/workspace/ax-tools/pages") / "site-aeris-music"
GH_TOKEN_FILE = Path(os.environ.get("AR_GH_TOKEN_FILE", "/workspace/ax-tools/ar-identity/gh-token"))

MOOD_TH = {"warm": "อบอุ่น", "sad": "เศร้า", "epic": "ยิ่งใหญ่", "hopeful": "มีความหวัง",
           "calm": "ผ่อนคลาย", "mystic": "ขลัง"}
FILM_TITLE = {"pied_piper": "The Pied Piper of Hamelin (1957)",
              "rock_rock_rock": "Rock, Rock, Rock! (1956)",
              "criminal": "They Made Me a Criminal (1939)",
              "gun_pulpit": "The Gun and the Pulpit (1974)",
              "haunted_hill": "House on Haunted Hill (1959)",
              "his_girl_friday": "His Girl Friday (1940)"}

TITLE_FMT = "{title} — มิวสิควีดีโอ · AERIS Music"
TAGLINE = "AERIS Music · เพลงที่ {num} · {mood_th} · {mmss} · ตัดภาพยนตร์ {film}"


def gh_token() -> str:
    for name in ("AX_GH_TOKEN", "GH_TOKEN"):
        if os.environ.get(name):
            return os.environ[name]
    return GH_TOKEN_FILE.read_text().strip()


def gh(method: str, path: str, token: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        "https://api.github.com" + path, data=data, method=method,
        headers={"Authorization": f"token {token}",
                 "Accept": "application/vnd.github+json", "User-Agent": "AR"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def song_meta(slug: str) -> dict:
    """Title, number, mood and film, read from the song's own lyric header."""
    meta, _ = load_lyrics(slug)
    mood = meta.get("mood", "calm")
    sub = meta.get("subtitle", "") or ""
    num = "".join(ch for ch in sub.split("·")[0] if ch.isdigit()) if "·" in sub else ""
    import make_film_video as fv
    film_id = meta.get("film") or fv.film_for_mood(mood)["id"]
    return {"title": meta.get("title", slug), "number": num or "—",
            "mood_th": MOOD_TH.get(mood, "เพลงไทยต้นฉบับ"),
            "film_title": FILM_TITLE.get(film_id, film_id)}


def mmss(seconds: float) -> str:
    return f"{int(seconds) // 60}:{int(seconds) % 60:02d}"


def probe(path: Path) -> dict:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True, check=True).stdout.strip()
    return {"seconds": float(out or 0)}


def build_preview(src: Path, out: Path) -> None:
    subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-i", str(src), "-vf", "scale=1280:-2",
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "26",
         "-c:a", "aac", "-b:a", "96k", str(out)], check=True)
    if out.stat().st_size > 100 * 1024 * 1024:      # GitHub Pages file limit
        raise SystemExit(f"preview {out.stat().st_size} bytes exceeds the Pages "
                         "100 MB limit; lower crf/scale")


def render(slug: str, meta: dict, secs: float, poster: str, preview: str) -> str:
    film = meta.get("film_title") or "ภาพยนตร์สาธารณสมบัติ"
    title = meta.get("title") or slug
    tagline = TAGLINE.format(num=meta.get("number", "—"),
                             mood_th=meta.get("mood_th", "เพลงไทยต้นฉบับ"),
                             mmss=mmss(secs), film=film)
    full = f"https://github.com/{DOWNLOADS}/releases/download/{RELEASE}/film-{slug}.mp4"
    return f'''<!doctype html>
<html lang="th">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>{TITLE_FMT.format(title=title)}</title>
<meta name="description" content="{title} — มิวสิควีดีโอจาก AERIS Music">
<meta property="og:title" content="{title} — มิวสิควีดีโอ">
<meta property="og:description" content="{tagline}">
<meta property="og:type" content="video.other">
<meta property="og:image" content="{poster}">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Thai:wght@300;400;600;700&display=swap" rel="stylesheet">
<style>
:root{{--bg:#0b0b0f;--fg:#f4f4f8;--dim:#a6a6b8;--accent:#ff4d6d;--accent2:#ffb03a}}
*{{box-sizing:border-box;margin:0;padding:0}}
body{{background:var(--bg);color:var(--fg);font-family:"IBM Plex Sans Thai",system-ui,sans-serif;line-height:1.7;text-align:center;-webkit-font-smoothing:antialiased}}
a{{color:var(--accent2)}}
.wrap{{max-width:1040px;margin:0 auto;padding:0 22px}}
header{{padding:22px 0;display:flex;align-items:center;justify-content:space-between}}
.logo{{font-weight:700;letter-spacing:.14em;font-size:1.05rem}}
.logo span{{color:var(--accent)}}
h1{{font-size:clamp(1.4rem,4vw,2rem);font-weight:700;margin:14px 0 4px}}
.sub{{color:var(--dim);font-size:.98rem;margin-bottom:18px}}
video{{width:min(96vw,960px);border-radius:12px;background:#000;box-shadow:0 10px 40px rgba(0,0,0,.5)}}
.note{{color:var(--dim);font-size:.88rem;margin-top:14px}}
.btn{{display:inline-block;padding:11px 24px;border-radius:999px;font-weight:600;text-decoration:none}}
.btn-primary{{background:linear-gradient(120deg,var(--accent),var(--accent2));color:#12060a}}
footer{{border-top:1px solid #1e1e2e;margin-top:34px;padding:26px 0;color:var(--dim);font-size:.88rem}}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="logo">AERIS<span>·</span>MUSIC</div>
    <a class="btn btn-primary" href="https://www.youtube.com/@aerismusicth?sub_confirmation=1" target="_blank" rel="noopener">ติดตามช่อง</a>
  </header>
  <h1>{title}</h1>
  <div class="sub">{tagline}</div>
  <video controls playsinline preload="metadata" poster="{poster}" src="{preview}"></video>
  <p class="note">ไฟล์เต็ม 1080p: <a href="{full}">film-{slug}.mp4</a></p>
  <p class="note">หน้านี้อยู่บน GitHub Pages — ลิงก์ถาวร ไม่หายเมื่อ pod รีไซเคิล</p>
  <footer>
    <a href="./">← กลับหน้าแรก AERIS Music</a> ·
    <a href="https://www.youtube.com/@aerismusicth" target="_blank" rel="noopener">YouTube</a>
  </footer>
</div>
</body>
</html>
'''


def ensure_clone(token: str) -> Path:
    if CLONE.exists():
        subprocess.run(["git", "-C", str(CLONE), "pull", "-q", "--ff-only"], check=False)
        return CLONE
    CLONE.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(["git", "clone", "-q",
                    f"https://x-access-token:{token}@github.com/{REPO}.git",
                    str(CLONE)], check=True)
    return CLONE


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("slug", help="song slug, e.g. 26-ban-lang-lek-khong-rao")
    ap.add_argument("--dry-run", action="store_true", help="render locally, no push")
    args = ap.parse_args(argv)

    src = MV_DIR / f"film-{args.slug}.mp4"
    if not src.exists():
        raise SystemExit(f"no film at {src} — build it with make_film_video.py first")
    meta = song_meta(args.slug)
    secs = probe(src)["seconds"]

    token = gh_token()
    repo = ensure_clone(token)
    poster, preview = f"mv-{args.slug}-poster.jpg", f"mv-{args.slug}-720p.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(secs / 2), "-i", str(src),
                    "-frames:v", "1", "-vf", "scale=1280:720", str(repo / poster)], check=True)
    build_preview(src, repo / preview)
    html = render(args.slug, meta, secs, poster, preview)
    (repo / f"mv-{args.slug}.html").write_text(html)

    url = f"https://aerismusic8-alt.github.io/{REPO.split('/')[1]}/mv-{args.slug}.html"
    if args.dry_run:
        print(f"dry-run: wrote {repo}/mv-{args.slug}.html ({preview}, {poster})")
        print(f"would publish: {url}")
        return 0

    subprocess.run(["git", "-C", str(repo), "add", f"mv-{args.slug}.html", poster, preview],
                   check=True)
    subprocess.run(["git", "-C", str(repo), "commit", "-q", "-m",
                    f"MV watch page: {args.slug}"], check=True)
    subprocess.run(["git", "-C", str(repo), "push", "-q", "origin", "main"], check=True)
    print(f"published: {url}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
