#!/usr/bin/env python3
"""Audit a channel's uploads: what the best and worst actually look like.

K's question is not "which video won" but "what is different about the winners".
Ranking by raw views answers the wrong question, because the newest upload always
loses: a 62-minute volume published this morning cannot beat a clip from three
weeks ago. So the ranking here is **views per day since publish**, among uploads
older than `--min-age` days, and every feature is reported as a median over the
top and bottom group so one outlier cannot carry a conclusion.

Features are the ones this pipeline can actually change: title shape (length,
digit lead, emoji, separator, Thai share, hashtag), tag count, description
length, duration, publish weekday/hour, and thumbnail statistics (brightness,
contrast, saturation, edge density as a text-busy proxy).

    python3 ops/yt_audit.py --ch ch3 --n 20 --out music938-1/work/yt-audit.json
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import yt_auth  # noqa: E402

OUT_DIR = Path(__file__).resolve().parent / "out"
ROOT = Path(__file__).resolve().parent.parent
THAI = re.compile(r"[\u0e00-\u0e7f]")
EMOJI = re.compile("[\U0001F300-\U0001FAFF\u2600-\u27BF]")


def iso_duration(s: str) -> int:
    m = re.match(r"P(?:(\d+)D)?T?(?:(\d+)H)?(?:(\d+)M)?(?:(\d+)S)?", s or "")
    if not m:
        return 0
    d, h, mi, se = (int(x) if x else 0 for x in m.groups())
    return ((d * 24 + h) * 60 + mi) * 60 + se


def fetch(tok: str, ids: list[str]) -> list[dict]:
    rows = []
    for i in range(0, len(ids), 50):
        st, body = yt_auth.api_get(
            "videos", tok, part="snippet,status,statistics,contentDetails",
            id=",".join(ids[i:i + 50]))
        if st != 200:
            raise SystemExit(f"videos.list {st}: {body}")
        for v in body.get("items", []):
            sn = v["snippet"]
            rows.append({
                "id": v["id"], "title": sn["title"],
                "published": sn["publishedAt"],
                "privacy": v["status"]["privacyStatus"],
                "views": int(v.get("statistics", {}).get("viewCount", 0)),
                "likes": int(v.get("statistics", {}).get("likeCount", 0)),
                "comments": int(v.get("statistics", {}).get("commentCount", 0)),
                "seconds": iso_duration(v.get("contentDetails", {}).get("duration", "")),
                "tags": sn.get("tags", []),
                "description": sn.get("description", ""),
                "thumb": (sn.get("thumbnails", {}).get("high")
                          or sn.get("thumbnails", {}).get("medium") or {}).get("url", ""),
            })
    return rows


def title_features(title: str) -> dict:
    return {
        "len": len(title),
        "digit_lead": bool(re.match(r"^\s*[\d๐-๙]", title)),
        "emoji": bool(EMOJI.search(title)),
        "pipe": "|" in title,
        "hashtag": "#" in title,
        "thai_share": round(len(THAI.findall(title)) / max(1, len(title)), 2),
        "question": "?" in title or "?" in title,
    }


def thumb_features(url: str, cache: Path, vid: str = "") -> dict:
    """Statistics for one thumbnail.

    The cache name must carry the video id: every YouTube thumbnail URL ends in
    `hqdefault.jpg`, so keying on the file name alone made all 112 uploads share
    one image and every median come out identical.
    """
    if not url:
        return {}
    cache.mkdir(parents=True, exist_ok=True)
    f = cache / (f"{vid or 'x'}-" + (url.rsplit("/", 1)[-1].split("?")[0] or "t.jpg"))
    try:
        if not f.exists():
            urllib.request.urlretrieve(url, f)
        from PIL import Image, ImageFilter, ImageStat  # noqa: PLC0415

        im = Image.open(f).convert("RGB")
        im.thumbnail((320, 320))
        stat = ImageStat.Stat(im)
        gray = im.convert("L")
        edges = gray.filter(ImageFilter.FIND_EDGES)
        px = list(edges.getdata())
        busy = sum(1 for p in px if p > 40) / max(1, len(px))
        hsv = im.convert("HSV")
        sat = ImageStat.Stat(hsv).mean[1] / 255
        return {
            "bright": round(sum(stat.mean) / 3, 1),
            "contrast": round(sum(stat.stddev) / 3, 1),
            "saturation": round(sat, 2),
            "busy": round(busy, 3),
            "size": f"{im.width}x{im.height}",
        }
    except Exception as e:  # noqa: BLE001 - a missing thumb must not kill the audit
        return {"thumb_error": str(e)[:80]}


def enrich(rows: list[dict], cache: Path, today: datetime) -> list[dict]:
    for r in rows:
        pub = datetime.fromisoformat(r["published"].replace("Z", "+00:00"))
        r["age_days"] = max(0.5, (today - pub).total_seconds() / 86400)
        r["views_per_day"] = round(r["views"] / r["age_days"], 2)
        r["weekday"] = pub.strftime("%a")
        r["hour"] = pub.hour
        r.update({f"t_{k}": v for k, v in title_features(r["title"]).items()})
        r["tags_n"] = len(r["tags"])
        r["desc_len"] = len(r["description"])
        r.update({f"th_{k}": v for k, v in
                  thumb_features(r["thumb"], cache, r["id"]).items()})
    return rows


NUMERIC = ["views", "views_per_day", "seconds", "t_len", "t_thai_share", "tags_n",
           "desc_len", "likes", "th_bright", "th_contrast", "th_saturation", "th_busy"]
BOOLS = ["t_digit_lead", "t_emoji", "t_pipe", "t_hashtag"]


def summarise(group: list[dict]) -> dict:
    out = {}
    for k in NUMERIC:
        vals = [r[k] for r in group if isinstance(r.get(k), (int, float))]
        if vals:
            out[k] = round(statistics.median(vals), 2)
    for k in BOOLS:
        vals = [1 for r in group if r.get(k)]
        out[k + "_share"] = round(len(vals) / max(1, len(group)), 2)
    return out


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ch", default="ch3")
    ap.add_argument("--n", type=int, default=20)
    ap.add_argument("--min-age", type=float, default=14.0,
                    help="days a video must have existed to be ranked")
    ap.add_argument("--out", default="")
    a = ap.parse_args(argv)

    tok = yt_auth.access_token(a.ch)
    ids = yt_auth.all_upload_ids(tok)
    today = datetime.now(timezone.utc)
    rows = enrich(fetch(tok, ids), OUT_DIR / "thumbs", today)
    public = [r for r in rows if r["privacy"] == "public"]

    ranked = sorted([r for r in public if r["age_days"] >= a.min_age],
                    key=lambda r: r["views_per_day"], reverse=True)
    n = min(a.n, len(ranked) // 2)
    top, bottom = ranked[:n], ranked[-n:]
    shorts = [r for r in public if r["seconds"] < 600]
    longs = [r for r in public if r["seconds"] >= 600]

    report = {
        "channel": a.ch,
        "generated": today.isoformat(timespec="seconds"),
        "uploads": len(rows),
        "public": len(public),
        "ranked_pool": len(ranked),
        "min_age_days": a.min_age,
        "n": n,
        "totals": {
            "views": sum(r["views"] for r in public),
            "shorts": len(shorts), "shorts_views": sum(r["views"] for r in shorts),
            "long": len(longs), "long_views": sum(r["views"] for r in longs),
        },
        "median_all": summarise(public),
        "median_top": summarise(top),
        "median_bottom": summarise(bottom),
        "top": [{k: r[k] for k in ("id", "title", "views", "views_per_day",
                                   "age_days", "seconds", "tags_n")} for r in top],
        "bottom": [{k: r[k] for k in ("id", "title", "views", "views_per_day",
                                      "age_days", "seconds", "tags_n")} for r in bottom],
    }
    if a.out:
        p = Path(a.out)
        p.parent.mkdir(parents=True, exist_ok=True)
        p.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n",
                     encoding="utf-8")
        print(f"wrote {p}")
    # A running experiment is read by the audit that already holds the token, so
    # the verdict needs no rail of its own. A failure here must not cost the
    # report that carries the rest of the week's numbers.
    exp = ROOT / "music938-1" / "work" / "hook-experiment.json"
    if exp.exists():
        try:
            import hook_verdict  # noqa: PLC0415

            v = hook_verdict.main(["--write", "--channel", a.ch])
            print(f"hook experiment: {'read' if v == 0 else f'rc {v}'}")
        except Exception as exc:  # noqa: BLE001
            print(f"hook experiment skipped ({type(exc).__name__}: {exc})")

    print(f"public {len(public)}  ranked {len(ranked)}  top/bottom n={n}")
    for label in ("median_top", "median_bottom"):
        print(label, json.dumps(report[label], ensure_ascii=False))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
