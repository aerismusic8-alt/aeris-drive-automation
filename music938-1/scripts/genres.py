#!/usr/bin/env python3
"""Genre support for an open-ended catalogue.

K, 2026-11-01: "ไม่จำกัดเพลง ทำได้ทุกแนว" — unlimited songs, any genre, and AR
plans the catalogue. The original pack was 20 Thai songs described only by a
`# MOOD:` header, which is enough for one lane and not for many.

`channel/genres.json` is the plan and the single source of a genre's sound: its
Flow Music style prompt, its Thai tagline, its hashtags and how many songs the
catalogue should hold. A new song needs only a lyric file with

    # GENRE: synthpop

in its header. A song without one keeps working off its `# MOOD:` header, so the
first 20 songs are unaffected.

    python3 scripts/genres.py --list        # the plan and what is built
    python3 scripts/genres.py --check       # exit 1 on a genre with no sound
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PLAN = ROOT / "channel" / "genres.json"
LYRICS = ROOT / "lyrics"

# A cover still paints from the mood palette; a genre maps onto the closest one
# so a new genre needs no new artwork code.
PALETTE_FOR = {
    "lukthung": "warm", "morlam": "hopeful", "citypop": "mystic", "synthpop": "hopeful",
    "rnb": "mystic", "lofi": "calm", "rock": "epic", "pop": "hopeful", "indie": "calm",
    "edm": "hopeful", "jazz": "mystic", "acoustic": "warm", "country": "warm",
}


def plan() -> dict:
    return json.loads(PLAN.read_text(encoding="utf-8"))


def genres() -> list[dict]:
    return plan()["genres"]


def by_id() -> dict[str, dict]:
    return {g["id"]: g for g in genres()}


def header(slug: str) -> dict[str, str]:
    """The `# KEY: value` block off a lyric file, lowercased keys."""
    path = LYRICS / f"{slug}.txt"
    out: dict[str, str] = {}
    if not path.exists():
        return out
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"#\s*([A-Za-z]+)\s*:\s*(.+)", line)
        if m:
            out[m.group(1).lower()] = m.group(2).strip()
    return out


def genre_of(slug: str) -> dict | None:
    g = header(slug).get("genre", "").lower()
    return by_id().get(g) if g else None


def style_for(slug: str, mood: str, fallback: str) -> str:
    """The Flow Music style prompt: the genre's, else the caller's mood style."""
    g = genre_of(slug)
    return g["style"] if g else fallback


def tagline_for(slug: str, mood: str, mood_taglines: dict[str, str]) -> str:
    g = genre_of(slug)
    if g:
        return g["tagline"]
    return mood_taglines.get(mood, mood_taglines.get("calm", ""))


def palette_key(slug: str, mood: str) -> str:
    """Which mood palette paints the cover."""
    g = genre_of(slug)
    return PALETTE_FOR.get(g["id"], mood) if g else mood


def hashtags_for(slug: str) -> list[str]:
    g = genre_of(slug)
    return list(g["hashtags"]) if g else []


def counts() -> dict[str, int]:
    """genre id -> songs on disk (a lyric file with that GENRE header)."""
    out = {g["id"]: 0 for g in genres()}
    for path in sorted(LYRICS.glob("*.txt")):
        g = header(path.stem).get("genre", "").lower()
        if g in out:
            out[g] += 1
    return out


def catalogue_size() -> int:
    return sum(g["planned"] for g in genres())


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--check", action="store_true")
    args = ap.parse_args()
    if not (args.list or args.check):
        ap.error("pick --list or --check")

    built = counts()
    total = catalogue_size()
    have = sum(built.values())
    missing = [g for g in genres() if not g.get("style") or not g.get("tagline")]
    print(f"catalogue plan: {len(genres())} genres, {total} songs planned, "
          f"{have} on disk")
    for g in genres():
        n = built.get(g["id"], 0)
        bar = "#" * n + "." * max(g["planned"] - n, 0)
        print(f"  {g['id']:10s} {g['name_th']:8s} {n:2}/{g['planned']:<2} [{bar}]")
    if missing:
        print(f"\n{len(missing)} genre(s) have no style or tagline: "
              f"{', '.join(g['id'] for g in missing)}", file=sys.stderr)
        return 1
    print("\nevery genre has a sound and a tagline")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
