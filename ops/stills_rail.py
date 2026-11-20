#!/usr/bin/env python3
"""Free stills rail: Wikimedia Commons + Openverse + NASA, all licence-checked.

Why these three and not an image generator:
  * Every file carries a machine-readable licence, so attribution is generated
    rather than guessed. Commercial reuse needs CC0 / PD / CC BY / CC BY-SA, and
    BY / BY-SA must be credited in the description.
  * None needs an account, a key or a captcha — so a fresh pod, a CI runner and
    the sandbox all get the same stock with no operator action. `stock_kit.py`
    can therefore rebuild the whole set from a ~1 KB query list.
  * They are complementary. Commons is strongest for places and objects;
    Openverse indexes Flickr and the wider CC web (240+ hits per query, so a
    theme never runs dry); NASA supplies public-domain space and earth imagery.

Pollinations returns 402 for most requests now (~1 image per several minutes)
and no HuggingFace Space offers free dedicated GPU time, so neither is a source.

Thai-language queries return ~0 results on Commons, so callers pass English
hints. `harvest` interleaves the sources, so a theme Commons covers thinly is
filled in from Openverse instead of returning an empty pool.
"""
import json
import os
import re
import urllib.parse
import urllib.request

UA = {"User-Agent": "AX-episode-builder/1.0 (educational channel; contact ax@example.com)"}
API = "https://commons.wikimedia.org/w/api.php"
OPENVERSE_API = "https://api.openverse.org/v1/images/"
NASA_API = "https://images-api.nasa.gov/search"
CLEVELAND_API = "https://openaccess-api.clevelandart.org/api/artworks/"
CHICAGO_API = "https://api.artic.edu/api/v1/artworks/search"

# Licences we can use in a monetised video. BY / BY-SA additionally need credit.
OK_LICENCE = re.compile(r"(cc0|public domain|cc[ -]by|pdm|by-sa|by\b)", re.I)
NEEDS_CREDIT = re.compile(r"cc[ -]by|\bby\b", re.I)
# NC (non-commercial) and ND (no-derivatives) are excluded on purpose.
BAD_LICENCE = re.compile(r"(\bnc\b|noncommercial|non-commercial|\bnd\b|noderiv|fair use)", re.I)

# Openverse `license` codes we accept, mapped to the human name we store.
OV_OK = {"cc0": "CC0", "pdm": "Public Domain Mark", "by": "CC BY", "by-sa": "CC BY-SA"}


def _get_json(url, timeout=40):
    with urllib.request.urlopen(urllib.request.Request(url, headers=UA), timeout=timeout) as f:
        return json.loads(f.read().decode())


def search(query, limit=8, min_width=1400, max_tries=2):
    """Wikimedia Commons candidates: high-res, wide-enough, licence we can use.

    `iiurlwidth` follows `min_width` (never below 1920) instead of being pinned
    at 1920. A caller that asks for 4K material was previously handed a 1920
    thumbnail whose *reported* size was the original, so the file silently
    arrived too small for a 4K pan. Measured 2026-11-20: a 3840 request returned
    a 1280 px JPEG.
    """
    thumb_w = max(int(min_width), 1920)
    params = {
        "action": "query", "generator": "search",
        "gsrsearch": f"{query} filetype:bitmap", "gsrnamespace": "6",
        "gsrlimit": str(limit * 3), "prop": "imageinfo",
        "iiprop": "url|size|extmetadata|mime", "iiurlwidth": str(thumb_w),
        "format": "json",
    }
    out = []
    for _ in range(max_tries):
        try:
            data = _get_json(f"{API}?{urllib.parse.urlencode(params)}")
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
                "origin": "Wikimedia Commons",
            })
        if out:
            break
    return out


def search_openverse(query, limit=8, min_width=1400):
    """Openverse candidates (Flickr + the CC web). No key, no account.

    Anonymous access is rate-limited (roughly 100 req/hour), but a rebuild is a
    few dozen calls and the pool is cached, so it is rarely re-fetched.
    """
    params = {
        "q": query, "license": "cc0,pdm,by,by-sa", "size": "large",
        "page_size": str(min(limit * 3, 50)),
    }
    try:
        data = _get_json(f"{OPENVERSE_API}?{urllib.parse.urlencode(params)}")
    except Exception:
        return []
    out = []
    for r in data.get("results", []):
        code = (r.get("license") or "").lower()
        if code not in OV_OK:
            continue
        if (r.get("width") or 0) < min_width:
            continue
        url = r.get("url")
        if not url:
            continue
        out.append({
            "title": (r.get("title") or "untitled")[:120],
            "url": url,
            "source": r.get("foreign_landing_url") or url,
            "licence": OV_OK[code],
            "credit": (r.get("creator") or "").strip()[:90],
            "width": r.get("width") or 0,
            "height": r.get("height") or 0,
            "origin": "Openverse",
        })
    return out


