#!/usr/bin/env python3
"""Read how the posted formats are doing and steer the queue toward what works.

K (2026-11-09): "งานที่โพสต์ต้องเช็คข้อมูลก่อนโพสต์งานต่อไปว่าผลตอบรับดีไหม ไม่ดีเปลี่ยน
ทำวนไปเรื่อยๆจนเจอรูปแบบที่มีการตอบรับ แล้วลองทำรูปแบบนั้นซ้ำ" — before posting the next
job, check how the last ones did; if a format is not getting a response, change it; keep
looping until a format responds, then repeat that format.

The honest constraint first, because it decides the whole design:

  * Facebook's Graph insights for this app answer `API access blocked`, so the Page's
    per-post reach cannot be read. `social_stats.py` can still read the Page's follower
    count through the signed-in desktop, but not per-post numbers.
  * YouTube's Data API works and is free, and `market.py` already collects per-video
    views — but a slug is shared by every cut of a song (the Short, the karaoke, the
    exhibit), so YouTube cannot separate *which FB/TK format* drew the view.
  * A TikTok post page serves its own play count to a plain logged-out request. That is
    the one direct, free, per-format signal for the FB/TK surfaces, and it is what this
    module ranks on.

So the loop ranks the formats by the median views/day of the TikTok posts we have
actually published, and only acts when the signal is strong enough to mean something:
too few posts, or a dead heat, and it leaves the varied rotation alone rather than
churning on noise. When one format clearly leads it is boosted — posted more often —
and when one clearly lags it is demoted to the back of the queue, which is K's
"แนวโน้มไม่ดีให้เปลี่ยนรูปแบบใหม่": the working formats, and the fresh ones behind
them, reach the feed before a lane that is not responding.

    python3 scripts/engagement.py            # report what the formats are doing
    python3 scripts/engagement.py --apply    # retune the committed queue
"""
from __future__ import annotations

import argparse
import json
import re
import statistics
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
QUEUE = ROOT / "work" / "crosspost-queue.json"
STATE = ROOT / "work" / "crosspost-state.json"
DECISION = ROOT / "work" / "engagement.json"

UA = ("Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 "
      "(KHTML, like Gecko) Chrome/120 Safari/537.36")

# The formats the FB/TK rail posts, and the ones worth comparing to each other. A
# photo or a link is a different job (identity / funnel), not a discovery format, so
# they are not in the race — a link is capped at one a day on purpose.
RACING = ("song", "karaoke", "surreal", "mood", "affiliate")

# How many published posts of a format before its numbers are trusted, and how far
# ahead the leader must be before the queue is retuned. Both are deliberately
# cautious: acting on two posts, or on a 10% gap, is how a feedback loop turns noise
# into a bandit problem. At the current cadence a format reaches MIN_SAMPLES in a few
# days, which is fast enough to matter and slow enough to be real.
MIN_SAMPLES = 3
LEAD_RATIO = 1.3
# How far *behind* the pack a format must be before its remaining items stop
# leading the feed ("แนวโน้มไม่ดี → เปลี่ยนรูปแบบ"). The mirror of LEAD_RATIO.
LAG_RATIO = 1.3

# Only posts from the last WINDOW_DAYS are re-read each run, and their last count is
# cached, so a run reads a handful of pages, not every post ever made. A post's
# views/day stabilises after a couple of weeks anyway, so an older post stops moving
# the decision and does not need re-reading.
WINDOW_DAYS = 14
CACHE = ROOT / "work" / "engagement-cache.json"


def load_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


def kind_of(item: dict) -> str:
    return item.get("kind") or "song"


def posted_kinds(state: dict, queue: list[dict]) -> dict[str, list[str]]:
    """Map each posted TikTok id to its format, so a play count can be attributed.

    The format lives in the queue item, not the state record, so the two are joined
    on the item id. An id with no queue row (a hand-posted clip) is skipped rather
    than guessed at.
    """
    by_id = {it["id"]: kind_of(it) for it in queue}
    out: dict[str, list[str]] = {}
    for key, rec in state.get("posted", {}).items():
        if not key.startswith("tiktok:"):
            continue
        kind = by_id.get(key)
        if kind is None:
            continue
        out.setdefault(kind, []).append(rec.get("url", ""))
    return out


def fetch_playcount(url: str, *, timeout: float = 20.0) -> int | None:
    """The public play count of one TikTok post, or None when it cannot be read.

    A logged-out GET returns the page with a `stats`/`statsV2` block; the count is
    parsed from there. None means "not read" and is never treated as zero — a format
    must not be judged on a number the platform did not give.
    """
    if not url or "tiktok.com" not in url:
        return None
    req = urllib.request.Request(url, headers={"User-Agent": UA})
    try:
        html = urllib.request.urlopen(req, timeout=timeout).read().decode("utf-8", "replace")
    except Exception:  # noqa: BLE001 — a network blip must not fail the rail
        return None
    m = re.search(r'"statsV2":\{[^}]*"playCount":"?(\d+)', html)
    if not m:
        m = re.search(r'"stats":\{[^}]*"playCount":(\d+)', html)
    return int(m.group(1)) if m else None


