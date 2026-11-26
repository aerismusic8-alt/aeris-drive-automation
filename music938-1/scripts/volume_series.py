#!/usr/bin/env python3
"""Publish the long-form compilation as a numbered weekly VOLUME SERIES.

Why this exists. The 2026-11-15 competitor scan (real public channel pages, no
API quota) found the channels that actually win the Thai "เพลงเพราะๆ ฟังสบาย"
query are not Shorts channels: they are ~100% long-form continuous compilations
(73-80 minutes each) published as a *numbered series* — "เพลงเพราะๆ ฟังสบาย
Vol.152 | รวมเพลงใหม่ ฟังยาว ไม่มีสะดุด เปิดฟังทั้งวัน", 30+ volumes deep, subs
1.5k-6k, median 1,000-3,700 views. Our channel posts a themed album once and
stops, so it has no "next episode" for YouTube to suggest; Studio Analytics says
99% new viewers / 0% returning and Browse (53%) + Suggested (33%) already do the
discovery — the missing piece is a reason to come *back*.

The advisor panel (duck + pollinations, 2026-11-15, quorum PASS) both chose this
over fixing Shorts' first 3 seconds: publish a numbered weekly long-form series.

What makes a volume a *volume*, not a re-titled album:
  - a monotonic Vol.N the channel has never published (so the number is honest),
  - the newest songs lead, the older catalogue rotates behind them, so each
    volume is genuinely new listening rather than the same tracklist (duck's
    execution detail: strongest songs up front, rotate the catalogue),
  - a continuous mix: no silence, no per-track fade-out, one bed under all of it,
  - the "next volume" breadcrumb in the description, so a finisher is pointed at
    Vol.N+1 (pollinations' execution detail).

Determinism. The rotation is a pure function of the volume number, so the same
volume always builds the same tracklist and a retry after a pod recycle is safe.

    python3 scripts/volume_series.py --next            # the volume that ships next
    python3 scripts/volume_series.py --next --list      # show its tracklist
    python3 scripts/volume_series.py --next --render    # build it
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))
import compile_album as ca  # noqa: E402

WORK = ROOT / "work"
SERIES_STATE = WORK / "volume-series-state.json"

# The scan's winning volumes run 73-80 minutes; below the ambient-loop shape and
# above the "album" shape. The title promises a continuous listen, so a short
# volume would be the lie — hold the floor at 45 minutes of real audio.
TARGET_MINUTES = 75.0
MIN_VOLUME_MINUTES = 45.0
# A volume needs enough songs to be a real continuous listen; the scan's winners
# carry dozens. 12 keeps the shape honest while the catalogue is still small.
MIN_VOLUME_TRACKS = 12

# K (2026-11-26): a "new volume" that is the previous volume's songs reordered is
# duplicate content - it competes with the volume that already works instead of
# extending it, and YouTube can read the pair as a repost. Above this share of
# the previous volume's tracklist the build refuses unless the caller says, in
# the title, that it is a remaster.
REPEAT_LIMIT = 0.8

# The scan's winners lead with a music emoji, the channel tagline, "Vol.N | ",
# then "รวมเพลงใหม่ ฟังยาว ไม่มีสะดุด เปิดฟังทั้งวัน". Keep every piece.
VOLUME_TAGLINE = "เพลงเพราะๆ ฟังสบาย"
VOLUME_PROMISE = "รวมเพลงใหม่ ฟังยาว ไม่มีสะดุด เปิดฟังทั้งวัน"


def _state() -> dict:
    if SERIES_STATE.exists():
        try:
            return json.loads(SERIES_STATE.read_text(encoding="utf-8"))
        except (ValueError, OSError):
            return {}
    return {}


def next_volume(state: dict | None = None) -> int:
    """The next volume number. 1 when nothing has shipped.

    Never trusts a filename: the number is `published + 1`, so a half-written
    state can only ever re-use a number, never skip one.
    """
    s = _state() if state is None else state
    return int(s.get("next_volume", 1))


def rotate(slugs: list[str], volume: int) -> list[str]:
    """Newest songs lead and the whole mix shifts each volume, so Vol.N+1 opens
    on a different song and is not a re-titled Vol.N.

    `slugs` arrives in catalogue order (compile_album.available_songs sorts by
    name, and newer songs sort last). The newest third leads so a returning
    viewer hears fresh material first; the newest block and the older tail each
    rotate by the volume number, so consecutive volumes do not open on the same
    song. The catalogue grows as the produce loop adds songs, so later volumes
    are genuinely longer and newer, not just reordered.
    """
    if not slugs:
        return []
    n = len(slugs)
    fresh = max(1, n // 3)
    newest, older = slugs[-fresh:], slugs[:-fresh]
    if len(newest) > 1:
        off = (volume - 1) % len(newest)
        newest = newest[off:] + newest[:off]
    if older:
        off = ((volume - 1) * 5) % len(older)
        older = older[off:] + older[:off]
    return newest + older


def pick_volume(volume: int, target_minutes: float = TARGET_MINUTES) -> list[str]:
    """The tracklist for `volume`: rotate the catalogue, then fill to target.

    Greedy fill in the rotated order, so the newest songs survive the cut and the
    volume still reaches the target length. `pick()` is not reused here because
    it walks catalogue order, which is exactly what rotation exists to change.
    """
    order = rotate(ca.available_songs(), volume)
    chosen: list[str] = []
    total = 0.0
    for slug in order:
        d = ca.duration(ca.SONGS / f"song-{slug}.mp3")
        if not d:
            continue
        cost = d if not chosen else max(0.0, d - ca.CROSSFADE)
        if total + cost > target_minutes * 60:
            continue
        chosen.append(slug)
        total += cost
    return chosen


def volume_title(volume: int) -> str:
    """The series title: emoji + tagline + "Vol.N | " + the winners' promise.

    The scan's winning volumes lead exactly this way. `(เลือกเพลงฟังได้)` is the
    single strongest signal in the wider dataset (37 winner titles, 0 loser
    titles) and the description carries the chapters that make it true, so it is
    appended when the 100-char budget allows and dropped when it does not.
    """
    title = f"🎵 {VOLUME_TAGLINE} Vol.{volume} | {VOLUME_PROMISE}"
    if len(title) + len(" (เลือกเพลงฟังได้)") <= 100:
        title += " (เลือกเพลงฟังได้)"
    return title[:100]


def volume_description(slugs: list[str], volume: int,
                       next_volume_number: int | None = None) -> str:
    """The volume description: chapters, the subscribe + Shopee ask, breadcrumb.

    One description writer for every long-form upload. `monetize.cta` leads with
    the subscribe (the 1,000-sub gate) then the Shopee link and degrades to ""
    so a description never breaks.
    """
    try:
        import monetize
        cta = monetize.cta("youtube")
    except Exception:
        cta = ""
    cta_block = f"{cta}\n\n" if cta else ""
    nxt = next_volume_number if next_volume_number is not None else volume + 1
    return (
        f"🎵 {VOLUME_TAGLINE} Vol.{volume} — รวม {len(slugs)} เพลงไทย ต่อเนื่อง\n\n"
        f"🤖 เพลงส้นทีนไรเนี่ย — ค่ายเพลง AI สร้างเพลงและเสียงร้องด้วย AI\n\n"
        f"{cta_block}"
        f"👉 กดเลือกเพลงที่อยากฟังได้จากรายการด้านล่าง\n\n"
        f"⏱️ รายการเพลง\n{ca.build_chapters(slugs)}\n\n"
        f"🎧 ฟังเพลิน ๆ ได้ทั้งวัน ไม่ต้องกดเปลี่ยน\n"
        f"▶️ ตอนถัดไป: Vol.{nxt} กำลังจะมา — กดติดตามไว้ก่อน\n"
        f"✨ เพลงส้นทีนไรเนี่ย — ค่ายเพลง AI\n\n"
        f"#เพลงไทย #รวมเพลงไทย #เพลงป็อป #เพลงแดนซ์ #เพลงร็อก "
        f"#ค่ายเพลงAI #AIMusic #เพลงส้นทีนไรเนี่ย #เพลงฟังสบาย #ฟังยาว\n"
    )


def previous_tracks(volume: int) -> list[str]:
    """The tracklist of `volume` as it shipped, or [] when it cannot be known.

    Read from the committed sidecar (`compilation-state-*.json` carries no
    tracklist; `library/compilations/volume-00N.songs` does). A missing sidecar
    returns [] and the guard then has nothing to compare against, which fails
    open on purpose: refusing to build because history is missing would stop the
    series for a reason that is not about content.
    """
    path = ca.COMPILED / f"volume-{volume:03d}.songs"
    try:
        return [ln.strip() for ln in path.read_text(encoding="utf-8").splitlines()
                if ln.strip()]
    except OSError:
        return []


def overlap(prev: list[str], new: list[str]) -> float:
    """Share of the new tracklist that the previous volume already carried."""
    if not prev or not new:
        return 0.0
    return len(set(prev) & set(new)) / len(set(new))


def remaster_title(volume: int) -> str:
    """The title for a re-release of an existing volume, saying so plainly.

    A viewer who already has Vol.N must not be offered the same songs under a
    new number; the title has to be honest enough that the difference is visible
    before the click.
    """
    title = f"🎵 {VOLUME_TAGLINE} Vol.{volume} ฉบับปรับปรุง (Remaster) | {VOLUME_PROMISE}"
    if len(title) + len(" (เลือกเพลงฟังได้)") <= 100:
        title += " (เลือกเพลงฟังได้)"
    return title[:100]


def build(volume: int, *, render: bool = False, remaster: bool = False) -> dict:
    """Prepare (and optionally render) one volume. Returns a summary dict."""
    slugs = pick_volume(volume)
    if remaster:
        prev = previous_tracks(volume - 1) or previous_tracks(volume)
        if not prev:
            return {"volume": volume, "ok": False,
                    "reason": "remaster needs the earlier volume's sidecar"}
        slugs = prev
    else:
        prev = previous_tracks(volume - 1)
        share = overlap(prev, slugs)
        if share >= REPEAT_LIMIT:
            return {"volume": volume, "ok": False, "overlap": round(share, 2),
                    "reason": (f"{share:.0%} of Vol.{volume - 1}'s songs are back; "
                               "wait for new publishable songs, or ship it as a "
                               "remaster (--remaster) with a title that says so")}
    if len(slugs) < MIN_VOLUME_TRACKS:
        return {"volume": volume, "ok": False,
                "reason": f"only {len(slugs)} eligible; need {MIN_VOLUME_TRACKS}"}
    total = (sum(ca.duration(ca.SONGS / f"song-{s}.mp3") for s in slugs)
             - ca.CROSSFADE * (len(slugs) - 1))
    if total < MIN_VOLUME_MINUTES * 60:
        return {"volume": volume, "ok": False,
                "reason": f"{total/60:.1f} min < {MIN_VOLUME_MINUTES} floor"}
    stem = (f"volume-{volume:03d}-remaster" if remaster
            else f"volume-{volume:03d}")
    title = remaster_title(volume) if remaster else volume_title(volume)
    ca.COMPILED.mkdir(parents=True, exist_ok=True)
    (ca.COMPILED / f"{stem}.title").write_text(title, encoding="utf-8")
    # The uploader runs the genre gate on every song the volume carries and
    # refuses (exit 4) when it cannot name them — that missing sidecar is what
    # stopped the series after Vol.2.
    (ca.COMPILED / f"{stem}.songs").write_text("\n".join(slugs) + "\n",
                                               encoding="utf-8")
    (ca.COMPILED / f"{stem}.txt").write_text(
        volume_description(slugs, volume), encoding="utf-8")
    out = None
    if render:
        out = ca.render(VOLUME_TAGLINE, slugs, out_name=stem)
        # render() writes its own album description; the volume description is
        # the one that carries the breadcrumb, so it wins.
        (ca.COMPILED / f"{stem}.txt").write_text(
            volume_description(slugs, volume), encoding="utf-8")
    return {"volume": volume, "ok": True, "stem": stem,
            "tracks": len(slugs), "minutes": round(total / 60, 1),
            "title": title, "remaster": remaster,
            "path": str(out) if out else None}


def record(volume: int, video_id: str | None) -> None:
    """Mark `volume` published and advance `next_volume` past it."""
    s = _state()
    vols = s.get("volumes", {})
    vols[str(volume)] = {"video_id": video_id}
    s["volumes"] = vols
    s["next_volume"] = max(int(s.get("next_volume", 1)), volume + 1)
    SERIES_STATE.write_text(json.dumps(s, ensure_ascii=False, indent=2),
                            encoding="utf-8")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--volume", type=int, help="build a specific volume")
    ap.add_argument("--next", action="store_true", help="build the next volume")
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--render", action="store_true")
    ap.add_argument("--remaster", action="store_true",
                    help="re-release the previous volume's songs, labelled as a remaster")
    args = ap.parse_args()

    volume = args.volume if args.volume else next_volume()
    if not (args.volume or args.next):
        print(f"next volume would be Vol.{volume} "
              f"(pass --next or --volume N)", file=sys.stderr)
        return 0
    if args.list:
        slugs = pick_volume(volume)
        total = (sum(ca.duration(ca.SONGS / f"song-{s}.mp3") for s in slugs)
                 - ca.CROSSFADE * (len(slugs) - 1)) if slugs else 0
        print(volume_title(volume))
        print(f"{len(slugs)} tracks, ~{total/60:.1f} min")
        print(ca.build_tracklist(slugs))
        return 0
    res = build(volume, render=args.render, remaster=args.remaster)
    print(json.dumps(res, ensure_ascii=False))
    return 0 if res.get("ok") else 1


if __name__ == "__main__":
    raise SystemExit(main())
