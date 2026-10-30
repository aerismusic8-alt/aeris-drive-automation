#!/usr/bin/env python3
"""Scan competitor YouTube channels and report what they do that we do not.

Why this exists. The channel (ch3, @aerismusicth) is a Thai music channel with
almost no audience, and "make better videos" is not an actionable instruction.
The actionable version is: read the channels that already win the same search
terms, measure them, and copy the shape that works.

What it measures, per channel and per video:

  * channel: subscribers, total videos, lifetime views, age, country, keywords
  * upload cadence: how many videos per week over the last 90 days
  * duration distribution: Shorts vs long-form, and the length of each
  * title shape: length in Thai characters, whether it carries a bracket tag
  * engagement: views, likes, comments, and likes/views per video
  * which videos are the outliers — the top decile is the pattern worth copying

Quota discipline: `search.list` costs 100 units against the same 10,000/day
project quota that uploads draw from (1,600 each). So the scan resolves channels
with search.list only when given a query, then uses channels.list (1),
playlistItems (1/page) and videos.list (1/page). A full 10-channel scan is a few
hundred units.

Usage:
    python3 scripts/competitor_scan.py --query "เพลงไทย คาราโอเกะ" --out work/competitors.json
    python3 scripts/competitor_scan.py --channel UCxxxx --channel UCyyyy
    python3 scripts/competitor_scan.py --queries-file work/competitor-queries.txt
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))
import common  # noqa: E402

TOKEN_URL = "https://oauth2.googleapis.com/token"
API = "https://www.googleapis.com/youtube/v3"


class Api:
    """Minimal YouTube Data API client on the ch3 OAuth token.

    Only read endpoints are used, so no write scope is needed. A 403 that names
    `quotaExceeded` is raised rather than retried: retrying a spent daily quota
    only burns time.
    """

    def __init__(self, token: str):
        self.token = token
        self.calls = 0
        self.units = 0
        self._cost = {"search": 100, "channels": 1, "playlistItems": 1,
                      "videos": 1, "playlists": 1}

    def get(self, path: str, **params):
        self.calls += 1
        self.units += self._cost.get(path, 1)
        url = f"{API}/{path}?" + urllib.parse.urlencode(params)
        req = urllib.request.Request(url, headers={"Authorization": f"Bearer {self.token}"})
        for attempt in range(5):
            try:
                with urllib.request.urlopen(req, timeout=60) as f:
                    return json.load(f)
            except urllib.error.HTTPError as e:
                body = e.read().decode(errors="replace")
                try:
                    parsed = json.loads(body)
                except ValueError:
                    parsed = {"raw": body}
                reason = (parsed.get("error", {}).get("errors", [{}])[0]
                          .get("reason", ""))
                if reason in ("quotaExceeded", "dailyLimitExceeded"):
                    raise SystemExit(f"YouTube quota exhausted after {self.units} units: {parsed}")
                if e.code in (429, 500, 502, 503, 504) and attempt < 4:
                    time.sleep(2 * (attempt + 1) ** 2)
                    continue
                raise SystemExit(f"HTTP {e.code} on {path}: {parsed}")
        raise RuntimeError("unreachable")


def access_token() -> str:
    rt = os.environ.get("YT_CH3_REFRESH_TOKEN")
    if not rt:
        raise SystemExit("YT_CH3_REFRESH_TOKEN is not set in this session")
    data = urllib.parse.urlencode({
        "client_id": os.environ["YT_CLIENT_ID"],
        "client_secret": os.environ["YT_CLIENT_SECRET"],
        "refresh_token": rt,
        "grant_type": "refresh_token",
    }).encode()
    with urllib.request.urlopen(TOKEN_URL, data=data, timeout=60) as f:
        return json.load(f)["access_token"]


def iso_duration_to_seconds(iso: str) -> int:
    m = re.match(r"P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", iso or "")
    if not m:
        return 0
    d, h, mi, s = (int(x) if x else 0 for x in m.groups())
    return d * 86400 + h * 3600 + mi * 60 + s


def resolve_channels(api: Api, query: str, limit: int = 10) -> list[str]:
    """Channel ids for a search query. Costs 100 units, so call it sparingly."""
    body = api.get("search", part="snippet", q=query, type="channel",
                   maxResults=limit, regionCode="TH", relevanceLanguage="th")
    return [it["id"]["channelId"] for it in body.get("items", [])]


def channel_stats(api: Api, ids: list[str]) -> list[dict]:
    body = api.get("channels", part="snippet,statistics,contentDetails,brandingSettings",
                   id=",".join(ids))
    out = []
    for it in body.get("items", []):
        s = it.get("statistics", {})
        sn = it.get("snippet", {})
        bs = (it.get("brandingSettings", {}) or {}).get("channel", {}) or {}
        out.append({
            "id": it["id"],
            "title": sn.get("title"),
            "handle": sn.get("customUrl"),
            "published": sn.get("publishedAt"),
            "country": sn.get("country"),
            "subs": int(s.get("subscriberCount", 0)) if not s.get("hiddenSubscriberCount") else None,
            "videos": int(s.get("videoCount", 0)),
            "views": int(s.get("viewCount", 0)),
            "uploads_playlist": it["contentDetails"]["relatedPlaylists"]["uploads"],
            "keywords": bs.get("keywords"),
            "description": (sn.get("description") or "")[:400],
        })
    return out


def recent_videos(api: Api, uploads_playlist: str, cap: int = 50) -> list[dict]:
    """Newest uploads with full statistics. Two calls per 50 videos.

    An auto-generated Topic channel has no uploads playlist, so the call answers
    404. That is not an error worth stopping the scan for: the channel simply
    carries no scannable catalogue.
    """
    ids, page = [], None
    while len(ids) < cap:
        kw = {"part": "contentDetails", "playlistId": uploads_playlist,
              "maxResults": 50}
        if page:
            kw["pageToken"] = page
        try:
            body = api.get("playlistItems", **kw)
        except SystemExit as exc:
            if "404" in str(exc):
                return []
            raise
        ids += [i["contentDetails"]["videoId"] for i in body.get("items", [])]
        page = body.get("nextPageToken")
        if not page:
            break
    rows = []
    for k in range(0, len(ids), 50):
        body = api.get("videos", part="snippet,statistics,contentDetails",
                       id=",".join(ids[k:k + 50]))
        for v in body.get("items", []):
            st = v.get("statistics", {})
            sn = v["snippet"]
            rows.append({
                "id": v["id"],
                "title": sn.get("title"),
                "published": sn.get("publishedAt"),
                "duration_s": iso_duration_to_seconds(v["contentDetails"]["duration"]),
                "views": int(st.get("viewCount", 0)),
                "likes": int(st.get("likeCount", 0)),
                "comments": int(st.get("commentCount", 0)),
                "tags": sn.get("tags", []),
                "thumb": (sn.get("thumbnails", {}).get("high") or {}).get("url"),
            })
    return rows


THAI = re.compile(r"[\u0e00-\u0e7f]")


def title_shape(title: str) -> dict:
    return {
        "chars": len(title),
        "thai_chars": len(THAI.findall(title)),
        "has_bracket": bool(re.search(r"[\(\[]", title)),
        "has_hashtag": "#" in title,
    }


def summarise(name: str, ch: dict, vids: list[dict]) -> dict:
    now = datetime.now(timezone.utc)
    shorts = [v for v in vids if v["duration_s"] <= 60]
    longf = [v for v in vids if v["duration_s"] > 60]
    dated = [v for v in vids if v.get("published")]
    recent = [v for v in dated
              if (now - datetime.fromisoformat(v["published"].replace("Z", "+00:00"))).days <= 90]
    days_span = None
    if len(dated) >= 2:
        ts = sorted(datetime.fromisoformat(v["published"].replace("Z", "+00:00"))
                    for v in dated)
        days_span = max(1, (ts[-1] - ts[0]).days)
    tag_pool: dict[str, int] = {}
    for v in vids:
        for t in v.get("tags", []):
            tag_pool[t] = tag_pool.get(t, 0) + 1
    by_views = sorted(vids, key=lambda v: v["views"], reverse=True)
    return {
        "name": name,
        "id": ch["id"],
        "handle": ch.get("handle"),
        "subs": ch.get("subs"),
        "total_videos": ch.get("videos"),
        "total_views": ch.get("views"),
        "published": ch.get("published"),
        "country": ch.get("country"),
        "keywords": ch.get("keywords"),
        "scanned_videos": len(vids),
        "shorts": len(shorts),
        "longform": len(longf),
        "median_longform_s": sorted(v["duration_s"] for v in longf)[len(longf) // 2] if longf else None,
        "uploads_last_90d": len(recent),
        "uploads_per_week_90d": round(len(recent) / (90 / 7), 2) if recent else 0.0,
        "history_days": days_span,
        "mean_views": round(sum(v["views"] for v in vids) / len(vids), 1) if vids else 0,
        "median_views": sorted(v["views"] for v in vids)[len(vids) // 2] if vids else 0,
        "mean_likes": round(sum(v["likes"] for v in vids) / len(vids), 1) if vids else 0,
        "like_rate_pct": round(100 * sum(v["likes"] for v in vids)
                               / max(1, sum(v["views"] for v in vids)), 3),
        "top_tags": [t for t, _ in sorted(tag_pool.items(), key=lambda x: -x[1])[:20]],
        "title_shapes": [title_shape(v["title"]) for v in vids[:20]],
        "top_videos": [{"title": v["title"], "views": v["views"], "likes": v["likes"],
                        "duration_s": v["duration_s"], "published": v["published"][:10]}
                       for v in by_views[:8]],
        "videos": vids,
    }


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--query", action="append", default=[])
    ap.add_argument("--queries-file")
    ap.add_argument("--channel", action="append", default=[])
    ap.add_argument("--per-query", type=int, default=8)
    ap.add_argument("--videos", type=int, default=40, help="uploads to scan per channel")
    ap.add_argument("--out", default=str(ROOT / "work" / "competitors.json"))
    a = ap.parse_args()

    queries = list(a.query)
    if a.queries_file:
        queries += [ln.strip() for ln in Path(a.queries_file).read_text(encoding="utf-8").splitlines()
                    if ln.strip() and not ln.startswith("#")]

    api = Api(access_token())
    ids: list[str] = list(a.channel)
    for q in queries:
        got = resolve_channels(api, q, a.per_query)
        print(f"  search {q!r} -> {len(got)} channels ({api.units} units so far)")
        ids += [c for c in got if c not in ids]

    ids = list(dict.fromkeys(ids))
    chans = channel_stats(api, ids)
    out = {"scanned_at": datetime.now(timezone.utc).isoformat(),
           "queries": queries, "units_spent": api.units, "channels": []}
    for ch in chans:
        vids = recent_videos(api, ch["uploads_playlist"], a.videos)
        out["channels"].append(summarise(ch["title"], ch, vids))
        print(f"  {ch['title'][:36]:36} subs={ch.get('subs')} vids={len(vids)} "
              f"units={api.units}")

    out["units_spent"] = api.units
    common.write_json(Path(a.out), out)
    print(f"\nwrote {a.out}  ({len(out['channels'])} channels, {api.units} units, "
          f"{api.calls} calls)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
