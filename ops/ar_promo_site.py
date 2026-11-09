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
    sys.path.insert(0, str(Path(__file__).resolve().parent))
    from ax_secrets import get_secret  # noqa: E402
    v = get_secret(name)
    if not v:
        raise SystemExit(f"missing secret {name}")
    return v


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
                   maxResults=limit * 2)
    ids = [it["snippet"]["resourceId"]["videoId"] for it in data.get("items", [])]
    if not ids:
        return []
    # A scheduled upload is still private: its thumbnail 404s, so a card for it
    # renders broken. Keep only what a visitor can actually open.
    detail = api_get("https://www.googleapis.com/youtube/v3/videos", token,
                     part="status,snippet", id=",".join(ids))
    out = []
    for v in detail.get("items", []):
        if (v.get("status") or {}).get("privacyStatus") != "public":
            continue
        out.append({"id": v["id"], "title": v["snippet"]["title"],
                    "published": v["snippet"].get("publishedAt", "")})
        if len(out) >= limit:
            break
    return out


def channel_uploads_rss(limit: int = 9) -> list[dict]:
    """The channel's newest uploads from the public RSS feed.

    Free, keyless, no quota — so the buying-guide section can ship even on a day
    the Data API is refused (403 quotaExceeded). The feed only carries recent
    public uploads and no privacy field, which is all the site needs; the API
    path stays first because it also confirms `public`.
    """
    import xml.etree.ElementTree as ET
    url = f"https://www.youtube.com/feeds/videos.xml?channel_id={CHANNEL_ID}"
    req = urllib.request.Request(url, headers={"User-Agent": "Mozilla/5.0"})
    with urllib.request.urlopen(req, timeout=30) as r:
        root = ET.fromstring(r.read())
    ns = {"a": "http://www.w3.org/2005/Atom"}
    out = []
    for e in root.findall("a:entry", ns):
        vid = e.findtext("a:id", default="", namespaces=ns).split(":")[-1]
        title = e.findtext("a:title", default="", namespaces=ns)
        if vid:
            out.append({"id": vid, "title": title,
                        "published": e.findtext("a:published", default="", namespaces=ns)})
        if len(out) >= limit:
            break
    return out


def esc(s: str) -> str:
    return (s.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;")
             .replace('"', "&quot;"))


PLAY_ICON = ('<svg viewBox="0 0 68 48" fill="#fff"><path d="M66.5 7.7a8.5 8.5 0 0 0-6-6C55.2 0 34 0 '
             '34 0S12.8 0 7.5 1.7a8.5 8.5 0 0 0-6 6A89 89 0 0 0 0 24a89 89 0 0 0 1.5 16.3 8.5 8.5 0 0 0 6 '
             '6C12.8 48 34 48 34 48s21.2 0 26.5-1.7a8.5 8.5 0 0 0 6-6A89 89 0 0 0 68 24a89 89 0 0 0-1.5-16.3z'
             'M27 34V14l18 10z"/></svg>')

# The Page is the conversion goal. A four-advisor panel (2026-11-06) agreed the
# site's single job is to turn a visitor into a Page follower, so the first
# screen leads with the follow button — not with a YouTube subscribe.
PAGE_URL = "https://www.facebook.com/profile.php?id=61595890900382"
TIKTOK_URL = "https://www.tiktok.com/@aeris.music4"