def days_since(rec: dict, now_epoch: float) -> float:
    try:
        t = _epoch(rec.get("at", ""))
    except ValueError:
        return 0.0
    return max((now_epoch - t) / 86400.0, 1.0 / 24.0)


def kind_stats(state: dict, queue: list[dict], counts: dict[str, int | None],
               now_epoch: float) -> dict[str, dict]:
    """Per-format sample count and median views/day, from the readable posts.

    A post whose count could not be read is left out of the sample entirely, so an
    unreadable page dilutes nothing and the median is over real numbers only.
    """
    groups = posted_kinds(state, queue)
    recs = state.get("posted", {})
    by_id = {it["id"]: kind_of(it) for it in queue}
    out: dict[str, dict] = {}
    for kind in groups:
        per_day = []
        for key, rec in recs.items():
            if not key.startswith("tiktok:") or by_id.get(key) != kind:
                continue
            c = counts.get(rec.get("url", ""))
            if c is None:
                continue
            per_day.append(c / days_since(rec, now_epoch))
        if per_day:
            out[kind] = {"n": len(per_day),
                         "median_per_day": statistics.median(per_day)}
    return out


def leader(stats: dict[str, dict], *, min_samples: int = MIN_SAMPLES,
           lead_ratio: float = LEAD_RATIO) -> str | None:
    """The format clearly ahead, or None when the signal is too thin to act on.

    None is the common, correct answer early on: with no readable counts, or a tie,
    the rail should keep its even rotation rather than chase noise. A leader needs at
    least `min_samples` readable posts and a median views/day at least `lead_ratio`
    times the runner-up's.
    """
    ranked = sorted(((k, s) for k, s in stats.items() if s["n"] >= min_samples),
                    key=lambda kv: -kv[1]["median_per_day"])
    if not ranked:
        return None
    if len(ranked) == 1:
        return ranked[0][0]
    top, second = ranked[0][1]["median_per_day"], ranked[1][1]["median_per_day"]
    if second <= 0:
        return ranked[0][0] if top > 0 else None
    return ranked[0][0] if top >= second * lead_ratio else None


def trailer(stats: dict[str, dict], *, min_samples: int = MIN_SAMPLES,
            lag_ratio: float = LAG_RATIO) -> str | None:
    """The format clearly *behind* the pack, or None when the signal is too thin.

    The mirror of `leader`, for K's "ถ้าแนวโน้มไม่ดีให้เปลี่ยนรูปแบบ": a lane whose
    median views/day is at most `1/lag_ratio` of the best lane's is not responding,
    so its remaining items should stop leading the feed. Needs at least two formats
    with enough samples — a lone format cannot be behind itself — and refuses a dead
    heat the same way `leader` does.
    """
    ranked = sorted(((k, s) for k, s in stats.items() if s["n"] >= min_samples),
                    key=lambda kv: -kv[1]["median_per_day"])
    if len(ranked) < 2:
        return None
    top = ranked[0][1]["median_per_day"]
    worst_k, worst_v = ranked[-1]
    if top <= 0:
        return None
    if worst_v["median_per_day"] * lag_ratio <= top:
        return worst_k
    return None


def retune(queue: list[dict], winner: str | None, every: int = 3,
           trailing: str | None = None) -> list[dict]:
    """Steer the queue toward the format that is working and away from the one that is not.

    The winner is folded in every `every` positions — roughly one post in four — and
    everything else keeps its order, so the feed leans into the format that is working
    without becoming only that format (the advisor warning about a look-alike wall).

    K (2026-11-10): "ถ้าแนวโน้มไม่ดีให้เปลี่ยนรูปแบบใหม่". A format that is clearly
    *behind* the others is the case a pure boost does not cover — early on, when no
    format has enough samples to lead, the loop used to leave everything alone even
    though one lane was plainly dying. `trailing` names that lane, and its items are
    pushed to the back so the working lanes (and the fresh formats behind them) reach
    the feed first. With neither a winner nor a trailing lane the queue is untouched:
    no signal, no change.
    """
    out = queue
    if winner:
        win = [it for it in out if kind_of(it) == winner]
        if win:
            rest = [it for it in out if kind_of(it) != winner]
            # local import keeps this module importable without the crosspost stack
            sys.path.insert(0, str(Path(__file__).resolve().parent))
            import crosspost  # noqa: PLC0415
            out = crosspost.interleave(rest, win, every=every, chunk=1)
    if trailing:
        demoted = [it for it in out if kind_of(it) == trailing]
        if demoted:
            out = [it for it in out if kind_of(it) != trailing] + demoted
    return out


