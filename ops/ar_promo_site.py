#!/usr/bin/env python3
"""AR promo site — generate and publish the AERIS Music landing page.

The page is a real, agent-owned promotional channel: it lives on GitHub Pages
(``aerismusic8-alt/site-aeris-music``), which needs no captcha and no third
party, so it is the one social surface AR can create and refresh end to end.
Every run reads the channel's newest uploads from the YouTube Data API and
rewrites the page, so the site tracks what is actually published.

Usage
-----
    python3 ops/ar_promo_site.py --dry-run          # render to /tmp, no push
    python3 ops/ar_promo_site.py                    # render and push
    python3 ops/ar_promo_site.py --channel ch3 --repo owner/site-aeris-music
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

CHANNEL_ENV = {
    "ch1": "YT_CH1_REFRESH_TOKEN",
    "ch2": "YT_CH2_REFRESH_TOKEN",
    "ch3": "YT_CH3_REFRESH_TOKEN",
    "ch4": "YT_CH4_REFRESH_TOKEN",
}
# YouTube lists uploads under the channel's "uploads" playlist (UU<id tail>).
CHANNEL_ID = "UCm44BjAn03ruOF-WaA3ZRww"  # AERIS Music
DEFAULT_REPO = "aerismusic8-alt/site-aeris-music"
GH_TOKEN_FILE = Path(os.environ.get("AR_GH_TOKEN_FILE", "/workspace/ax-tools/ar-identity/gh-token"))


def secret(name: str) -> str:
    v = os.environ.get(name)
    if v:
        return v
    raise SystemExit(f"missing secret {name}")


def access_token(refresh_env: str) -> str:
    body = urllib.parse.urlencode({
        "client_id": secret("YT_CLIENT_ID"),
        "client_secret": secret("YT_CLIENT_SECRET"),
        "refresh_token": secret(refresh_env),
        "grant_type": "refresh_token",
    }).encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=body)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["access_token"]


def api_get(url: str, token: str, **params) -> dict:
    q = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{url}?{q}", headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def channel_uploads(channel: str, limit: int = 9) -> list[dict]:
    token = access_token(CHANNEL_ENV[channel])
    uploads_playlist = "UU" + CHANNEL_ID[2:]
    data = api_get("https://www.googleapis.com/youtube/v3/playlistItems", token,
                   part="snippet,contentDetails", playlistId=uploads_playlist,
                   maxResults=limit)
    out = []
    for it in data.get("items", []):
        sn = it["snippet"]
        vid = sn["resourceId"]["videoId"]
        out.append({"id": vid, "title": sn["title"],
                    "published": sn.get("publishedAt", "")})
    return out


def esc(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
             .replace('"', "&quot;"))


PLAY_ICON = ('<svg viewBox="0 0 68 48" fill="#fff"><path d="M66.5 7.7a8.5 8.5 0 0 0-6-6C55.2 0 34 0 '
             '34 0S12.8 0 7.5 1.7a8.5 8.5 0 0 0-6 6A89 89 0 0 0 0 24a89 89 0 0 0 1.5 16.3 8.5 8.5 0 0 0 6 '
             '6C12.8 48 34 48 34 48s21.2 0 26.5-1.7a8.5 8.5 0 0 0 6-6A89 89 0 0 0 68 24a89 89 0 0 0-1.5-16.3z'
             'M27 34V14l18 10z"/></svg>')


def render(videos: list[dict], channel_url: str) -> str:
    cards = []
    for v in videos:
        title = esc(v["title"])
        cards.append(f'''    <a class="card" href="https://youtu.be/{v['id']}" target="_blank" rel="noopener">
      <div class="thumb"><img src="https://i.ytimg.com/vi/{v['id']}/hqdefault.jpg" alt="{title}" loading="lazy"><div class="play">{PLAY_ICON}</div></div>
      <div class="body"><div class="t">{title}</div></div>
    </a>''')
    grid = "\n".join(cards) if cards else '<p class="sub">เร็ว ๆ นี้</p>'
    return f'''<!DOCTYPE html>
<html lang="th">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>AERIS Music — เพลงไทยต้นฉบับ</title>
<meta name="description" content="AERIS Music — เพลงไทยต้นฉบับ เนื้อเพลงจากใจ ฟังได้ทุกที่">
<meta property="og:title" content="AERIS Music — เพลงไทยต้นฉบับ">
<meta property="og:description" content="เพลงไทยต้นฉบับ เนื้อเพลงจากใจ ฟังได้ทุกที่">
<meta property="og:type" content="website">
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link href="https://fonts.googleapis.com/css2?family=IBM+Plex+Sans+Thai:wght@300;400;600;700&display=swap" rel="stylesheet">
<style>
:root{{--bg:#0b0b0f;--fg:#f4f4f8;--dim:#a6a6b8;--accent:#ff4d6d;--accent2:#ffb03a;--card:#1b1b26}}
*{{box-sizing:border-box;margin:0;padding:0}}
html{{scroll-behavior:smooth}}
body{{background:var(--bg);color:var(--fg);font-family:"IBM Plex Sans Thai",system-ui,sans-serif;line-height:1.7;-webkit-font-smoothing:antialiased}}
a{{color:inherit;text-decoration:none}}
.wrap{{max-width:1040px;margin:0 auto;padding:0 22px}}
header{{padding:26px 0;display:flex;align-items:center;justify-content:space-between}}
.logo{{font-weight:700;letter-spacing:.14em;font-size:1.05rem}}
.logo span{{color:var(--accent)}}
.btn{{display:inline-block;padding:12px 26px;border-radius:999px;font-weight:600;transition:transform .15s,opacity .15s}}
.btn:hover{{transform:translateY(-2px);opacity:.92}}
.btn-primary{{background:linear-gradient(120deg,var(--accent),var(--accent2));color:#12060a}}
.btn-ghost{{border:1px solid #33334a;color:var(--fg)}}
.hero{{padding:64px 0 40px;text-align:center;position:relative;overflow:hidden}}
.hero:before{{content:"";position:absolute;inset:-40% 20% auto;height:420px;background:radial-gradient(closest-side,rgba(255,77,109,.28),transparent);filter:blur(20px);z-index:-1}}
.hero h1{{font-size:clamp(2.1rem,6vw,3.6rem);font-weight:700;line-height:1.25;letter-spacing:-.01em}}
.hero h1 em{{font-style:normal;background:linear-gradient(120deg,var(--accent),var(--accent2));-webkit-background-clip:text;background-clip:text;color:transparent}}
.hero p{{color:var(--dim);font-size:1.1rem;margin:18px auto 30px;max-width:620px}}
.hero .cta{{display:flex;gap:14px;justify-content:center;flex-wrap:wrap}}
section{{padding:52px 0}}
h2{{font-size:1.5rem;font-weight:600;margin-bottom:8px}}
.sub{{color:var(--dim);margin-bottom:28px}}
.grid{{display:grid;gap:20px;grid-template-columns:repeat(auto-fit,minmax(280px,1fr))}}
.card{{background:var(--card);border:1px solid #24243a;border-radius:16px;overflow:hidden;transition:border-color .2s,transform .2s}}
.card:hover{{border-color:#3a3a5c;transform:translateY(-3px)}}
.thumb{{position:relative;aspect-ratio:16/9;background:#000}}
.thumb img{{width:100%;height:100%;object-fit:cover;display:block}}
.play{{position:absolute;inset:0;display:flex;align-items:center;justify-content:center;background:rgba(0,0,0,.25);opacity:0;transition:opacity .2s}}
.card:hover .play{{opacity:1}}
.play svg{{width:54px;height:54px;filter:drop-shadow(0 2px 8px rgba(0,0,0,.6))}}
.card .body{{padding:16px 18px}}
.card .t{{font-weight:600;font-size:1.02rem}}
footer{{border-top:1px solid #1e1e2e;padding:34px 0;color:var(--dim);font-size:.9rem;text-align:center}}
.socials{{display:flex;gap:16px;justify-content:center;margin-bottom:16px;flex-wrap:wrap}}
.socials a{{color:var(--dim);border-bottom:1px solid transparent}}
.socials a:hover{{color:var(--fg);border-color:var(--accent)}}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="logo">AERIS<span>·</span>MUSIC</div>
    <a class="btn btn-ghost" href="{channel_url}?sub_confirmation=1" target="_blank" rel="noopener">ติดตามช่อง</a>
  </header>
  <div class="hero">
    <h1>เพลงไทย<em>ต้นฉบับ</em><br>จากใจถึงใจ</h1>
    <p>AERIS Music — เพลงไทยที่แต่งและร้องเอง เนื้อเพลงจริงใจ ฟังได้ทุกที่ทุกเวลา</p>
    <div class="cta">
      <a class="btn btn-primary" href="{channel_url}?sub_confirmation=1" target="_blank" rel="noopener">สมัครรับชมบน YouTube</a>
      <a class="btn btn-ghost" href="#music">ฟังเพลง</a>
    </div>
  </div>
</div>
<section id="music" class="wrap">
  <h2>ผลงานล่าสุด</h2>
  <p class="sub">เพลงไทยต้นฉบับจาก AERIS Music</p>
  <div class="grid">
{grid}
  </div>
</section>
<footer>
  <div class="socials">
    <a href="{channel_url}" target="_blank" rel="noopener">YouTube</a>
  </div>
  <div>© AERIS Music — เพลงไทยต้นฉบับ</div>
</footer>
</body>
</html>
'''


def gh(method: str, path: str, token: str, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request("https://api.github.com" + path, data=data, method=method,
                                 headers={"Authorization": f"token {token}",
                                          "Accept": "application/vnd.github+json",
                                          "User-Agent": "AR"})
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, json.loads(e.read().decode() or "{}")


def push(repo: str, html: str, token: str) -> str:
    st, cur = gh("GET", f"/repos/{repo}/contents/index.html", token)
    sha = cur.get("sha") if st == 200 else None
    body = {"message": "chore(site): refresh promo page from channel uploads",
            "content": base64.b64encode(html.encode()).decode(), "branch": "main"}
    if sha:
        body["sha"] = sha
    st, d = gh("PUT", f"/repos/{repo}/contents/index.html", token, body)
    if st not in (200, 201):
        raise SystemExit(f"push failed: {st} {d}")
    return d["commit"]["sha"][:10]


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--channel", default="ch3", choices=sorted(CHANNEL_ENV))
    p.add_argument("--repo", default=DEFAULT_REPO)
    p.add_argument("--limit", type=int, default=9)
    p.add_argument("--dry-run", action="store_true", help="write the HTML to /tmp, do not push")
    p.add_argument("--out", default="/tmp/aeris-promo-site.html")
    args = p.parse_args(argv)

    videos = channel_uploads(args.channel, args.limit)
    channel_url = "https://www.youtube.com/@aerismusicth"
    html = render(videos, channel_url)
    Path(args.out).write_text(html)
    print(f"rendered {len(videos)} videos -> {args.out}")
    if args.dry_run:
        return 0
    token = GH_TOKEN_FILE.read_text().strip()
    sha = push(args.repo, html, token)
    print(f"pushed {sha} to {args.repo}")
    print(f"https://{args.repo.split('/')[0]}.github.io/{args.repo.split('/')[1]}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
