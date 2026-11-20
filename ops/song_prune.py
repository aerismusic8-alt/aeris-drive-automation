#!/usr/bin/env python3
"""Remove superseded takes, so a family of songs keeps only its newest one.

K, 2026-11-20: "เพลงเก่าลบออกให้หมด ใช้เพลงใหม่ล่าสุด" — delete the old songs, use
the newest. The auto-producer appends a template suffix when it wants more songs
(อีกครั้ง / ในฝัน / ยามเช้า / ยามค่ำ), so one song becomes five files that differ
only in their lyrics. Nothing publishes them: they just fill the library, the
catalogue and every listing the channel shows.

A *family* is the slug with its leading number and trailing `-vNN` removed, so
`30-wan-tham-mada-thi-phi-set` and `34-wan-tham-mada-thi-phi-set-v34` are the same
song. The newest take (highest number) is kept and every older one is deleted
with all of its derived media: song, karaoke mix, karaoke video, cover, clipmeta,
thumb, Short, MV and the render work files.

Deletion is K's standing rule (2026-10-24: "อันไหนซ้ำ อันไหนไม่มีคุณภาพลบออกจาก
ช่อง ... ไม่ต้องเก็บ"), and it is recoverable: every master also sits on the
`media-938` release, and the lyric text is tracked in git.

    python3 ops/song_prune.py              # dry run: print the plan
    python3 ops/song_prune.py --apply      # delete
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
BASE = ROOT / "music938-1"
SONGS = BASE / "library" / "songs"
SCAN_DIRS = [BASE / "library", BASE / "work", BASE / "out"]
QUEUE = BASE / "work" / "crosspost-queue.json"
RELEASE = "media-938"

LEAD = re.compile(r"^\d+-")
VER = re.compile(r"-v\d+$")


def family(slug: str) -> str:
    return VER.sub("", LEAD.sub("", slug))


def number(slug: str) -> int:
    m = re.match(r"^(\d+)-", slug)
    return int(m.group(1)) if m else 0


def takes() -> dict[str, list[str]]:
    fams: dict[str, list[str]] = {}
    for p in sorted(SONGS.glob("song-*.mp3")):
        slug = p.stem[len("song-"):]
        fams.setdefault(family(slug), []).append(slug)
    return fams


def plan() -> tuple[list[str], list[str]]:
    """(keep, prune) slugs. A family with one take is always kept."""
    keep: list[str] = []
    prune: list[str] = []
    for slugs in takes().values():
        ordered = sorted(slugs, key=number)
        keep.append(ordered[-1])
        prune.extend(ordered[:-1])
    return sorted(keep), sorted(prune)


def files_for(slug: str) -> list[Path]:
    """Every file whose name carries this slug: the master and all its media."""
    out: list[Path] = []
    for d in SCAN_DIRS:
        if not d.exists():
            continue
        for p in d.rglob(f"*{slug}*"):
            if p.is_file():
                out.append(p)
    return sorted(out)


def _release_ids() -> dict[str, int]:
    """name -> asset id on the media release, so a deleted song stops coming back.

    Deleting only the local file is not enough: `pull_media` restores every asset
    on the release, so a fresh pod would pull the pruned takes straight back.
    """
    sys.path.insert(0, str(BASE / "scripts"))
    import publish_media  # noqa: PLC0415

    tok = publish_media.token()
    rid = publish_media.release_id(RELEASE, tok)
    ids: dict[str, int] = {}
    page = 1
    while True:
        st, assets = publish_media.api(
            f"/repos/{publish_media.REPO}/releases/{rid}/assets"
            f"?per_page=100&page={page}", tok)
        if st != 200 or not assets:
            break
        for a in assets:
            ids[a["name"]] = a["id"]
        if len(assets) < 100:
            break
        page += 1
    return ids


def _release_delete(names: list[str]) -> int:
    sys.path.insert(0, str(BASE / "scripts"))
    import publish_media  # noqa: PLC0415

    tok = publish_media.token()
    ids = _release_ids()
    gone = 0
    for n in names:
        if n in ids:
            st, _ = publish_media.api(
                f"/repos/{publish_media.REPO}/releases/assets/{ids[n]}", tok,
                method="DELETE")
            if st in (204, 200):
                gone += 1
                print(f"  release: deleted {n}")
    return gone


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--apply", action="store_true", help="delete (default: dry run)")
    ap.add_argument("--release", action="store_true",
                    help="also delete the takes from the media release, so a fresh "
                         "pod does not pull them back")
    args = ap.parse_args()

    keep, prune = plan()
    if not prune:
        print(f"{len(keep)} songs, no superseded takes — nothing to do")
        return 0

    victims: list[Path] = []
    for slug in prune:
        files = files_for(slug)
        print(f"prune {slug}  ({len(files)} file(s))")
        for f in files:
            print(f"    {f.relative_to(ROOT)}  {f.stat().st_size / 1e6:.1f} MB")
        victims.extend(files)

    total = sum(f.stat().st_size for f in victims)
    print(f"\nkeep {len(keep)} newest: {', '.join(keep)}")
    print(f"delete {len(prune)} superseded take(s), {len(victims)} file(s), "
          f"{total / 1e6:.0f} MB")

    if not args.apply:
        print("\ndry run — pass --apply to delete")
        return 0

    for f in victims:
        f.unlink(missing_ok=True)
    # A queued clip for a deleted song would fail at post time, so drop it. The
    # crosspost *state* is history of what already went out and is left alone.
    if QUEUE.exists():
        rows = json.loads(QUEUE.read_text(encoding="utf-8"))
        gone = [r for r in rows if not any(s in json.dumps(r, ensure_ascii=False)
                                           for s in prune)]
        if len(gone) != len(rows):
            QUEUE.write_text(json.dumps(gone, ensure_ascii=False, indent=1),
                             encoding="utf-8")
            print(f"queue: dropped {len(rows) - len(gone)} entr(ies) for deleted songs")
    print(f"deleted {len(victims)} file(s), {total / 1e6:.0f} MB freed")

    if args.release:
        names = [f.name for f in victims if f.parent.name in
                 ("songs", "karaoke", "covers", "musicvideo", "shorts", "thumbs")]
        n = _release_delete(names)
        print(f"release: {n} asset(s) deleted")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