def report(stats: dict[str, dict], win: str | None,
           lag: str | None = None) -> str:
    lines = ["# ผลตอบรับ FB/TikTok — AERIS Music", ""]
    if not stats:
        lines += ["ยังอ่านยอดดูไม่ได้ (TikTok ยังไม่มียอด หรือหน้าโหลดไม่ติด) "
                  "— คงการหมุนรูปแบบเดิมไว้ก่อน ไม่เดา", ""]
        return "\n".join(lines)
    lines += ["| รูปแบบ | โพสต์ที่อ่านได้ | ยอดดู/วัน (มัธยฐาน) |", "| --- | ---: | ---: |"]
    for k, s in sorted(stats.items(), key=lambda kv: -kv[1]["median_per_day"]):
        lines.append(f"| {k} | {s['n']} | {s['median_per_day']:.1f} |")
    lines.append("")
    if win:
        lines.append(f"**รูปแบบที่นำ:** {win} — จะดันให้โพสต์บ่อยขึ้น")
    else:
        lines.append("**ยังไม่มีรูปแบบที่นำชัด** — สัญญาณน้อยหรือสูสี "
                     "จึงคงการหมุนเดิม (ไม่ปรับจากสัญญาณรบกวน)")
    if lag:
        lines.append(f"**รูปแบบที่ตามหลัง:** {lag} — จะลดความถี่ลง (แนวโน้มไม่ดี → เปลี่ยนรูปแบบ)")
    lines.append("")
    return "\n".join(lines)


def recent_tiktok(state: dict, now_epoch: float,
                  window_days: float = WINDOW_DAYS) -> dict[str, str]:
    """Posted TikTok URLs inside the window, as `{url: item_id}`."""
    out: dict[str, str] = {}
    for key, rec in state.get("posted", {}).items():
        if not key.startswith("tiktok:"):
            continue
        url = rec.get("url", "")
        if not url:
            continue
        try:
            t = _epoch(rec.get("at", ""))
        except ValueError:
            continue
        if now_epoch - t <= window_days * 86400:
            out[url] = key
    return out


def _epoch(ts: str) -> float:
    import calendar
    import time
    return calendar.timegm(time.strptime(ts, "%Y-%m-%dT%H:%M:%SZ"))


def build_counts(state: dict, queue: list[dict], *, fetch=fetch_playcount,
                 now_epoch: float | None = None, cache: dict | None = None) -> dict:
    """Read the play count of each recent posted TikTok URL, reusing the cache.

    A URL already in the cache is not re-fetched: the count only needs refreshing
    occasionally, and this is what keeps a rail run to a few requests. An unreadable
    page stores `None`, which is dropped by `kind_stats` — never counted as zero.
    """
    import time
    now = time.time() if now_epoch is None else now_epoch
    cache = {} if cache is None else cache
    counts: dict[str, int | None] = {}
    for url in recent_tiktok(state, now):
        if url in cache:
            counts[url] = cache[url]
        else:
            counts[url] = fetch(url)
            cache[url] = counts[url]
    return counts


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--apply", action="store_true",
                    help="retune the committed queue toward the leading format")
    ap.add_argument("--json", action="store_true", help="print the numbers, write nothing")
    ap.add_argument("--now", type=float, default=None, help="epoch seconds (tests)")
    args = ap.parse_args()

    import time
    now = time.time() if args.now is None else args.now
    queue = load_json(QUEUE, [])
    state = load_json(STATE, {"posted": {}})
    cache = load_json(CACHE, {})
    counts = build_counts(state, queue, now_epoch=now, cache=cache)
    CACHE.write_text(json.dumps(cache, ensure_ascii=False, indent=1) + "\n",
                     encoding="utf-8")
    stats = kind_stats(state, queue, counts, now)
    win = leader(stats)
    lag = trailer(stats)

    if args.json:
        print(json.dumps({"stats": stats, "winner": win, "trailing": lag},
                         ensure_ascii=False, indent=1))
        return 0

    if args.apply:
        newq = retune(queue, win, trailing=lag)
        if newq != queue:
            bits = []
            if win:
                bits.append(f"boosted {win}")
            if lag:
                bits.append(f"demoted {lag}")
            QUEUE.write_text(json.dumps(newq, ensure_ascii=False, indent=2) + "\n",
                             encoding="utf-8")
            print("retuned: " + ", ".join(bits))
        else:
            print(f"no retune ({win or 'no clear leader'})")
        DECISION.write_text(json.dumps(
            {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now)),
             "winner": win, "trailing": lag, "stats": stats},
            ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8")
        return 0

    print(report(stats, win, lag))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