# Buying-guide pages. Social reach is tiny and slow; a search-indexable page
# needs no audience — a searcher who types one of these queries is already
# shopping, which is where affiliate revenue actually comes from. The queries
# are real: pulled free from Google Suggest (hl=th, gl=th, 2026-11-09), not
# guessed. Each guide carries the Shopee affiliate link (the site is a YouTube
# surface, so it uses the youtube Sub_id link).
SHOPEE_URL = "https://s.shopee.co.th/8pn3G4alfI"
GUIDES: list[dict] = [
    {"q": "หูฟังบลูทูธ ยี่ห้อไหนดี",
     "title": "หูฟังบลูทูธ ยี่ห้อไหนดี — เลือกแบบไหนให้คุ้ม",
     "intro": "ก่อนซื้อหูฟังบลูทูธ ดู 3 อย่างนี้ก่อน แล้วจะเลือกได้ง่ายขึ้นมาก",
     "points": ["แบตอึดกี่ชั่วโมง — ใช้จริงต่อวันกี่ชั่วโมง",
                "ตัดเสียงรบกวน (ANC) จำเป็นกับคุณไหม",
                "ใส่สบายนานแค่ไหน — น้ำหนักและจุกหู"]},
    {"q": "หูฟัง ตัดเสียงรบกวน ยี่ห้อไหนดี",
     "title": "หูฟังตัดเสียงรบกวน (ANC) คุ้มกับเงินที่จ่ายไหม",
     "intro": "หูฟังตัดเสียงรบกวนช่วยตอนนั่งรถ เครื่องบิน หรือทำงานในที่เสียงดัง",
     "points": ["ดูค่า ANC ตอนเปิด — บางรุ่นตัดได้แค่เสียงทุ้ม",
                "โหมดเปิดฟังเสียงรอบตัว (Transparency) สำคัญในเมือง",
                "ลองเทียบรุ่นก่อนตัดสินใจ"]},
    {"q": "หูฟัง ราคาไม่เกิน 500",
     "title": "หูฟังราคาไม่เกิน 500 — ได้อะไรบ้าง",
     "intro": "งบหลักร้อยเลือกได้ ถ้ารู้ว่าอะไรสำคัญกับคุณจริง ๆ",
     "points": ["ดูสเปกแบตและระยะเชื่อมต่อก่อนยี่ห้อ",
                "งานประกอบและสายชาร์จเป็นจุดที่มักประหยัดต้นทุน",
                "อ่านรีวิวรุ่นที่จะซื้อจริง"]},
    {"q": "หู ฟัง ใส่ นอน ไม่ เจ็บ",
     "title": "หูฟังใส่นอน ไม่เจ็บ — ต้องดู 3 อย่างนี้",
     "intro": "หูฟังสำหรับใส่นอนต้องบาง เบา และไม่กดหูเวลาเอียง",
     "points": ["รูปแบบนอนหงาย/ตะแคง — แบบบุใน vs แบบคล้องหู",
                "ความหนาของตัวหูฟังตอนตะแคง",
                "เสียงไม่ต้องดังมาก แต่ต้องนุ่ม"]},
    {"q": "ลำโพงบลูทูธ ยี่ห้อไหนดี",
     "title": "ลำโพงบลูทูธ ยี่ห้อไหนดี — ตามขนาดห้อง",
     "intro": "ลำโพงบลูทูธเลือกตามขนาดห้อง ไม่ใช่ตามราคา",
     "points": ["ห้องเล็ก 10-20 วัตต์ก็พอ",
                "ดูการเชื่อมต่อและแบตก่อน",
                "วางใกล้นอนเลือกเสียงนุ่ม"]},
]


def _guides_html() -> tuple[str, str]:
    """The buying-guide section + its FAQPage JSON-LD.

    Headings and the FAQ answers carry the exact query (`g["q"]`) so the page
    can rank for it, and each card links to the Shopee affiliate link.
    """
    cards, faqs = [], []
    for g in GUIDES:
        pts = "".join(f"<li>{esc(p)}</li>" for p in g["points"])
        cards.append(
            f'    <article class="guide">\n'
            f'      <h3>{esc(g["title"])}</h3>\n'
            f'      <p class="sub" style="margin:6px 0 12px">{esc(g["intro"])}</p>\n'
            f'      <ul>{pts}</ul>\n'
            f'      <a class="btn btn-primary" href="{SHOPEE_URL}" target="_blank" '
            f'rel="nofollow sponsored noopener">ดูรุ่นที่แนะนำบน Shopee</a>\n'
            f'    </article>')
        faqs.append({"@type": "Question", "name": g["q"],
                     "acceptedAnswer": {"@type": "Answer",
                                        "text": g["intro"] + " " + " ".join(g["points"])}})
    section = (
        '  <h2>คู่มือเลือกซื้อ หูฟัง &amp; ลำโพง</h2>\n'
        '  <p class="sub">รวมคำถามที่คนถามบ่อยก่อนซื้อ — เลือกให้ตรงกับที่ใช้จริง</p>\n'
        '  <div class="grid">\n' + "\n".join(cards) + "\n  </div>")
    ld = json.dumps({"@context": "https://schema.org", "@type": "FAQPage",
                     "mainEntity": faqs}, ensure_ascii=False)
    return section, f'<script type="application/ld+json">{ld}</script>'


