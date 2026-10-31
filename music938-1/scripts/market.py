#!/usr/bin/env python3
"""Measure the channel, diff it against the last reading, and write the promo brief.

The release rail publishes and the activity monitor records a channel's totals,
but neither answers "what should we do next". This does: it reads the stats of
every video the ledger says is live, compares them with the previous reading, and
writes two files into `work/`:

  * `market-snapshot.json` - the raw reading, so the next run can diff it
  * `market-report.md`     - a Thai brief: what grew, what stalled, what to promote

It is deterministic and needs no LLM, so it can run daily and cost nothing. The
weekly strategy pass reads `market-report.md` and turns it into decisions.

    python3 scripts/market.py                 # read, diff, write the brief
    python3 scripts/market.py --json          # the snapshot on stdout
    python3 scripts/market.py --channel ch3
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
WORK = ROOT / "work"
LEDGER = WORK / "release-state.json"
SNAPSHOT = WORK / "market-snapshot.json"
REPORT = WORK / "market-report.md"

CHANNEL_ENV = {
    "ch1": "YT_CH1_REFRESH_TOKEN",
    "ch2": "YT_CH2_REFRESH_TOKEN",
    "ch3": "YT_CH3_REFRESH_TOKEN",
    "ch4": "YT_CH4_REFRESH_TOKEN",
}
CHANNEL_ID = {
    "ch1": "UCI6EfsgM1HNjrYarvigxyrQ",
    "ch2": "UCM3QO5L_pmj34n1JVlbhh-w",
    "ch3": "UCm44BjAn03ruOF-WaA3ZRww",
    "ch4": "UC7gCIu4G_7QCEJ8hJ-34zoQ",
}
CHANNEL_NAME = {"ch3": "AERIS Music"}
API = "https://www.googleapis.com/youtube/v3"
MONETIZE_SUBS = 1000
MONETIZE_HOURS = 4000


def secret(name: str) -> str:
    v = os.environ.get(name)
    if not v:
        raise SystemExit(f"missing secret {name}")
    return v


def access_token(channel: str) -> str:
    body = urllib.parse.urlencode({
        "client_id": secret("YT_CLIENT_ID"),
        "client_secret": secret("YT_CLIENT_SECRET"),
        "refresh_token": secret(CHANNEL_ENV[channel]),
        "grant_type": "refresh_token",
    }).encode()
    req = urllib.request.Request("https://oauth2.googleapis.com/token", data=body)
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)["access_token"]


def yt_get(path: str, token: str, **params) -> dict:
    url = f"{API}/{path}?" + urllib.parse.urlencode(params)
    req = urllib.request.Request(url, headers={"Authorization": f"Bearer {token}"})
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.load(r)


def chunks(items: list, size: int):
    for i in range(0, len(items), size):
        yield items[i:i + size]


def released_ids(root: Path) -> list[dict]:
    """Every distinct video the ledger says is live, newest first."""
    path = root / "work" / "release-state.json"
    if not path.exists():
        return []
    state = json.loads(path.read_text(encoding="utf-8"))
    seen: dict[str, dict] = {}
    for r in state.get("released", []):
        vid = r.get("video_id")
        if vid and vid not in seen:
            seen[vid] = {"video_id": vid, "slug": r.get("slug", ""),
                         "kind": r.get("kind", ""), "public": bool(r.get("public"))}
    return list(seen.values())


def video_stats(token: str, ids: list[str]) -> dict[str, dict]:
    out: dict[str, dict] = {}
    for group in chunks(ids, 50):
        data = yt_get("videos", token, part="statistics,snippet", id=",".join(group))
        for v in data.get("items", []):
            st = v.get("statistics", {})
            sn = v.get("snippet", {})
            out[v["id"]] = {
                "title": sn.get("title", ""),
                "published": sn.get("publishedAt", ""),
                "views": int(st.get("viewCount", 0)),
                "likes": int(st.get("likeCount", 0)),
                "comments": int(st.get("commentCount", 0)),
            }
    return out


def channel_stats(token: str, channel: str) -> dict:
    data = yt_get("channels", token, part="statistics", id=CHANNEL_ID[channel])
    items = data.get("items", [])
    st = items[0]["statistics"] if items else {}
    return {"subs": int(st.get("subscriberCount", 0)),
            "views": int(st.get("viewCount", 0)),
            "videos": int(st.get("videoCount", 0))}


def read_snapshot(path: Path) -> dict:
    if path.exists():
        try:
            return json.loads(path.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            return {}
    return {}


def _delta(cur: int, prev) -> int:
    return cur - prev if isinstance(prev, int) else 0


def _arrow(d: int) -> str:
    return f"+{d:,}" if d > 0 else (f"{d:,}" if d < 0 else "—")


def build_snapshot(channel: str, channel_now: dict, videos: list[dict]) -> dict:
    return {
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "channel": channel,
        "channel_stats": channel_now,
        "videos": {v["video_id"]: v for v in videos},
    }


def render_report(prev: dict, cur: dict) -> str:
    """A Thai brief: totals, what moved, and the concrete next actions."""
    ch = cur["channel_stats"]
    pch = prev.get("channel_stats", {})
    pv = prev.get("videos", {})
    vids = list(cur["videos"].values())

    lines: list[str] = []
    lines.append("# รายงานการตลาด AERIS Music (อัตโนมัติ)\n")
    lines.append(f"อ่านเมื่อ {cur['at']} · ช่อง `{cur['channel']}`\n")

    dsubs = _delta(ch["subs"], pch.get("subs"))
    dviews = _delta(ch["views"], pch.get("views"))
    lines.append("## ภาพรวมช่อง\n")
    lines.append("| ตัวชี้วัด | ค่า | เปลี่ยนแปลง |")
    lines.append("|---|---:|---:|")
    lines.append(f"| ผู้ติดตาม | {ch['subs']:,} | {_arrow(dsubs)} |")
    lines.append(f"| ยอดชมรวม | {ch['views']:,} | {_arrow(dviews)} |")
    lines.append(f"| วิดีโอ | {ch['videos']:,} | {_arrow(_delta(ch['videos'], pch.get('videos')))} |")
    lines.append("")

    pct = (ch["subs"] / MONETIZE_SUBS) * 100
    lines.append(f"เป้าสร้างรายได้: **{ch['subs']:,} / {MONETIZE_SUBS:,} ผู้ติดตาม "
                 f"({pct:.1f}%)** และ **{MONETIZE_HOURS:,} ชั่วโมงชม/ปี**\n")

    # What grew since the last reading is the promotion signal: a video that is
    # moving now is the one worth pointing more traffic at.
    movers = []
    for v in vids:
        before = pv.get(v["video_id"], {}).get("views")
        d = _delta(v["views"], before)
        if d:
            movers.append((d, v))
    movers.sort(key=lambda t: -t[0])

    if movers:
        lines.append("## กำลังมาแรง (เทียบกับครั้งก่อน)\n")
        lines.append("| วิดีโอ | ยอดชม | เพิ่ม |")
        lines.append("|---|---:|---:|")
        for d, v in movers[:8]:
            lines.append(f"| {v['title'][:48]} | {v['views']:,} | {_arrow(d)} |")
        lines.append("")
    else:
        lines.append("_ยังไม่มีการเปลี่ยนแปลงเทียบกับครั้งก่อน (รอบแรก หรือยังไม่มีคนดู)_\n")

    lines.append("## ผลงานทั้งหมด\n")
    lines.append("| วิดีโอ | ประเภท | ยอดชม | ไลก์ | คอมเมนต์ |")
    lines.append("|---|---|---:|---:|---:|")
    for v in sorted(vids, key=lambda v: -v["views"]):
        lines.append(f"| {v['title'][:48]} | {v['kind']} | {v['views']:,} | "
                     f"{v['likes']:,} | {v['comments']:,} |")
    lines.append("")

    lines.append("## สิ่งที่ควรทำต่อ\n")
    lines.extend(_recommendations(cur, prev, movers))
    return "\n".join(lines) + "\n"


def _recommendations(cur: dict, prev: dict, movers: list) -> list[str]:
    vids = list(cur["videos"].values())
    kinds: dict[str, int] = {}
    for v in vids:
        kinds[v["kind"]] = kinds.get(v["kind"], 0) + 1

    out: list[str] = []
    if movers:
        top_d, top_v = movers[0]
        out.append(f"- **ดัน {top_v['title'][:40]}** — โตเร็วสุดรอบนี้ ({_arrow(top_d)}). "
                   f"ปักคอมเมนต์ชวนกดติดตาม และแชร์ลิงก์นี้ในหน้าโปรโมท")
    shorts = [v for v in vids if v["kind"] == "short"]
    songs = [v for v in vids if v["kind"] == "song"]
    if shorts and songs:
        best = max(shorts, key=lambda v: v["views"])
        out.append(f"- **Shorts คือเครื่องยนต์ค้นพบ** — ชุดสั้นมียอดชมนำยาว "
                   f"(สูงสุด {best['views']:,}). ทำ Short เพิ่มจากเพลงที่ยังไม่มี")
    if not vids:
        out.append("- ยังไม่มีวิดีโอที่เผยแพร่จริง — ตรวจว่า release rail ทำงาน")
    out.append("- รีเฟรชหน้าโปรโมท (GitHub Pages) ให้ชี้เพลงที่กำลังมาแรง")
    out.append("- ถ้าคอมเมนต์มีคำถาม ให้ตอบทุกอัน — สัญญาณมีส่วนร่วมช่วยการค้นพบ")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--root", help="repo root; defaults to this tree")
    ap.add_argument("--channel", default="ch3", choices=sorted(CHANNEL_ENV))
    ap.add_argument("--json", action="store_true", help="print the snapshot, do not write files")
    args = ap.parse_args()

    root = Path(args.root).resolve() if args.root else ROOT
    token = access_token(args.channel)

    rel = released_ids(root)
    stats = video_stats(token, [r["video_id"] for r in rel]) if rel else {}
    videos = []
    for r in rel:
        s = stats.get(r["video_id"])
        if s:
            videos.append({**r, **s})
    cur = build_snapshot(args.channel, channel_stats(token, args.channel), videos)

    if args.json:
        print(json.dumps(cur, ensure_ascii=False, indent=2))
        return 0

    prev = read_snapshot(root / "work" / "market-snapshot.json")
    (root / "work").mkdir(parents=True, exist_ok=True)
    (root / "work" / "market-snapshot.json").write_text(
        json.dumps(cur, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    (root / "work" / "market-report.md").write_text(
        render_report(prev, cur), encoding="utf-8")
    print(f"channel {cur['channel']}: {cur['channel_stats']['subs']} subs, "
          f"{len(videos)} videos tracked -> work/market-report.md")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
