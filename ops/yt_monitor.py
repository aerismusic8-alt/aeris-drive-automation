#!/usr/bin/env python3
"""Hourly snapshot of every channel's public state, committed as JSONL.

Why a schedule and not a manual reading: one reading cannot tell growth from
noise, and the monetization goal is a trend (subs, views, watch hours) rather
than a single number. A row an hour makes the trend visible and makes a stall
obvious — a channel that has not uploaded in days reads differently from one
that is simply young.

The public feeds (`/feeds/videos.xml`) return 404 from a datacenter IP and the
channel page needs JavaScript, so this uses the YouTube Data API with the
account refresh tokens. That is the one credential here, and it is deliberate:
when a token is missing or rejected the row records `status: auth_error` and the
run still succeeds, so a broken credential shows up as a gap in the series
instead of a silently missing sample.

Usage:
  python3 ops/yt_monitor.py            # append one row per channel
  python3 ops/yt_monitor.py --ch ch3   # just one channel
"""
import argparse
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import yt_auth  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / "data" / "yt-monitor.jsonl"
# A channel with no upload in this long is dormant for the "always active" goal.
STALE_HOURS = 36


def snapshot(ch: str) -> dict:
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    row = {"at": now, "ch": ch}
    try:
        tok = yt_auth.access_token(ch)
        code, body = yt_auth.api_get(
            "channels", tok, part="snippet,statistics,contentDetails", mine="true")
        item = (body.get("items") or [None])[0]
        if not item:
            row["status"] = "no_channel"
            return row
        st = item["statistics"]
        row.update({
            "status": "ok",
            "id": item["id"],
            "title": item["snippet"]["title"],
            "subs": int(st.get("subscriberCount", 0)),
            "videos": int(st.get("videoCount", 0)),
            "views": int(st.get("viewCount", 0)),
        })
        # Age of the newest upload, from the uploads playlist.
        uploads = item["contentDetails"]["relatedPlaylists"]["uploads"]
        code, pl = yt_auth.api_get(
            "playlistItems", tok, part="contentDetails",
            playlistId=uploads, maxResults=1)
        items = pl.get("items") or []
        if items:
            pub = items[0]["contentDetails"].get("videoPublishedAt")
            row["last_upload"] = pub
            if pub:
                age = datetime.now(timezone.utc) - datetime.fromisoformat(
                    pub.replace("Z", "+00:00"))
                row["hours_since_upload"] = round(age.total_seconds() / 3600, 1)
                row["stale"] = row["hours_since_upload"] > STALE_HOURS
    except SystemExit as exc:
        row["status"] = "no_token"
        row["detail"] = str(exc)[:120]
    except Exception as exc:  # a rejected token, a 403, a network blip
        row["status"] = "auth_error"
        row["detail"] = f"{type(exc).__name__}: {exc}"[:160]
    return row


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--ch", help="a single channel, e.g. ch3")
    args = ap.parse_args()

    chans = [args.ch] if args.ch else list(yt_auth.CHANNELS)
    OUT.parent.mkdir(parents=True, exist_ok=True)
    rows = [snapshot(ch) for ch in chans]
    with OUT.open("a", encoding="utf-8") as f:
        for r in rows:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    for r in rows:
        if r["status"] == "ok":
            flag = " STALE" if r.get("stale") else ""
            print(f"{r['ch']} {r['title']}: {r['subs']} subs, {r['videos']} videos, "
                  f"{r['views']} views, last upload {r.get('hours_since_upload', '?')}h ago{flag}")
        else:
            print(f"{r['ch']} {r['status']}: {r.get('detail', '')}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
