#!/usr/bin/env python3
"""Rank the songs that actually win a genre, by verified view count.

K (2026-11-23): "เพลงที่มียอดวิว 200 ล้านวิวขึ้นไป ในแต่ละแนว ... 20 เพลงในแต่ละแนวก็ได้".

A view count is not a musical judgement, so this tool does two jobs and keeps
them apart:

  * it **verifies** the number (YouTube `videos.list` statistics, not a blog
    post, not a guess) and ranks by views per year since upload, because a
    2011 hit and a 2024 hit at the same total did not age the same;
  * it writes the reference set to `work/reference-chart/<genre>.json` so the
    audio half (`ops/reference_profile.py`) has a fixed, auditable input.

What it cannot do is hear them. Ripping audio off YouTube is neither free nor
legal here, so the measurement stage runs only on audio K supplies. Until then
this answers "which songs are the bar for this genre", which is a question the
API can answer.

Quota: one `search.list` per query is 100 units, `videos.list` is 1 per call of
50. Research spends a research channel's quota (`--ch ch1` by default) so the
publishing channel (`ch3`) never loses upload budget to a scan.

    python3 ops/reference_chart.py --genre pop
    python3 ops/reference_chart.py --genre rock --min-views 200000000 --limit 20
    python3 ops/reference_chart.py --genre edm --queries "edm hit" --queries "dance music"
"""
from __future__ import annotations

import argparse
import datetime as dt
import json
import sys
import urllib.parse
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ops"))
from yt_auth import API, _request, access_token  # noqa: E402

# The genre must be one the compass publishes; a parked genre's reference set is
# wasted quota because nothing from it can ship.
GENRE_QUERIES = {
    "pop": ["เพลงไทย เพราะๆ", "เพลงไทยยอดนิยม", "thai pop hit"],
    "edm": ["edm dance hit", "thai edm", "dance music hit"],
    "hiphop": ["thai hiphop", "เพลงแรพไทย", "hip hop hit"],
    "rock": ["เพลงร็อคไทย", "thai rock hit", "rock anthem"],
    "alternative": ["thai indie alternative", "เพลงอินดี้", "alternative hit"],
}
MIN_VIEWS = 200_000_000


def _iso_duration_seconds(value: str) -> int:
    import re
    m = re.match(r"PT(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", value or "")
    if not m:
        return 0
    h, mi, s = (int(x or 0) for x in m.groups())
    return h * 3600 + mi * 60 + s


def search(query: str, token: str, limit: int = 50) -> list[str]:
    params = urllib.parse.urlencode({
        "part": "id", "q": query, "type": "video", "videoCategoryId": "10",
        "order": "viewCount", "maxResults": str(limit),
        "regionCode": "TH", "relevanceLanguage": "th",
    })
    status, body = _request(f"{API}/search?{params}",
                            headers={"Authorization": f"Bearer {token}"})
    if status != 200:
        print(f"search '{query}' -> HTTP {status}: "
              f"{body.get('error', {}).get('message', '?')}", file=sys.stderr)
        return []
    return [i["id"]["videoId"] for i in body.get("items", [])
            if i.get("id", {}).get("videoId")]


def hydrate(ids: list[str], token: str) -> list[dict]:
    out: list[dict] = []
    for i in range(0, len(ids), 50):
        chunk = ids[i:i + 50]
        params = urllib.parse.urlencode({"part": "snippet,statistics,contentDetails",
                                         "id": ",".join(chunk)})
        status, body = _request(f"{API}/videos?{params}",
                                headers={"Authorization": f"Bearer {token}"})
        if status != 200:
            print(f"videos.list -> HTTP {status}", file=sys.stderr)
            continue
        for v in body.get("items", []):
            sn, st, cd = v.get("snippet", {}), v.get("statistics", {}), v.get("contentDetails", {})
            views = int(st.get("viewCount", 0))
            published = sn.get("publishedAt", "")
            try:
                age_days = max(1, (dt.datetime.now(dt.timezone.utc)
                                   - dt.datetime.fromisoformat(published.replace("Z", "+00:00"))).days)
            except ValueError:
                age_days = 1
            out.append({
                "id": v.get("id", ""),
                "title": sn.get("title", ""),
                "channel": sn.get("channelTitle", ""),
                "published": published[:10],
                "views": views,
                "views_per_year": round(views / (age_days / 365.0)),
                "duration_s": _iso_duration_seconds(cd.get("duration", "")),
                "likes": int(st.get("likeCount", 0) or 0),
            })
    return out


def rank(videos: list[dict], min_views: int, limit: int) -> list[dict]:
    keep = {}

    def score(v: dict) -> float:
        # Views per year, with a light length penalty: a 6-hour "10 hour loop"
        # collects views without being a song anyone can sing.
        return v["views_per_year"] * (1.0 if v["duration_s"] <= 420 else 0.5)

    # One song can arrive from two queries (Thai and English title).
    for v in videos:
        if v["views"] < min_views:
            continue
        prev = keep.get(v["id"])
        if prev is None or score(v) > score(prev):
            keep[v["id"]] = v
    return sorted(keep.values(), key=score, reverse=True)[:limit]


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--genre", required=True, choices=sorted(GENRE_QUERIES))
    ap.add_argument("--queries", action="append",
                    help="override the genre's default queries (repeatable)")
    ap.add_argument("--min-views", type=int, default=MIN_VIEWS)
    ap.add_argument("--limit", type=int, default=20)
    ap.add_argument("--ch", default="ch1", help="channel whose quota pays (default ch1)")
    ap.add_argument("--out", help="default work/reference-chart/<genre>.json")
    args = ap.parse_args()

    token = access_token(args.ch)
    queries = args.queries or GENRE_QUERIES[args.genre]
    ids: list[str] = []
    for q in queries:
        found = search(q, token)
        print(f"  {q!r}: {len(found)} result(s)")
        ids.extend(found)
    rows = rank(hydrate(list(dict.fromkeys(ids)), token), args.min_views, args.limit)

    out = Path(args.out) if args.out else (
        ROOT / "music938-1/work/reference-chart" / f"{args.genre}.json")
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps({"genre": args.genre, "min_views": args.min_views,
                               "queries": queries,
                               "written": dt.datetime.now(dt.timezone.utc).isoformat(timespec="seconds"),
                               "songs": rows}, ensure_ascii=False, indent=2))

    print(f"\n{args.genre}: {len(rows)} song(s) at >= {args.min_views:,} views")
    for n, v in enumerate(rows, 1):
        print(f"  {n:2d}. {v['views']/1e6:6.0f}M  {v['views_per_year']/1e6:5.1f}M/yr  "
              f"{v['duration_s']//60}:{v['duration_s']%60:02d}  {v['title'][:48]} — {v['channel'][:24]}")
    print(f"\nwritten: {out}")
    return 0 if rows else 1


if __name__ == "__main__":
    raise SystemExit(main())