def render(videos: list[dict], channel_url: str) -> str:
    guide_section, guide_ld = _guides_html()
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
<title>AERIS Music — เพลงไทยต้นฉบับ · ติดตามเพจ</title>
<meta name="description" content="AERIS Music — เพลงไทยต้นฉบับ เพลงเศร้า เพื่อชีวิต ลูกทุ่ง คาราโอเกะ พร้อมคู่มือเลือกซื้อหูฟังบลูทูธและลำโพงก่อนตัดสินใจ">
<meta property="og:title" content="AERIS Music — เพลงไทยต้นฉบับ">
<meta property="og:description" content="เพลงไทยหลากหลายอารมณ์ พร้อมเวอร์ชันคาราโอเกะ ติดตามเพจไว้ไม่พลาดเพลงใหม่">
<meta property="og:type" content="website">
{guide_ld}
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
.guide{{background:var(--card);border:1px solid #24243a;border-radius:16px;padding:22px}}
.guide h3{{font-size:1.12rem;font-weight:600;line-height:1.5}}
.guide ul{{margin:0 0 16px;padding-left:20px;color:var(--dim)}}
.guide li{{margin:4px 0}}
</style>
</head>
<body>
<div class="wrap">
  <header>
    <div class="logo">AERIS<span>·</span>MUSIC</div>
    <a class="btn btn-primary" href="{PAGE_URL}" target="_blank" rel="noopener">ติดตามเพจ</a>
  </header>
  <div class="hero">
    <h1>เพลงไทย<em>ต้นฉบับ</em><br>จากใจถึงใจ</h1>
    <p>เพลงเศร้า · เพื่อชีวิต · ลูกทุ่ง · คาราโอเกะ — เพลงใหม่มาลงเพจเรื่อย ๆ<br>ติดตามเพจไว้ ไม่พลาดเพลงต่อไปครับ 🎶</p>
    <div class="cta">
      <a class="btn btn-primary" href="{PAGE_URL}" target="_blank" rel="noopener">ติดตาม AERIS Music บน Facebook</a>
      <a class="btn btn-ghost" href="{channel_url}?sub_confirmation=1" target="_blank" rel="noopener">ฟังบน YouTube</a>
    </div>
  </div>
</div>
<section class="wrap">
  <h2>เพจนี้มีอะไรให้ฟัง</h2>
  <p class="sub">เพลงไทยหลากหลายอารมณ์ พร้อมเวอร์ชันคาราโอเกะให้ร้องตาม</p>
  <div class="grid">
    <div class="card"><div class="body"><div class="t">🎵 เพลงเศร้า</div><p class="sub" style="margin:8px 0 0">สำหรับวันที่คิดถึงใครบางคน</p></div></div>
    <div class="card"><div class="body"><div class="t">🎸 เพื่อชีวิต / ร็อก</div><p class="sub" style="margin:8px 0 0">สำหรับวันที่ต้องการพลัง</p></div></div>
    <div class="card"><div class="body"><div class="t">🌾 ลูกทุ่ง</div><p class="sub" style="margin:8px 0 0">กลิ่นอายบ้านเรา</p></div></div>
    <div class="card"><div class="body"><div class="t">🎤 คาราโอเกะ</div><p class="sub" style="margin:8px 0 0">สำหรับคนที่อยากร้องตาม</p></div></div>
  </div>
</section>
<section class="wrap">
{guide_section}
</section>
<section id="music" class="wrap">
  <h2>ผลงานล่าสุด</h2>
  <p class="sub">เพลงไทยต้นฉบับจาก AERIS Music</p>
  <div class="grid">
{grid}
  </div>
</section>
<section class="wrap">
  <div class="cta" style="justify-content:center">
    <a class="btn btn-primary" href="{PAGE_URL}" target="_blank" rel="noopener">ติดตาม AERIS Music บน Facebook</a>
  </div>
</section>
<footer>
  <div class="socials">
    <a href="{PAGE_URL}" target="_blank" rel="noopener">Facebook (เพจหลัก)</a>
    <a href="{channel_url}" target="_blank" rel="noopener">YouTube</a>
    <a href="{TIKTOK_URL}" target="_blank" rel="noopener">TikTok</a>
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


def gh_token() -> str:
    v = os.environ.get("AX_GH_TOKEN") or os.environ.get("GH_TOKEN")
    if v:
        return v
    return GH_TOKEN_FILE.read_text().strip()


def main(argv=None) -> int:
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--channel", default="ch3", choices=sorted(CHANNEL_ENV))
    p.add_argument("--repo", default=DEFAULT_REPO)
    p.add_argument("--limit", type=int, default=9)
    p.add_argument("--dry-run", action="store_true", help="write the HTML to /tmp, do not push")
    p.add_argument("--out", default="/tmp/aeris-promo-site.html")
    args = p.parse_args(argv)

    try:
        videos = channel_uploads(args.channel, args.limit)
    except Exception as exc:  # noqa: BLE001 - the RSS fallback must always be tried
        print(f"Data API unavailable ({exc}); falling back to the RSS feed")
        videos = channel_uploads_rss(args.limit)
    channel_url = "https://www.youtube.com/@aerismusicth"
    html = render(videos, channel_url)
    Path(args.out).write_text(html)
    print(f"rendered {len(videos)} videos -> {args.out}")
    if args.dry_run:
        return 0
    sha = push(args.repo, html, gh_token())
    print(f"pushed {sha} to {args.repo}")
    print(f"https://{args.repo.split('/')[0]}.github.io/{args.repo.split('/')[1]}/")
    return 0


if __name__ == "__main__":
    sys.exit(main())
