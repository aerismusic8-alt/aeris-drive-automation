#!/usr/bin/env python3
"""Free stills rail: Wikimedia Commons only.

Why Commons and not an image generator:
  * It is the only image source measured to work reliably from this sandbox on
    2026-10-24. Pollinations returns 402 for most requests now (~1 image per
    several minutes) and no HuggingFace Space offers free dedicated GPU time.
  * Every file carries a machine-readable licence, so attribution can be
    generated instead of guessed. Commercial reuse needs CC0 / PD / CC BY /
    CC BY-SA, and BY / BY-SA must be credited in the description.

Thai-language queries return 0 results on Commons, so callers pass English
hints. Measured 2026-10-24: 72 usable files across 12 calm/thematic queries.
"""
import json
import os
import re
import urllib.parse
import urllib.request

UA = {"User-Agent": "AX-episode-builder/1.0 (educational channel; contact ax@example.com)"}
API = "https://commons.wikimedia.org/w/api.php"

# Licences we can use in a monetised video. BY / BY-SA additionally need credit.
OK_LICENCE = re.compile(r"(cc0|public domain|cc[ -]by)", re.I)
NEEDS_CREDIT = re.compile(r"cc[ -]by", re.I)
# NC (non-commercial) and ND (no-derivatives) are excluded on purpose.
BAD_LICENCE = re.compile(r"(\bnc\b|noncommercial|non-commercial|\bnd\b|noderiv|fair use)", re.I)


def _get(url, timeout=40):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as f:
        return json.loads(f.read().decode())


def search(query, limit=8, min_width=1400, max_tries=2):
    """Return candidate files: high-res, wide-enough, licence we can use."""
    params = {
        "action": "query", "generator": "search",
        "gsrsearch": f"{query} filetype:bitmap", "gsrnamespace": "6",
        "gsrlimit": str(limit * 3), "prop": "imageinfo",
        "iiprop": "url|size|extmetadata|mime", "iiurlwidth": "1920",
        "format": "json",
    }
    out = []
    for _ in range(max_tries):
        try:
            data = _get(f"{API}?{urllib.parse.urlencode(params)}")
        except Exception:
            continue
        for page in data.get("query", {}).get("pages", {}).values():
            ii = (page.get("imageinfo") or [{}])[0]
            if not ii or ii.get("mime", "").startswith("image/svg"):
                continue
            if ii.get("width", 0) < min_width:
                continue
            meta = ii.get("extmetadata", {})
            lic = meta.get("LicenseShortName", {}).get("value", "")
            if not OK_LICENCE.search(lic) or BAD_LICENCE.search(lic):
                continue
            out.append({
                "title": page["title"].replace("File:", ""),
                "url": ii.get("thumburl") or ii["url"],
                "source": ii["descriptionurl"],
                "licence": lic,
                "credit": re.sub(r"<[^>]+>", "", meta.get("Artist", {}).get("value", "")).strip()[:90],
                "width": ii.get("thumbwidth", ii["width"]),
                "height": ii.get("thumbheight", ii["height"]),
            })
        if out:
            break
    return out


def harvest(queries, per_query=3, cache_path=None):
    """Collect a pool of stills across topics, de-duplicated by title."""
    if cache_path and os.path.exists(cache_path):
        return json.load(open(cache_path, encoding="utf-8"))
    pool, seen = [], set()
    for q in queries:
        taken = 0
        for c in search(q, limit=per_query + 3):
            if taken >= per_query:
                break
            if c["title"] in seen:
                continue
            seen.add(c["title"])
            c["query"] = q
            pool.append(c)
            taken += 1
    if cache_path:
        os.makedirs(os.path.dirname(cache_path), exist_ok=True)
        json.dump(pool, open(cache_path, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    return pool


def download(items, out_dir, log=print):
    os.makedirs(out_dir, exist_ok=True)
    got = []
    for i, it in enumerate(items):
        ext = os.path.splitext(urllib.parse.urlparse(it["url"]).path)[1].lower() or ".jpg"
        p = os.path.join(out_dir, f"s{i:03d}{ext}")
        if os.path.exists(p) and os.path.getsize(p) > 40000:
            it["path"] = p
            got.append(it)
            continue
        try:
            with urllib.request.urlopen(urllib.request.Request(it["url"], headers=UA), timeout=90) as f:
                data = f.read()
            if len(data) < 40000:
                log(f"  skip {it['title'][:40]} (too small: {len(data)}B)")
                continue
            open(p, "wb").write(data)
            it["path"], it["bytes"] = p, len(data)
            got.append(it)
        except Exception as e:
            log(f"  download failed {it['title'][:40]}: {type(e).__name__}")
    log(f"  downloaded {len(got)}/{len(items)} stills")
    return got


def credits_block(items, header="ภาพประกอบ"):
    """Attribution text for the description. BY and BY-SA require this."""
    lines, n = [], 0
    for it in items:
        if NEEDS_CREDIT.search(it.get("licence", "")):
            n += 1
            who = it.get("credit") or "Wikimedia Commons"
            lines.append(f"{n}. {it['title']} — {who} ({it['licence']}) {it['source']}")
    if not lines:
        return ""
    return header + " (Wikimedia Commons):\n" + "\n".join(lines[:60])
