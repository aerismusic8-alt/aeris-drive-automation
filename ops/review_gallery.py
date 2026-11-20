#!/usr/bin/env python3
"""Build a review gallery of clips that have never been uploaded anywhere.

K (2026-11-20): "ถ้ามีของเดิมส่งมาให้kดูให้หมด" then "เอาที่ยังไม่อัพพอ" — show
every finished clip that has not been published yet, in one page K can open.

The page streams each clip straight from the public `media-938` release, so it
carries no video bytes itself: the 85 unpublished clips total ~670 MB, well past
the Pages 100 MB/file limit, and committing them would bloat the site repo. The
release sets `accept-ranges`, so a `<video>` element plays them in place.

Only clips that pass the genre gate are listed. A PARKED song (lukthung, indie,
symphonic, เพื่อชีวิต) must never be shown to K as a candidate for upload; 63 of
the 148 unpublished clips are parked and are left out on purpose.

    python3 ops/review_gallery.py                 # build + push
    python3 ops/review_gallery.py --dry-run       # render to /tmp only
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import urllib.error
import urllib.request
from collections import defaultdict
from html import escape as esc
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

REPO = "aerismusic8-alt/aeris-drive-automation"
SITE = "aerismusic8-alt/site-aeris-music"
RELEASE = "media-938"
CLONE = Path(os.environ.get("MV_PAGES_DIR") or "/workspace/ax-tools/pages/site-aeris-music")
PAGE = "review-pending.html"

LANES = (
    ("short-song", "Short เพลง (ตัดท่อนฮุค)"),
    ("short-karaoke", "Short คาราโอเกะ"),
    ("short-aff", "Short สินค้า (affiliate)"),
    ("surreal", "Surreal (ภาพเซอร์เรียล)"),
    ("concert", "Concert (เวทีคอนเสิร์ต)"),
    ("karaoke", "คาราโอเกะเต็มเพลง"),
    ("film", "Film (ตัดภาพยนตร์)"),
    ("mv", "Music Video"),
    ("song", "Song (เพลงเต็ม)"),
    ("reactive", "Reactive"),
    ("mood", "Mood bed"),
    ("demo", "Demo"),
    ("short", "Short อื่น ๆ"),
)


def token() -> str:
    for name in ("AX_GH_TOKEN", "GH_TOKEN"):
        if os.environ.get(name):
            return os.environ[name]
    try:
        import ax_vault  # noqa: PLC0415
        return ax_vault.kv_get(ax_vault.ensure_anchor(),
                               "axsecrets:gh-workflow-token")["token"]
    except Exception:  # noqa: BLE001
        return ""


def gh(method: str, path: str, tok: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        "https://api.github.com" + path, data=data, method=method,
        headers={"Authorization": f"Bearer {tok}",
                 "Accept": "application/vnd.github+json",
                 "User-Agent": "AR"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def release_assets(tok: str) -> list[dict]:
    _, rel = gh("GET", f"/repos/{REPO}/releases/tags/{RELEASE}", tok)
    return [a for a in rel.get("assets", []) if a["name"].endswith(".mp4")]


def make_poster(url: str, dest: Path) -> bool:
    """Grab one frame as a small JPEG so a card is never a black box.

    `preload="none"` is deliberate: 85 clips would otherwise pull ~670 MB on
    load. Without a poster that left every card an empty black rectangle, which
    is what made the first version of this page useless to look at.
    """
    dest.parent.mkdir(parents=True, exist_ok=True)
    r = subprocess.run(
        ["ffmpeg", "-v", "error", "-y", "-ss", "1", "-i", url,
         "-frames:v", "1", "-vf", "scale=360:-2", "-q:v", "5", str(dest)],
        capture_output=True, text=True)
    return r.returncode == 0 and dest.exists() and dest.stat().st_size > 0



def posted_stems(root: Path) -> set[str]:
    """Every clip stem already published, from every ledger we keep.

    A clip counts as uploaded if any surface has it: the crosspost queue's
    `posted` map (Facebook/TikTok), the release ledger (YouTube), the reactive
    and trivia ledgers. Missing one ledger would re-offer a clip K has seen.
    """
    work = root / "work"
    done: set[str] = set()

    def add(v):
        if isinstance(v, str) and v:
            done.add(v[:-4] if v.endswith(".mp4") else v)

    st = json.loads((work / "crosspost-state.json").read_text(encoding="utf-8"))
    for k in st.get("posted", {}):
        add(k.split(":")[-1])
    for r in json.loads((work / "release-state.json").read_text(encoding="utf-8")).get("released", []):
        add(r.get("variant"))
        add(r.get("slug"))
    for k in (json.loads((work / "reactive-state.json").read_text(encoding="utf-8")).get("uploaded") or {}):
        add(k)
    for t in json.loads((work / "trivia-state.json").read_text(encoding="utf-8")).get("posted") or []:
        add(t.get("slug") if isinstance(t, dict) else t)
    return done


def lane_of(name: str) -> str:
    for lane, _ in LANES:
        if name.startswith(lane):
            return lane
    return "short"


def song_label(name: str) -> str:
    """A human title for a clip: the lyric TITLE when the song resolves."""
    import genres  # noqa: PLC0415
    slug = genres.resolve_slug(name)
    if slug:
        hdr = genres.header(slug)
        if hdr.get("title"):
            return hdr["title"]
    m = re.match(r"^[a-z-]+?-(.+?)(?:-v\d+)?\.mp4$", name)
    return (m.group(1) if m else name).replace("-", " ")


def build_html(clips: list[dict]) -> str:
    groups: dict[str, list[dict]] = defaultdict(list)
    for c in clips:
        groups[lane_of(c["name"])].append(c)

    cards = []
    for lane, label in LANES:
        items = sorted(groups.get(lane, []), key=lambda c: c["name"])
        if not items:
            continue
        cards.append(f'<h2>{esc(label)} <span class="n">{len(items)}</span></h2>')
        cards.append('<div class="grid">')
        for c in items:
            title = song_label(c["name"])
            mb = c["size"] / 1048576
            poster = f' poster="{esc(c["poster"])}"' if c.get("poster") else ""
            cards.append(
                '<figure>'
                f'<video preload="none" controls playsinline{poster}>'
                f'<source src="{esc(c["url"])}" type="video/mp4"></video>'
                f'<figcaption><b>{esc(title)}</b>'
                f'<span class="meta">{esc(c["name"])} · {mb:.1f} MB</span>'
                f'<a href="{esc(c["url"])}" target="_blank" rel="noopener">เปิดไฟล์</a>'
                '</figcaption></figure>')
        cards.append("</div>")

    return f"""<!doctype html>
