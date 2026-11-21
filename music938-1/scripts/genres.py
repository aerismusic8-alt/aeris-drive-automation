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
    "symphonic": "epic", "hiphop": "epic", "rap": "epic", "alternative": "hopeful",
}

# K (2026-11-20) names the second lane "แดนซ์" (dance), not EDM. The id stays
# `edm` because a lyric file's `# GENRE:` header, the arrangement signatures and
# the image prompts all key off it — renaming the id would orphan every existing
# song. This is the display name and the accepted alias, nothing more.
ALIASES = {"dance": "edm", "แดนซ์": "edm"}


def plan() -> dict:
    return json.loads(PLAN.read_text(encoding="utf-8"))


def genres() -> list[dict]:
    return plan()["genres"]


def by_id() -> dict[str, dict]:
    return {g["id"]: g for g in genres()}


def canonical(gid: str) -> str:
    """Resolve a genre name to its plan id (`dance` -> `edm`)."""
    gid = (gid or "").strip().lower()
    return ALIASES.get(gid, gid)


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
    g = canonical(header(slug).get("genre", ""))
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
        g = canonical(header(path.stem).get("genre", ""))
        if g in out:
            out[g] += 1
    return out


def is_parked(genre: dict) -> bool:
    """A parked genre keeps its style and tagline but takes no new songs.

    K, 2026-11-13 parked lukthung and morlam ("พักแนวลูกทุ่ง เพื่อชีวิต ไว้").
    Its existing songs must still resolve a sound, so it stays in the plan; only
    production and the catalogue total skip it.
    """
    return genre.get("status") == "parked"


def active() -> list[dict]:
    return [g for g in genres() if not is_parked(g)]


def resolve_slug(name: str) -> str | None:
    """Map a file stem to a lyric slug, or None.

    A master is named `music-am-35-fai-thi-yang-mai-dap.mp3` while the lyric file
    is `35-fai-thi-yang-mai-dap.txt`, and a bank clip adds its own prefixes
    (`bank-karaoke-06-doen-khon-diao-...`). Longest suffix match resolves all of
    them without a prefix table that would rot: the key token, the kind and the
    `-v36` variant are all just leading text in front of the slug.

    The slug is not always at the end: a bank clip appends its own theme
    (`bank-song-40-luk-khuen-laeo-pai-v40-bangkok-night.mp4`). A suffix-only
    match returned None for those, and because an unresolvable clip is refused,
    a publishable EDM song was blocked. So the last resort is a whole-token
    match anywhere in the stem, longest slug first.
    """
    stem = Path(name).stem if Path(name).suffix in (".mp3", ".mp4", ".wav", ".m4a") else name
    if (LYRICS / f"{stem}.txt").exists():
        return stem
    slugs = sorted((p.stem for p in LYRICS.glob("*.txt")), key=len, reverse=True)
    for slug in slugs:
        if stem.endswith(f"-{slug}") or stem.endswith(slug):
            return slug
    for slug in slugs:
        if f"-{slug}-" in stem:
            return slug
    return None


def publishable(slug: str) -> tuple[bool, str]:
    """May a clip of this song be published? Returns (ok, why).

    K parked lukthung/morlam on 2026-11-13 and then said "ทำแนวสนุกอย่างเดียว"
    (2026-11-18). `is_parked` only stopped *new production*; nothing stopped an
    already-rendered old song from being uploaded, and on 2026-11-19 two
    เพื่อชีวิต clips went to YouTube and Facebook that way.

    So this is the publishing gate, and it fails closed:

    * a parked genre is refused by name, with K's own word for it;
    * a song with no `# GENRE:` header is refused too, because it predates the
      plan and its genre is unknowable -- the original 20 are all เพื่อชีวิต,
      which is exactly the lane that was parked.

    The 20 original lyric files keep working for playback; they just cannot be
    published as new work on this channel.

    Accepts a lyric slug or a file stem; see `resolve_slug`.
    """
    resolved = resolve_slug(slug)
    if resolved is None:
        return False, f"'{slug}' matches no lyric file — its genre is unknowable"
    slug = resolved
    hdr = header(slug)
    gid = canonical(hdr.get("genre", ""))
    if not gid:
        sub = hdr.get("subtitle", "")
        return False, (f"no # GENRE: header (subtitle: {sub or 'none'}) — "
                       f"a song outside the plan cannot be published")
    g = by_id().get(gid)
    if g is None:
        return False, f"unknown genre '{gid}' (not in channel/genres.json)"
    if is_parked(g):
        return False, f"genre '{gid}' ({g['name_th']}) is parked by K"
    return True, f"genre '{gid}' ({g['name_th']}) is active"


def catalogue_size() -> int:
    return sum(g["planned"] for g in active())


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
    print(f"catalogue plan: {len(active())} active genres, {total} songs planned, "
          f"{have} on disk")
    for g in genres():
        n = built.get(g["id"], 0)
        bar = "#" * n + "." * max(g["planned"] - n, 0)
        tag = "  [parked]" if is_parked(g) else ""
        print(f"  {g['id']:10s} {g['name_th']:8s} {n:2}/{g['planned']:<2} [{bar}]{tag}")
    if missing:
        print(f"\n{len(missing)} genre(s) have no style or tagline: "
              f"{', '.join(g['id'] for g in missing)}", file=sys.stderr)
        return 1
    print("\nevery genre has a sound and a tagline")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
