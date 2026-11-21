#!/usr/bin/env python3
"""The compass: the one place that says what NEW work is allowed to be.

K (2026-11-20): "แนวเพลงสร้างคลิป ไม่มี เข็มทิศหายแบบนี้ก็หลงทางสิ" — with no
compass the direction is lost. The repo had the rules (`genres.publishable`, the
`clip_standard` floor, the `thumb_standard` floor) but nothing that said *which
lane* may produce *what*, bound to *which* standard. So every new rail re-derived
its own answer, and three real defects followed:

  * five rails render clips, **none** renders the declared product (an MV);
  * `make_short` / `make_surreal_short` / `make_concert_short` glob
    `song-*.mp3` and render every song on disk, so 18 of 32 renders were of a
    parked genre that can never be uploaded;
  * those same three lanes never call `clip_standard` at all.

This module is the answer, and it **fails closed**: a lane that is not in
`LANES` cannot ask for a song list, and `assert_lane` raises rather than
guessing. Adding a lane means adding a row here, with its product, its audio
source, its profile and its output — the four things that were previously
implicit and drifted apart.

What it is NOT: a rewrite of the rules. `genres.publishable()` still decides a
genre, `clip_standard` still measures a file, `thumb_standard` still measures a
thumbnail. The compass only decides *which lane may run* and *which songs it may
touch*, and points at the gate each lane must pass.

Existing published clips are untouched by design: nothing here reads, moves or
re-renders a finished asset. It constrains new work only.

    python3 ops/compass.py --list          # the lanes and what each produces
    python3 ops/compass.py --songs mv      # publishable songs a lane may render
    python3 ops/compass.py --check         # exit 1 if a lane is broken
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
for _p in (ROOT / "ops", ROOT / "music938-1" / "scripts"):
    if str(_p) not in sys.path:
        sys.path.insert(0, str(_p))

import clip_standard  # noqa: E402  (path set up above)

# --- What a lane may be -----------------------------------------------------
# `product` — a finished video for an audience. The song is the thing being
#   watched (K, 2026-11-20: "เราทำเพลงนะไม่ใช่คลิปบรรยาย").
# `tool`    — a renderer we keep, but which is not a format to produce for the
#   channel. `ops/story_reel.py` is narration over stills: useful, not our product.
# `retired` — a lane K ordered stopped. It must not render new work.
PRODUCT = "product"
TOOL = "tool"
RETIRED = "retired"

# `audio` is the sharpest test of "is this our product": if a build produces a
# voice explaining something, it is the wrong rail.
SONG = "song"          # the song is the soundtrack (an MV / Short / exhibit)
BED = "bed"            # an instrumental bed, no vocal, no song title
NARRATION = "narration"  # a spoken explanation — not a music product
SILENT = "silent"      # an intermediate asset

# One row per lane. `profile` is a `clip_standard` profile the output must pass;
# `None` means the lane is not publishable at all (an internal asset), which is
# only legal for `TOOL`/`RETIRED` rows — `--check` enforces that.
LANES: dict[str, dict] = {
    "mv": {
        "script": "music938-1/scripts/make_music_video.py",
        "kind": PRODUCT, "audio": SONG, "profile": "vertical",
        "out": "music938-1/library/musicvideo", "name": "mv-<slug>-full.mp4",
        "rail": None,
        "note": "THE declared product (K 2026-11-20). No rail renders it yet.",
    },
    "film": {
        "script": "music938-1/scripts/make_film_video.py",
        "kind": PRODUCT, "audio": SONG, "profile": "film",
        "out": "music938-1/library/musicvideo", "name": "<slug>.mp4",
        "rail": None,
        "note": "long-form MV over public-domain film; landscape 16:9.",
    },
    "short": {
        "script": "music938-1/scripts/make_short.py",
        "kind": PRODUCT, "audio": SONG, "profile": "short",
        "out": "music938-1/library/shorts", "name": "short-song-<slug>.mp4",
        "rail": ".github/workflows/ax-music-karaoke-render.yml",
        "note": "discovery Short; burns captions, so it carries the text floor.",
    },
    "surreal": {
        "script": "music938-1/scripts/make_surreal_short.py",
        "kind": PRODUCT, "audio": SONG, "profile": "vertical",
        "out": "music938-1/library/surreal", "name": "surreal-<slug>.mp4",
        "rail": ".github/workflows/ax-music-surreal-render.yml",
        "note": "absurd-exhibit Short, bedded on the song.",
    },
    "concert": {
        "script": "music938-1/scripts/make_concert_short.py",
        "kind": PRODUCT, "audio": SONG, "profile": "vertical",
        "out": "music938-1/library/concert", "name": "concert-<slug>.mp4",
        "rail": ".github/workflows/ax-music-concert-render.yml",
        "note": "live-concert-styled Short.",
    },
    "affiliate": {
        "script": "music938-1/scripts/make_affiliate_short.py",
        "kind": PRODUCT, "audio": SONG, "profile": "vertical",
        "out": "music938-1/library/affiliate", "name": "short-aff-<id>.mp4",
        "rail": ".github/workflows/ax-music-affiliate-render.yml",
        "note": "Shopee product card, bedded on a channel song (the funnel).",
    },
    "bank": {
        "script": "ops/clip_lane.py",
        "kind": PRODUCT, "audio": SONG, "profile": "bank",
        "out": "music938-1/library/bank", "name": "bank-<mix>-<id>-<theme>.mp4",
        "rail": ".github/workflows/ax-clip-lane.yml",
        "publish_rail": ".github/workflows/ax-bank-publish.yml",
        "note": "VJ clip from the picture bank; published by ax-bank-publish.",
    },
    "reactive": {
        "script": "ops/make_reactive.py",
        "kind": PRODUCT, "audio": SONG, "profile": "vertical",
        "out": "/workspace/ax-tools/incoming/reactive", "name": "<mode>-reactive-<slug>.mp4",
        "rail": ".github/workflows/ax-music-reactive.yml",
        "note": "picture computed from the audio (equalizer + dancing mascot).",
    },
    "moods": {
        "script": "music938-1/scripts/make_mood_short.py",
        "kind": PRODUCT, "audio": BED, "profile": "vertical",
        "out": "music938-1/library/moods", "name": "mood-<mood>.mp4",
        "rail": ".github/workflows/ax-music-produce.yml",
        "note": "real-instrument mood bed (K approved 2026-11-09). No song slug.",
    },
    "compilation": {
        "script": "music938-1/scripts/compile_album.py",
        "kind": PRODUCT, "audio": SONG, "profile": "horizontal",
        "out": "music938-1/library/compilations", "name": "<name>.mp4",
        "rail": ".github/workflows/ax-music-compilation.yml",
        "note": "long-form album; watch-hour fuel.",
    },
    "trivia": {
        "script": "ops/trivia_reel.py",
        "kind": PRODUCT, "audio": NARRATION, "profile": "trivia",
        "out": "music938-1/library/trivia", "name": "<fact>.mp4",
        "rail": ".github/workflows/ax-music-trivia.yml",
        "note": "a factual format K asked for BY NAME, so it is allowed to narrate.",
    },
    "story": {
        "script": "ops/story_reel.py",
        "kind": TOOL, "audio": NARRATION, "profile": "vertical",
        "out": "music938-1/library/stories", "name": "<theme>.mp4",
        "rail": None,
        "note": "narration over stills — a tool, NOT a product (CHARTER 2026-11-20).",
    },
    "karaoke": {
        "script": "music938-1/scripts/make_karaoke.py",
        "kind": RETIRED, "audio": SONG, "profile": "horizontal",
        "out": "music938-1/library/karaoke", "name": "<mix>-<slug>.mp4",
        "rail": None,
        "note": "RETIRED by K (2026-11-03): the lyric sweep was estimated, not "
                "measured. CHARTER's asset list still names it — K's order wins.",
    },
    "motion": {
        "script": "music938-1/scripts/make_motion.py",
        "kind": TOOL, "audio": SILENT, "profile": "motion",
        "out": "music938-1/library/motion", "name": "motion-<slug>.mp4",
        "rail": None,
        "note": "silent 3-4 s intermediate; `motion` profile is not publishable.",
    },
}


def lanes(kind: str | None = None) -> dict[str, dict]:
    """Lane rows, optionally only one kind (PRODUCT / TOOL / RETIRED)."""
    if kind is None:
        return dict(LANES)
    return {k: v for k, v in LANES.items() if v["kind"] == kind}


def products() -> dict[str, dict]:
    """Lanes that produce something for an audience."""
    return lanes(PRODUCT)


def assert_lane(lane: str) -> dict:
    """Return the lane row, or refuse. Fails closed: an unlisted lane is a bug.

    A new rail that renders without a compass row is exactly how the direction
    got lost, so the answer is an exception with the fix in the message, not a
    silent default.
    """
    row = LANES.get(lane)
    if row is None:
        raise SystemExit(
            f"COMPASS: '{lane}' is not a known lane. Add a row to "
            f"ops/compass.py LANES (script, kind, audio, profile, out) before it "
            f"may render. Known: {', '.join(sorted(LANES))}")
    return row


def may_render(lane: str) -> tuple[bool, str]:
    """May this lane produce NEW work? Returns (ok, why)."""
    row = assert_lane(lane)
    if row["kind"] == RETIRED:
        return False, f"lane '{lane}' is retired — {row['note']}"
    return True, f"lane '{lane}' is {row['kind']} ({row['audio']} audio)"


def songs(lane: str, *, available: list[str] | None = None) -> list[str]:
    """The songs this lane may render: publishable genre, and a master on disk.

    This is the single enumeration every render lane must use. Globbing
    `song-*.mp3` directly is what produced 18 unuploadable clips, because the
    release still carries the original masters of a parked genre.

    `available` lets a caller that already listed the catalogue (from the
    release, say) filter that list instead of the local disk — the release is
    the catalogue, and a local cache must never narrow it.
    """
    row = assert_lane(lane)
    ok, why = may_render(lane)
    if not ok:
        raise SystemExit(f"COMPASS: {why}")
    if row["audio"] != SONG:
        raise SystemExit(
            f"COMPASS: lane '{lane}' is not song-based ({row['audio']}); it has no "
            f"song list — its output is not tied to a song slug")

    import genres  # noqa: PLC0415  (music938-1/scripts)

    if available is None:
        songs_dir = ROOT / "music938-1" / "library" / "songs"
        available = sorted(p.stem[len("song-"):] for p in songs_dir.glob("song-*.mp3"))
    kept: list[str] = []
    for slug in sorted(set(available)):
        if genres.publishable(slug)[0]:
            kept.append(slug)
    return kept


def dropped(lane: str, *, available: list[str] | None = None) -> list[str]:
    """The songs `songs()` refused, for a log line that explains the skip."""
    if available is None:
        songs_dir = ROOT / "music938-1" / "library" / "songs"
        available = sorted(p.stem[len("song-"):] for p in songs_dir.glob("song-*.mp3"))
    keep = set(songs(lane, available=available))
    return sorted(set(available) - keep)


def is_publishable(slug: str) -> tuple[bool, str]:
    """May a clip of this one song be published? Returns (ok, why).

    The single-slug form of `songs()`, for a lane that is handed a slug instead
    of a list (a rail input, an MV build). It delegates to
    `genres.publishable()` so there is still one rule; what it removes is the
    local `genres.publishable(...)` call in each lane, which is how the answers
    drifted apart in the first place.
    """
    import genres  # noqa: PLC0415  (music938-1/scripts)

    return genres.publishable(slug)


def check() -> list[tuple[str, bool, str]]:
    """Structural checks on the compass itself. Used by `--check` and the suite."""
    rows: list[tuple[str, bool, str]] = []
    for lane, row in LANES.items():
        script = ROOT / row["script"]
        rows.append((f"{lane}: script exists", script.exists(), row["script"]))
        prof = row["profile"]
        if prof is None:
            rows.append((f"{lane}: only a tool may skip the profile",
                         row["kind"] != PRODUCT, f"kind={row['kind']}"))
        else:
            rows.append((f"{lane}: profile '{prof}' exists in clip_standard",
                         prof in clip_standard.PROFILES, str(list(clip_standard.PROFILES))))
            mapped = clip_standard.LANE_PROFILE.get(lane)
            rows.append((f"{lane}: clip_standard agrees ({mapped})",
                         mapped in (None, prof), f"compass={prof} standard={mapped}"))
        if row["kind"] == PRODUCT:
            rows.append((f"{lane}: a product has an audio source",
                         row["audio"] in (SONG, BED, NARRATION), row["audio"]))
        for key in ("rail", "publish_rail"):
            rail = row.get(key)
            if rail:
                rows.append((f"{lane}: its {key} exists", (ROOT / rail).exists(), rail))
        if row["kind"] == PRODUCT and row["audio"] == SONG:
            rows.append((f"{lane}: a song product names its songs through the compass",
                         "compass" in script.read_text(encoding="utf-8")
                         if script.exists() else False, row["script"]))
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true", help="every lane and its job")
    ap.add_argument("--songs", metavar="LANE", help="publishable songs a lane may render")
    ap.add_argument("--check", action="store_true", help="exit 1 if a lane is broken")
    a = ap.parse_args()

    if a.songs:
        for slug in songs(a.songs):
            print(slug)
        return 0
    if a.check:
        bad = 0
        for name, ok, detail in check():
            if not ok:
                bad += 1
                print(f"FAIL {name}  ({detail})")
        print(f"{len(check()) - bad}/{len(check())} compass checks pass")
        return 1 if bad else 0
    if a.list or True:
        print(f"{'lane':12} {'kind':8} {'audio':10} {'profile':10} rail")
        for lane, row in LANES.items():
            rail = "yes" if row.get("rail") else "-"
            print(f"{lane:12} {row['kind']:8} {row['audio']:10} "
                  f"{str(row['profile']):10} {rail}")
            print(f"{'':12} {row['note']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
