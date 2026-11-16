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
    python3 ops/mv_page.py --all                              # every MV on the release
    python3 ops/mv_page.py 26-ban-lang-lek-khong-rao --dry-run # render to /tmp only

The MV itself is read from disk when this pod built it, otherwise fetched from the
`media-938` release, so the publisher works from a fresh pod too and is reusable
for every song, not only the one built in this session.
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import shutil
import subprocess
import sys
import urllib.error
import urllib.request
from html import escape as esc_html
from pathlib import Path

REPO = "aerismusic8-alt/site-aeris-music"
RELEASE = "media-938"
DOWNLOADS = "aerismusic8-alt/aeris-drive-automation"
ROOT = Path(os.environ.get("MV_SOURCE_ROOT")
            or Path(__file__).resolve().parent.parent / "music938-1")  # .../music938-1
MV_DIR = ROOT / "library" / "musicvideo"
sys.path.insert(0, str(ROOT / "scripts"))
from make_short import load_lyrics  # noqa: E402  (lyric header = the song's metadata)
# Where the Pages checkout lives. A CI run checks the Pages repo out itself and
# points MV_PAGES_DIR at it, so the same publisher works from a fresh pod and from
# the Pages repo's own workflow without a cross-repo token.
CLONE = Path(os.environ.get("MV_PAGES_DIR") or "/workspace/ax-tools/pages/site-aeris-music")
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
    """A write token, or "" when none is set (the release reads are public)."""
    for name in ("AX_GH_TOKEN", "GH_TOKEN", "GITHUB_TOKEN"):
        if os.environ.get(name):
            return os.environ[name]
    return GH_TOKEN_FILE.read_text().strip() if GH_TOKEN_FILE.exists() else ""


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
    # The number is the slug's leading digits (canonical); the subtitle carries it
    # only sometimes, so the slug is the source that is always there.
    head = slug.split("-", 1)[0]
    num = head.lstrip("0") or head if head.isdigit() else "—"
    import make_film_video as fv
    film_id = meta.get("film") or fv.film_for_mood(mood)["id"]
    return {"title": meta.get("title", slug), "number": num,
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


def render(slug: str, meta: dict, secs: float, poster: str, preview: str,
           asset: str | None = None) -> str:
    film = meta.get("film_title") or "ภาพยนตร์สาธารณสมบัติ"
    title = meta.get("title") or slug
    tagline = TAGLINE.format(num=meta.get("number", "—"),
                             mood_th=meta.get("mood_th", "เพลงไทยต้นฉบับ"),
                             mmss=mmss(secs), film=film)
    asset = asset or f"film-{slug}.mp4"
    full = f"https://github.com/{DOWNLOADS}/releases/download/{RELEASE}/{asset}"
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
    if token:
        url = f"https://x-access-token:{token}@github.com/{REPO}.git"
    else:
        url = f"https://github.com/{REPO}.git"
    subprocess.run(["git", "clone", "-q", url, str(CLONE)], check=True)
    return CLONE


def _gh_headers(accept: str = "application/vnd.github+json") -> dict:
    hdrs = {"Accept": accept, "User-Agent": "ax-mv-page"}
    token = gh_token()
    if token:
        hdrs["Authorization"] = f"token {token}"
    return hdrs


def _is_mv(name: str) -> bool:
    """A long-form MV: `film-<slug>.mp4` or `mv-<slug>[-full].mp4` (no Short cut)."""
    if not name.endswith(".mp4") or "-hook" in name or "-vertical" in name:
        return False
    stem = name[:-4]
    if stem.endswith("-full"):
        stem = stem[:-5]
    return stem.startswith(("film-", "mv-"))


def slug_from_asset(name: str) -> str:
    stem = name[:-4]
    if stem.endswith("-full"):
        stem = stem[:-5]
    return stem.split("-", 1)[1]        # strip the film-/mv- prefix


def release_mv_assets() -> dict[str, str]:
    """{slug: asset_name} for every long-form MV on the media release.

    A fresh pod has an empty `library/`, so the MVs that already shipped live only
    on the release. Reading the release list is what makes the publisher reusable
    for every song, not just the one built in this session. The film MV wins over a
    generated one for the same slug, matching `release.mv_files`.
    """
    import urllib.request
    base = f"https://api.github.com/repos/{DOWNLOADS}/releases/tags/{RELEASE}"
    with urllib.request.urlopen(urllib.request.Request(base, headers=_gh_headers()),
                                timeout=30) as r:
        rel = json.loads(r.read().decode())
    out: dict[str, str] = {}
    for a in rel.get("assets", []):
        name = a["name"]
        if not _is_mv(name):
            continue
        slug = slug_from_asset(name)
        # film- sorts before mv-, so a later mv- never displaces it.
        if slug not in out or name.startswith("film-"):
            out[slug] = name
    return out


def fetch_asset(name: str, dest: Path) -> Path:
    """Download one release asset if it is not already on disk."""
    if dest.exists():
        return dest
    import time
    import urllib.request
    info = next((a for a in _release_assets() if a["name"] == name), None)
    if not info:
        raise SystemExit(f"{name} is not on the {RELEASE} release")
    urls = [f"https://api.github.com/repos/{DOWNLOADS}/releases/assets/{info['id']}",
            info["browser_download_url"]]
    dest.parent.mkdir(parents=True, exist_ok=True)
    last: Exception | None = None
    for attempt in range(3):
        url = urls[min(attempt, 1)]
        hdrs = _gh_headers("application/octet-stream") if attempt == 0 else {"User-Agent": "ax-mv-page"}
        try:
            with urllib.request.urlopen(urllib.request.Request(url, headers=hdrs),
                                        timeout=600) as r:
                dest.write_bytes(r.read())
            return dest
        except Exception as exc:  # noqa: BLE001 - a CDN blip must not abort the run
            last = exc
            if attempt < 2:
                time.sleep(5 * (attempt + 1))
    raise SystemExit(f"could not fetch {name} after 3 tries ({last})")


def _release_assets() -> list[dict]:
    import urllib.request
    base = f"https://api.github.com/repos/{DOWNLOADS}/releases/tags/{RELEASE}"
    with urllib.request.urlopen(urllib.request.Request(base, headers=_gh_headers()),
                                timeout=30) as r:
        return json.loads(r.read().decode()).get("assets", [])


def film_asset(slug: str) -> tuple[Path, str]:
    """Find the MV for a slug; return (path, release asset name).

    A film MV is `film-<slug>.mp4` (make_film_video.py); a generated MV is
    `mv-<slug>-full.mp4` (make_music_video.py). Both ship in the media release, so
    a pod with an empty `library/` fetches the one it needs instead of failing.
    """
    for name in (f"film-{slug}.mp4", f"mv-{slug}-full.mp4"):
        p = MV_DIR / name
        if p.exists():
            return p, name
    on_release = release_mv_assets().get(slug)
    if not on_release:
        raise SystemExit(f"no MV for {slug} on disk or on the {RELEASE} release")
    return fetch_asset(on_release, MV_DIR / on_release), on_release


def write_index(repo: Path) -> str:
    """Refresh mv-index.html so every published MV page is one click away."""
    pages = sorted(repo.glob("mv-*.html"))
    items = []
    for p in pages:
        if p.name == "mv-index.html":
            continue
        # Show the song's Thai title (the page's <h1>), not the slug.
        m = re.search(r"<h1>(.*?)</h1>", p.read_text(), re.S)
        title = m.group(1).strip() if m else p.stem[3:].replace("-", " ")
        thumb = f"{p.stem}-poster.jpg"
        href = p.name
        img = (f'<img src="{thumb}" alt="{esc_html(title)}" loading="lazy">'
               if (repo / thumb).exists() else "")
        items.append(f'<a class="card" href="{href}">{img}'
                     f'<div class="t">{esc_html(title)}</div></a>')
    grid = "\n".join(items) or "<p>เร็ว ๆ นี้</p>"
    html = f'''<!doctype html>
<html lang="th"><head>
<meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1">
<title>มิวสิควีดีโอ · AERIS Music</title>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Thai:wght@300;400;600;700&display=swap" rel="stylesheet">
<style>
:root{{--bg:#0b0b0f;--fg:#f4f4f8;--dim:#a6a6b8;--accent:#ff4d6d;--accent2:#ffb03a;--card:#1b1b26}}
*{{box-sizing:border-box;margin:0;padding:0}}
body{{background:var(--bg);color:var(--fg);font-family:"IBM Plex Sans Thai",system-ui,sans-serif;line-height:1.7;-webkit-font-smoothing:antialiased}}
a{{color:inherit;text-decoration:none}}
.wrap{{max-width:1040px;margin:0 auto;padding:26px 22px}}
h1{{font-size:1.6rem;font-weight:700;margin-bottom:6px}}
.sub{{color:var(--dim);margin-bottom:22px}}
.grid{{display:grid;gap:20px;grid-template-columns:repeat(auto-fit,minmax(280px,1fr))}}
.card{{background:var(--card);border:1px solid #24243a;border-radius:16px;overflow:hidden;transition:transform .15s,border-color .2s}}
.card:hover{{transform:translateY(-3px);border-color:#3a3a5c}}
.card img{{width:100%;aspect-ratio:16/9;object-fit:cover;display:block}}
.card .t{{padding:14px 16px;font-weight:600}}
</style></head><body>
<div class="wrap">
  <h1>มิวสิควีดีโอ · AERIS Music</h1>
  <p class="sub">ภาพยนตร์สาธารณสมบัติ ตัดตามบทเพลง · <a href="./">← หน้าแรก</a></p>
  <div class="grid">
{grid}
  </div>
</div></body></html>
'''
    (repo / "mv-index.html").write_text(html)
    return "mv-index.html"


def publish(slug: str, dry_run: bool = False, force: bool = False) -> str:
    """Render and (unless dry-run) push the watch page for one song. Returns the URL."""
    token = gh_token()
    repo = ensure_clone(token)
    url = f"https://aerismusic8-alt.github.io/{REPO.split('/')[1]}/mv-{slug}.html"
    page = repo / f"mv-{slug}.html"
    if page.exists() and not force and not dry_run:
        # The daily rail re-runs this over every MV; without this the run would
        # re-download a 100-200 MB film and re-encode it to rebuild a page that
        # is already live. Only a new MV (or --force) does real work.
        print(f"skip {slug}: page already published")
        return url

    src, asset = film_asset(slug)
    meta = song_meta(slug)
    secs = probe(src)["seconds"]

    poster, preview = f"mv-{slug}-poster.jpg", f"mv-{slug}-720p.mp4"
    subprocess.run(["ffmpeg", "-v", "error", "-y", "-ss", str(secs / 2), "-i", str(src),
                    "-frames:v", "1", "-vf", "scale=1280:720", str(repo / poster)], check=True)
    build_preview(src, repo / preview)
    html = render(slug, meta, secs, poster, preview, asset)
    page.write_text(html)
    write_index(repo)

    if dry_run:
        print(f"dry-run: wrote {page} ({preview}, {poster})")
        print(f"would publish: {url}")
        return url

    subprocess.run(["git", "-C", str(repo), "add", f"mv-{slug}.html", poster, preview,
                    "mv-index.html"], check=True)
    # A republish can be byte-identical (same film, same song), so a bare commit
    # would exit 1 and abort the push. Only commit when something is staged.
    staged = subprocess.run(["git", "-C", str(repo), "diff", "--cached", "--quiet"],
                            check=False).returncode
    if staged != 0:
        subprocess.run(["git", "-C", str(repo), "commit", "-q", "-m",
                        f"MV watch page: {slug}"], check=True)
    subprocess.run(["git", "-C", str(repo), "push", "-q", "origin", "main"], check=True)
    print(f"published: {url}")
    return url


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("slug", nargs="?", help="song slug, e.g. 26-ban-lang-lek-khong-rao")
    ap.add_argument("--all", action="store_true",
                    help="publish a page for every MV on the media release")
    ap.add_argument("--force", action="store_true",
                    help="rebuild even when the page already exists")
    ap.add_argument("--dry-run", action="store_true", help="render locally, no push")
    args = ap.parse_args(argv)

    if args.all:
        slugs = sorted(release_mv_assets())
        if not slugs:
            print("no MV assets on the release")
            return 0
        print(f"{len(slugs)} MV(s) on the release: {', '.join(slugs)}")
        for s in slugs:
            publish(s, dry_run=args.dry_run, force=args.force)
        return 0

    if not args.slug:
        ap.error("give a slug or --all")
    publish(args.slug, dry_run=args.dry_run, force=args.force)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
