#!/usr/bin/env python3
"""Read a competitor channel's public page — no YouTube API quota.

Why this exists. `competitor_scan.py` uses the Data API, and its `search.list`
costs 100 units against the shared 10,000/day project quota, which the daily
release spends by mid-morning. That leaves no way to answer "what do the winning
channels do?" on the day the question is asked. The public channel page carries
the same numbers in `ytInitialData`, costs nothing, and needs no token.

What it reads per channel: subscriber count, video count, and the newest ~30
videos with views, likes-free age and duration. That is enough to see the shape
of what wins — title wording, Shorts vs long-form, cadence, and which videos
outperform the channel's median.

Usage:
    python3 ops/yt_public_scan.py @aerismusicth @somecompetitor --out work/competitors.json
    python3 ops/yt_public_scan.py --query "เพลงไทย คาราโอเกะ" --top 5
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36")
THAI = re.compile(r"[\u0e00-\u0e7f]")


def fetch(url: str) -> str:
    req = urllib.request.Request(url, headers={"User-Agent": UA,
                                               "Accept-Language": "th,en;q=0.8"})
    with urllib.request.urlopen(req, timeout=45) as f:
        return f.read().decode("utf-8", "replace")


def initial_data(html: str) -> dict:
    """The `ytInitialData` blob, brace-matched.

    A non-greedy regex stops at the first `};</script>`, which is a nested object
    on a real channel page, so the JSON is truncated and every renderer lookup
    comes back empty. Match the braces instead.
    """
    marker = html.find("var ytInitialData = ")
    if marker < 0:
        raise ValueError("no ytInitialData in page")
    start = html.find("{", marker)
    depth = 0
    in_str = esc = False
    for j in range(start, len(html)):
        c = html[j]
        if esc:
            esc = False
            continue
        if c == "\\":
            esc = True
            continue
        if c == '"':
            in_str = not in_str
            continue
        if in_str:
            continue
        if c == "{":
            depth += 1
        elif c == "}":
            depth -= 1
            if depth == 0:
                return json.loads(html[start:j + 1])
    raise ValueError("unbalanced ytInitialData")


def _walk(node, key):
    """Yield every value stored under `key` anywhere in a nested structure."""
    if isinstance(node, dict):
        for k, v in node.items():
            if k == key:
                yield v
            yield from _walk(v, key)
    elif isinstance(node, list):
        for v in node:
            yield from _walk(v, key)


def _text(node) -> str:
    if not isinstance(node, dict):
        return ""
    if "simpleText" in node:
        return node["simpleText"]
    if "runs" in node:
        return "".join(r.get("text", "") for r in node["runs"])
    if "content" in node:
        return str(node["content"])
    return ""


def _parse_int(s: str) -> int | None:
    """The number inside a label like "ผู้ติดตาม 7 คน" or "1.2M subscribers".

    The digit is not at the start — the Thai word for "subscribers" is — so a
    leading `\\d+` match returns None and the scan reports subs=None for every
    channel. Find the first number anywhere and scale a suffix. Thai scales by a
    trailing word, not a letter: พัน=1e3, หมื่น=1e4, แสน=1e5, ล้าน=1e6. Missing
    these read "1.3 หมื่น" (13,000) as 1, which is how every large channel came
    back as `subs=1`.
    """
    s = (s or "").replace(",", "").strip()
    m = re.search(r"(\d+(?:\.\d+)?)\s*(พัน|หมื่น|แสน|ล้าน|[KMB])?", s, re.I)
    if not m:
        return None
    n = float(m.group(1))
    mult = {"พัน": 1e3, "หมื่น": 1e4, "แสน": 1e5, "ล้าน": 1e6,
            "K": 1e3, "M": 1e6, "B": 1e9}.get((m.group(2) or "").upper()
                                              if m.group(2) else "", 1)
    return int(n * mult)


def channel_videos(handle: str, tab: str = "videos") -> dict:
    """Channel header plus the newest uploads, from the public page.

    Two renderer shapes are live in the wild. Older pages carry
    `videoRenderer` (title.simpleText, viewCountText, lengthText). The 2026 pages
    carry `lockupViewModel` (contentId, lockupMetadataViewModel.title.content,
    view count as an accessibilityLabel, duration in a thumbnail badge). Read
    both, or the scan silently returns nothing on one of them.
    """
    url = f"https://www.youtube.com/{handle.lstrip('/')}/{tab}"
    html = fetch(url)
    data = initial_data(html)
    hdr = (data.get("header", {}).get("pageHeaderRenderer") or {})
    title = hdr.get("pageTitle", handle)
    subs = None
    for m in re.finditer(r'"content":"([^"]*ผู้ติดตาม[^"]*)"', html):
        subs = _parse_int(m.group(1))
        break
    if subs is None:
        for m in re.finditer(r'"content":"([^"]*subscribers[^"]*)"', html):
            subs = _parse_int(m.group(1))
            break
    vids: list[dict] = []
    for vr in _walk(data, "videoRenderer"):
        vid = vr.get("videoId")
        if not vid:
            continue
        vids.append({
            "id": vid,
            "title": _text(vr.get("title", {})),
            "views": _parse_int(_text(vr.get("viewCountText", {}))),
            "age": _text(vr.get("publishedTimeText", {})),
            "duration_s": _hms(_text(vr.get("lengthText", {}))),
        })
    for lv in _walk(data, "lockupViewModel"):
        vid = lv.get("contentId")
        if not vid:
            continue
        md = (lv.get("metadata", {}).get("lockupMetadataViewModel") or {})
        title_txt = (md.get("title", {}) or {}).get("content", "")
        views = None
        age = ""
        parts = []
        for row in _walk(md.get("metadata", {}), "metadataParts"):
            parts.extend(row)
        for p in parts:
            al = p.get("accessibilityLabel", "")
            if "การดู" in al or "view" in al.lower():
                views = _parse_int(p.get("text", {}).get("content", ""))
            elif "ที่แล้ว" in al or "ago" in al.lower():
                age = p.get("text", {}).get("content", "")
        dur = None
        for b in _walk(lv.get("contentImage", {}), "thumbnailBadgeViewModel"):
            t = b.get("text", "")
            if re.fullmatch(r"\d+:\d+(:\d+)?", t or ""):
                dur = _hms(t)
                break
        vids.append({"id": vid, "title": title_txt, "views": views,
                     "age": age, "duration_s": dur})
    # The Shorts tab uses its own renderer: the title and the view count share
    # one accessibilityText ("<title>, การดู N ครั้ง - เล่นวิดีโอสั้น"), and the id
    # is in the tap endpoint, not a top-level contentId.
    for sl in _walk(data, "shortsLockupViewModel"):
        acc = sl.get("accessibilityText", "")
        vid = None
        for ep in _walk(sl.get("onTap", {}), "reelWatchEndpoint"):
            vid = ep.get("videoId")
            if vid:
                break
        if not vid:
            eid = sl.get("entityId", "")
            vid = eid.rsplit("-", 1)[-1] if "-" in eid else None
        if not vid:
            continue
        title_txt = acc.split(", การดู")[0].split(", ")[0].strip() or acc
        m = re.search(r"การดู\s*([\d.,KMB]+)", acc)
        vids.append({"id": vid, "title": title_txt,
                     "views": _parse_int(m.group(1)) if m else None,
                     "age": "", "duration_s": None, "short": True})
    return {"handle": handle, "title": title, "subs": subs, "videos": vids,
            "source": url}


def _hms(s: str) -> int | None:
    if not s or ":" not in s:
        return None
    try:
        parts = [int(x) for x in s.split(":")]
    except ValueError:
        return None
    if len(parts) == 2:
        return parts[0] * 60 + parts[1]
    if len(parts) == 3:
        return parts[0] * 3600 + parts[1] * 60 + parts[2]
    return None


def summarise(ch: dict) -> dict:
    vids = [v for v in ch["videos"] if v.get("views") is not None]
    views = sorted(v["views"] for v in vids)

    def is_short(v):
        if v.get("short"):
            return True
        d = v.get("duration_s")
        return d is not None and d <= 61

    shorts = [v for v in vids if is_short(v)]
    longf = [v for v in vids if not is_short(v)]
    med = views[len(views) // 2] if views else 0
    return {
        **{k: ch[k] for k in ("handle", "title", "subs")},
        "scanned": len(vids),
        "shorts": len(shorts),
        "longform": len(longf),
        "median_views": med,
        "mean_views": round(sum(views) / len(views), 1) if views else 0,
        "max_views": views[-1] if views else 0,
        "title_has_hashtag_pct": round(100 * sum("#" in v["title"] for v in vids) / max(1, len(vids))),
        "title_thai_pct": round(100 * sum(bool(THAI.search(v["title"])) for v in vids) / max(1, len(vids))),
        "mean_title_chars": round(sum(len(v["title"]) for v in vids) / max(1, len(vids)), 1),
        "top": sorted(vids, key=lambda v: -(v["views"] or 0))[:5],
    }


def resolve_query(query: str, top: int = 5) -> list[str]:
    """Channel handles for a search — scrapes the results page, no API cost."""
    url = ("https://www.youtube.com/results?search_query="
           + urllib.parse.quote(query) + "&sp=EgIQAg%253D%253D")  # filter: channels
    data = initial_data(fetch(url))
    out = []
    for cr in _walk(data, "channelRenderer"):
        h = _text(cr.get("subscriberCountText", {}))
        out.append({
            "handle": "/" + cr.get("navigationEndpoint", {}).get(
                "browseEndpoint", {}).get("canonicalBaseUrl", "").lstrip("/"),
            "name": _text(cr.get("title", {})),
            "subs_text": h,
        })
        if len(out) >= top:
            break
    return out


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("handles", nargs="*")
    ap.add_argument("--query")
    ap.add_argument("--top", type=int, default=5)
    ap.add_argument("--out")
    a = ap.parse_args()
    handles = list(a.handles)
    if a.query:
        for c in resolve_query(a.query, a.top):
            handles.append(c["handle"])
            print(f"  query hit: {c['name']} {c['handle']} ({c['subs_text']})")
    rows = []
    for h in handles:
        try:
            ch = channel_videos(h, "videos")
            try:
                sh = channel_videos(h, "shorts")
                seen = {v["id"] for v in ch["videos"]}
                ch["videos"] += [v for v in sh["videos"] if v["id"] not in seen]
                if ch["subs"] is None:
                    ch["subs"] = sh["subs"]
            except Exception as e:  # noqa: BLE001
                print(f"  {h}: shorts tab failed ({type(e).__name__}), long-form only")
            s = summarise(ch)
            rows.append(s)
            print(f"{h}: {s['title']} — subs={s['subs']} scanned={s['scanned']} "
                  f"median={s['median_views']} max={s['max_views']} "
                  f"shorts={s['shorts']} long={s['longform']}")
        except Exception as e:  # noqa: BLE001 — one bad channel must not stop the scan
            print(f"{h}: FAILED {type(e).__name__}: {e}")
    if a.out:
        Path(a.out).write_text(json.dumps(
            {"at": datetime.now(timezone.utc).isoformat(), "channels": rows},
            ensure_ascii=False, indent=2), encoding="utf-8")
        print(f"wrote {a.out}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
