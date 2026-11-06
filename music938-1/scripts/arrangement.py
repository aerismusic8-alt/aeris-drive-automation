#!/usr/bin/env python3
"""Two rules K set for the reworked catalogue (2026-11-06):

  "ดนตรีห้ามซ้ำกัน"          — no two songs may share the same music
  "ใช้เพนทาโทนิคด้วยนะ"      — every melody must be pentatonic

Both are enforced here rather than hoped for, because the measured problem was
exactly their absence: 20 of 22 songs carried no genre tag, so they all fell
back to one Flow style prompt and came out as the same ballad.

The arrangement is the thing that must not repeat. Two songs can share a genre
and still be different music if the *arrangement* differs — a different lead
instrument, a different groove, a different mix character. So each song is
assigned one signature from `channel/arrangements.json`, deterministically by its
position in the sorted catalogue, and `--check` fails if any signature is reused.

The pentatonic scale is chosen by mood (minor for the dark moods, major for the
bright ones) with a genre override, and appended to the Flow style prompt.

    python3 scripts/arrangement.py --check        # exit 1 if any music repeats
    python3 scripts/arrangement.py --for <slug>   # the suffix one song would get
"""
from __future__ import annotations

import argparse
import glob
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLAN = ROOT / "channel" / "arrangements.json"
LYRICS = ROOT / "lyrics"

# Mood -> scale. A minor pentatonic carries the sad/dark moods; a major
# pentatonic carries the bright ones. K asked for pentatonic melody, not for one
# particular pentatonic, so the mood picks which.
SCALE_BY_MOOD = {
    "sad": "minor", "mystic": "minor", "epic": "minor",
    "calm": "major", "warm": "major", "hopeful": "major", "fun": "major",
}
# A genre can override the mood when its tradition wants the other scale.
SCALE_BY_GENRE = {
    "rock": "minor", "rnb": "minor", "lofi": "minor", "jazz": "minor",
    "lukthung": "major", "morlam": "major", "country": "major",
    "acoustic": "major", "indie": "major", "citypop": "major",
    "synthpop": "major", "edm": "major",
}
PENTATONIC = {
    "major": ("major pentatonic (scale degrees 1-2-3-5-6), simple singable "
              "melody built only from those five notes, no chromatic passing "
              "tones, easy to hum after one listen"),
    "minor": ("minor pentatonic (scale degrees 1-b3-4-5-b7), simple singable "
              "melody built only from those five notes, no chromatic passing "
              "tones, memorable descending hook"),
}


def plan() -> dict:
    return json.loads(PLAN.read_text(encoding="utf-8"))


def signatures() -> list[dict]:
    return plan()["arrangements"]


def header(slug: str) -> dict[str, str]:
    path = LYRICS / f"{slug}.txt"
    out: dict[str, str] = {}
    if not path.exists():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"#\s*([A-Za-z]+)\s*:\s*(.+)", line)
        if m:
            out[m.group(1).lower()] = m.group(2).strip()
    return out


def slugs() -> list[str]:
    return sorted(Path(p).stem for p in glob.glob(str(LYRICS / "*.txt")))


_ASSIGN_CACHE: dict[tuple, dict[str, dict]] = {}


def assign(catalogue: list[str] | None = None) -> dict[str, dict]:
    """slug -> its arrangement, unique across the whole catalogue.

    Two passes, because a single greedy pass lets a header-less song (the five
    already-released ones have no genre) claim a signature out of a genre's pool
    and starve that genre. Tagged songs are placed first, each inside its own
    genre pool so the sound stays coherent (a rock song never gets a khaen loop);
    header-less songs then take whatever is left, so they are still all distinct.
    """
    cat = tuple(catalogue) if catalogue is not None else tuple(slugs())
    if cat in _ASSIGN_CACHE:
        return _ASSIGN_CACHE[cat]
    all_sigs = signatures()
    used: set[str] = set()
    out: dict[str, dict] = {}

    def place(slug: str, pool: list[dict]) -> None:
        pick = next((a for a in pool if a["id"] not in used), None)
        if pick is None:
            pick = next((a for a in all_sigs if a["id"] not in used), pool[0])
        used.add(pick["id"])
        out[slug] = pick

    tagged = [s for s in cat if (header(s).get("genre") or "").strip()]
    plain = [s for s in cat if s not in tagged]
    for slug in tagged:
        genre = header(slug).get("genre", "").lower()
        place(slug, [a for a in all_sigs if a.get("genre") == genre] or all_sigs)
    for slug in plain:
        place(slug, all_sigs)
    _ASSIGN_CACHE[cat] = out
    return out


def signature_for(slug: str, catalogue: list[str] | None = None) -> dict:
    """The arrangement one song gets.

    A `# ARRANGEMENT: <id>` header pins a song; otherwise it comes from the
    catalogue-wide `assign()` so no two songs share music.
    """
    by_id = {a["id"]: a for a in signatures()}
    pinned = header(slug).get("arrangement", "")
    if pinned and pinned in by_id:
        return by_id[pinned]
    return assign(catalogue)[slug]


def scale_for(slug: str, meta: dict | None = None) -> str:
    meta = meta or header(slug)
    genre = (meta.get("genre") or "").lower()
    mood = (meta.get("mood") or "").lower()
    return SCALE_BY_GENRE.get(genre) or SCALE_BY_MOOD.get(mood, "major")


def suffix(slug: str, meta: dict | None = None) -> str:
    """What is appended to the Flow style prompt: scale + this song's arrangement."""
    meta = meta or header(slug)
    a = signature_for(slug)
    parts = [PENTATONIC[scale_for(slug, meta)]]
    if a.get("instruments"):
        parts.append(a["instruments"])
    if a.get("groove"):
        parts.append(a["groove"])
    if a.get("mix"):
        parts.append(a["mix"])
    return ", ".join(parts)


def check() -> int:
    cat = slugs()
    pool = signatures()
    used: dict[str, list[str]] = {}
    for s in cat:
        used.setdefault(signature_for(s, cat)["id"], []).append(s)
    dupes = {k: v for k, v in used.items() if len(v) > 1}
    print(f"{len(cat)} songs, {len(pool)} arrangements in the pool")
    for s in cat:
        a = signature_for(s, cat)
        print(f"  {s:34s} -> {a['id']:14s} {scale_for(s):5s} pentatonic")
    if dupes:
        print(f"\n{len(dupes)} arrangement(s) reused — 'ดนตรีห้ามซ้ำ' violated:",
              file=sys.stderr)
        for k, v in dupes.items():
            print(f"  {k}: {', '.join(v)}", file=sys.stderr)
        return 1
    print(f"\nevery song has its own arrangement ({len(used)} distinct)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true")
    ap.add_argument("--for", dest="slug")
    args = ap.parse_args()
    if args.slug:
        print(suffix(args.slug))
        return 0
    if args.check:
        return check()
    ap.error("pick --check or --for <slug>")


if __name__ == "__main__":
    raise SystemExit(main())