def search_nasa(query, limit=8, min_width=1400):
    """NASA Image Library candidates. NASA imagery is public domain."""
    params = {"q": query, "media_type": "image", "page_size": str(min(limit * 3, 50))}
    try:
        data = _get_json(f"{NASA_API}?{urllib.parse.urlencode(params)}")
    except Exception:
        return []
    out = []
    for item in data.get("collection", {}).get("items", []):
        links = (item.get("links") or [{}])[0]
        href = links.get("href")
        if not href:
            continue
        meta = (item.get("data") or [{}])[0]
        out.append({
            "title": (meta.get("title") or "NASA image")[:120],
            "url": href,
            "source": href,
            "licence": "Public Domain (NASA)",
            "credit": (meta.get("center") or "NASA"),
            "width": min_width, "height": 0,
            "origin": "NASA",
        })
    return out


def search_cleveland(query, limit=8, min_width=1400):
    """Cleveland Museum of Art open access. No key; filter to CC0 only.

    The API returns a `share_license_status` per work, so only CC0 is taken —
    the museum's own CC0 subset, which needs no attribution and no ND/NC check.
    """
    params = {"q": query, "limit": str(min(limit * 3, 50)), "has_image": "1", "cc0": "1"}
    try:
        data = _get_json(f"{CLEVELAND_API}?{urllib.parse.urlencode(params)}")
    except Exception:
        return []
    out = []
    for w in data.get("data", []):
        if (w.get("share_license_status") or "").upper() != "CC0":
            continue
        imgs = w.get("images") or {}
        tier = imgs.get("print") or imgs.get("web") or {}
        url = tier.get("url")
        try:
            wd, ht = int(tier.get("width") or 0), int(tier.get("height") or 0)
        except (TypeError, ValueError):
            wd, ht = 0, 0
        if not url or wd < min_width:
            continue
        out.append({
            "title": (w.get("title") or "untitled")[:120],
            "url": url,
            "source": w.get("url") or url,
            "licence": "CC0",
            "credit": (w.get("creators") or [{}])[0].get("description", "")[:90],
            "width": wd, "height": ht,
            "origin": "Cleveland Museum",
        })
    return out


def search_chicago(query, limit=8, min_width=1400):
    """Art Institute of Chicago. No key; only works flagged public domain.

    The IIIF service serves a full-size JPEG at `.../<image_id>/full/1686,/0/default.jpg`.
    """
    params = {"q": query, "limit": str(min(limit * 3, 50)),
              "fields": "id,title,image_id,is_public_domain,artist_display"}
    try:
        data = _get_json(f"{CHICAGO_API}?{urllib.parse.urlencode(params)}")
    except Exception:
        return []
    iiif = (data.get("config") or {}).get("iiif_url", "https://www.artic.edu/iiif/2")
    out = []
    for w in data.get("data", []):
        iid = w.get("image_id")
        if not w.get("is_public_domain") or not iid:
            continue
        out.append({
            "title": (w.get("title") or "untitled")[:120],
            "url": f"{iiif}/{iid}/full/1686,/0/default.jpg",
            "source": f"https://www.artic.edu/artworks/{w.get('id')}",
            "licence": "Public Domain",
            "credit": (w.get("artist_display") or "Art Institute of Chicago")[:90],
            "width": 1686, "height": 0,
            "origin": "Art Institute of Chicago",
        })
    return out


SOURCES = [search, search_openverse, search_nasa, search_cleveland, search_chicago]


def search_multi(query, limit=8, min_width=1400):
    """Interleave the sources so a thin Commons result is filled by Openverse."""
    buckets = []
    for fn in SOURCES:
        try:
            buckets.append(fn(query, limit=limit, min_width=min_width))
        except Exception:
            buckets.append([])
    out, i = [], 0
    while any(i < len(b) for b in buckets) and len(out) < limit:
        for b in buckets:
            if i < len(b):
                out.append(b[i])
                if len(out) >= limit:
                    break
        i += 1
    return out


def harvest(queries, per_query=3, cache_path=None):
    """Collect a pool of stills across topics, de-duplicated by title."""
    if cache_path and os.path.exists(cache_path):
        return json.load(open(cache_path, encoding="utf-8"))
    pool, seen = [], set()
    for q in queries:
        taken = 0
        for c in search_multi(q, limit=per_query + 3):
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
    origins = sorted({it.get("origin") or "Wikimedia Commons" for it in items})
    for it in items:
        if NEEDS_CREDIT.search(it.get("licence", "")):
            n += 1
            who = it.get("credit") or (it.get("origin") or "Wikimedia Commons")
            lines.append(f"{n}. {it['title']} — {who} ({it['licence']}) {it['source']}")
    if not lines:
        return ""
    return f"{header} ({', '.join(origins)}):\n" + "\n".join(lines[:60])