<html lang="th"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title>คลิปที่ยังไม่อัพ — เพลงส้นทีนไรเนี่ย</title>
<style>
:root{{--bg:#0e0f13;--fg:#f2f3f5;--dim:#9aa0aa;--acc:#4ade80;--card:#171922}}
*{{box-sizing:border-box}}
body{{margin:0;background:var(--bg);color:var(--fg);
 font:16px/1.5 "Noto Sans Thai",system-ui,-apple-system,"Segoe UI",sans-serif}}
header{{padding:28px 20px 8px;max-width:1200px;margin:0 auto}}
h1{{margin:0 0 6px;font-size:24px}}
.lead{{color:var(--dim);margin:0}}
.lead b{{color:var(--acc)}}
h2{{max-width:1200px;margin:34px auto 10px;padding:0 20px;font-size:18px;
 display:flex;align-items:center;gap:10px}}
h2 .n{{background:var(--card);color:var(--dim);border-radius:999px;
 padding:1px 10px;font-size:13px;font-weight:400}}
.grid{{max-width:1200px;margin:0 auto;padding:0 20px;display:grid;
 grid-template-columns:repeat(auto-fill,minmax(280px,1fr));gap:18px}}
figure{{margin:0;background:var(--card);border-radius:14px;overflow:hidden;
 display:flex;flex-direction:column}}
video{{width:100%;aspect-ratio:9/16;background:#000;display:block}}
figcaption{{padding:10px 12px 12px;display:flex;flex-direction:column;gap:4px}}
figcaption b{{font-size:14px}}
.meta{{color:var(--dim);font-size:11px;word-break:break-all}}
figcaption a{{color:var(--acc);font-size:12px;text-decoration:none}}
footer{{max-width:1200px;margin:40px auto;padding:0 20px 60px;color:var(--dim);font-size:13px}}
</style></head><body>
<header>
<h1>คลิปที่ยังไม่อัพ</h1>
<p class="lead">ทั้งหมด <b>{len(clips)}</b> คลิป · เฉพาะแนว FUN ONLY ที่ K เปิดให้เผยแพร่
· เพลงที่ถูก PARKED ไม่ถูกรวมไว้ · วิดีโอสตรีมจาก release <code>{RELEASE}</code></p>
</header>
{''.join(cards)}
<footer>สร้างโดย AR (OpenHands) · หน้าดูอย่างเดียว ไม่ได้อัพขึ้นช่องใด ๆ</footer>
</body></html>
"""


def push(html: str, tok: str) -> str:
    subprocess.run(["git", "-C", str(CLONE), "pull", "--rebase", "-q"],
                   capture_output=True, text=True)
    (CLONE / PAGE).write_text(html, encoding="utf-8")
    subprocess.run(["git", "-C", str(CLONE), "add", PAGE, "poster"], check=True)
    msg = "review: the clips that have never been uploaded"
    r = subprocess.run(["git", "-C", str(CLONE), "commit", "-q", "-m", msg],
                       capture_output=True, text=True)
    if r.returncode != 0 and "nothing to commit" not in (r.stdout + r.stderr):
        raise SystemExit(f"commit failed: {r.stderr[:300]}")
    url = f"https://x-access-token:{tok}@github.com/{SITE}.git"
    p = subprocess.run(["git", "-C", str(CLONE), "push", "-q", url, "main"],
                       capture_output=True, text=True)
    if p.returncode != 0:
        raise SystemExit(f"push failed: {p.stderr[:400]}")
    return f"https://aerismusic8-alt.github.io/site-aeris-music/{PAGE}"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--posters-only", action="store_true",
                    help="build the missing posters into the Pages checkout, no push")
    a = ap.parse_args(argv)

    tok = token()
    root = Path(__file__).resolve().parent.parent / "music938-1"
    sys.path.insert(0, str(root / "scripts"))
    import genres  # noqa: PLC0415

    done = posted_stems(root)
    clips, skipped_parked = [], 0
    for asset in release_assets(tok):
        name = asset["name"]
        stem = name[:-4]
        if stem in done:
            continue
        if not name.startswith(("mood-", "demo-", "reactive-", "short-0")):
            slug = genres.resolve_slug(name)
            if not slug or not genres.publishable(slug)[0]:
                skipped_parked += 1
                continue
        clips.append({"name": name, "size": asset["size"], "stem": stem,
                      "url": asset["browser_download_url"]})

    # Posters are rendered for every clip and committed to the Pages site. The
    # release's own thumbs are served as `application/octet-stream` with
    # `content-disposition: attachment`, and Chrome refuses to paint those as a
    # `poster` — the cards stayed black even with the attribute present. Pages
    # serves a real `image/jpeg`, which does paint.
    for c in clips:
        dest = CLONE / "poster" / f"{c['stem']}.jpg"
        if not dest.exists() or dest.stat().st_size == 0:
            make_poster(c["url"], dest)
        if dest.exists() and dest.stat().st_size > 0:
            c["poster"] = f"poster/{c['stem']}.jpg"
    print(f"posters: {sum(1 for c in clips if c['poster'])}/{len(clips)}")
    still = [c["name"] for c in clips if not c["poster"]]
    if still:
        print(f"[warn] {len(still)} clips still have no poster: {still[:3]}")

    html = build_html(clips)
    if a.posters_only:
        print(f"posters written under {CLONE / 'poster'}")
        return 0
    if a.dry_run:
        out = Path("/tmp") / PAGE
        out.write_text(html, encoding="utf-8")
        print(f"dry run -> {out}")
        return 0
    print(push(html, tok))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
