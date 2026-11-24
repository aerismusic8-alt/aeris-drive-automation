#!/usr/bin/env python3
"""No repeats: picture, sound, lyric — judged by content, never by name.

K, 2026-11-21: "ภาพ เสียง เนื้อร้องห้ามซ้ำกันเด็ดขาด ทุก mv" and
"จะเปลี่ยนชื่อมาลอกก็ไม่ได้ ห้ามเด็ดขาด". A file name proves nothing, so every
check here hashes or compares the bytes: two masters with different names but
the same audio are one master, and two lyric sheets with different titles but
the same lines are one lyric.

    python3 ops/no_repeat.py --report          # what the library can still give
    python3 ops/no_repeat.py --check <slug>    # refuse a repeat before a render
"""
from __future__ import annotations

import argparse
import hashlib
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MUSIC = ROOT / "music938-1"
SONGS = MUSIC / "library" / "songs"
LYRICS = MUSIC / "lyrics"
LEDGER = MUSIC / "work" / "no-repeat.json"
PICTURE_LEDGER = MUSIC / "work" / "picture-ledger.json"

SIMILAR = 0.90      # lyric sheets at or above this are the same lyric
SHINGLE = 4         # characters per shingle for the lyric comparison


def sha(path: Path, algo: str = "sha256") -> str:
    h = hashlib.new(algo)
    with path.open("rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def normalise(text: str) -> str:
    """Letters only: no spaces, no punctuation, no difference from a rename."""
    return re.sub(r"[^0-9a-z\u0e00-\u0e7f]+", "", text.lower())


def shingles(text: str, n: int = SHINGLE) -> set[str]:
    t = normalise(text)
    if len(t) <= n:
        return {t} if t else set()
    return {t[i:i + n] for i in range(len(t) - n + 1)}


def similarity(a: str, b: str) -> float:
    sa, sb = shingles(a), shingles(b)
    if not sa or not sb:
        return 0.0
    return len(sa & sb) / len(sa | sb)


def lyric_text(slug: str) -> str:
    p = LYRICS / f"{slug}.txt"
    return p.read_text(encoding="utf-8") if p.exists() else ""


def load(path: Path, default: dict) -> dict:
    if not path.exists():
        return default
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except ValueError:
        return default


def save(path: Path, data: dict) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, ensure_ascii=False, indent=1, sort_keys=True),
                    encoding="utf-8")


def picture_history() -> dict[str, set[str]]:
    """mv -> set of picture content hashes it used."""
    led = load(PICTURE_LEDGER, {"mvs": {}})
    out: dict[str, set[str]] = {}
    for mv, entry in led.get("mvs", {}).items():
        out[mv] = {p.get("sha1") for p in entry.get("pictures", []) if p.get("sha1")}
    return out


def spent(slug: str) -> set[str]:
    """Picture content hashes already used by some other MV."""
    history = picture_history()
    return set().union(*[v for k, v in history.items() if k != f"mv-{slug}"]) \
        if history else set()


def fresh_pictures(paths: list[Path], slug: str) -> tuple[list[Path], list[Path]]:
    """Split into pictures no other MV has used, and the ones already spent."""
    history = picture_history()
    # A re-render of the same MV may reuse its own pictures; only another MV's
    # pictures are spent.
    spent = set().union(*[v for k, v in history.items() if k != f"mv-{slug}"]) \
        if history else set()
    seen: set[str] = set()
    fresh, reused = [], []
    for p in paths:
        try:
            h = sha(p, "sha1")
        except OSError:
            continue
        if h in seen:
            continue
        seen.add(h)
        (reused if h in spent else fresh).append(p)
    return fresh, reused


def check(slug: str, pictures: list[Path] | None = None) -> list[str]:
    """Every way this MV would repeat an earlier one. Empty list = clean."""
    bad: list[str] = []
    led = load(LEDGER, {"mvs": {}})
    song = SONGS / f"song-{slug}.mp3"
    text = lyric_text(slug)

    audio = sha(song) if song.exists() else ""
    lyric = hashlib.sha256(normalise(text).encode()).hexdigest() if text else ""

    # Compare against every asset on disk as well as every stamped MV: a lyric
    # that was written but never shipped still may not be reused under a new title.
    for other in sorted(LYRICS.glob("*.txt")):
        if other.stem == slug:
            continue
        s_ = similarity(text, other.read_text(encoding="utf-8"))
        if s_ >= SIMILAR:
            bad.append(f"lyric: {s_:.0%} the same words as {other.stem}")
    for other in sorted(SONGS.glob("song-*.mp3")):
        if other.stem == f"song-{slug}":
            continue
        if audio and sha(other) == audio:
            bad.append(f"audio: the same master as {other.stem} (identical bytes)")

    for other, entry in led.get("mvs", {}).items():
        if other == slug:
            continue
        if audio and entry.get("audio") == audio:
            bad.append(f"audio: the same master as {other} (identical bytes)")
        if lyric and entry.get("lyric") == lyric:
            bad.append(f"lyric: the same lines as {other} (identical after normalising)")
        other_text = entry.get("lyric_text", "")
        if text and other_text:
            s = similarity(text, other_text)
            if s >= SIMILAR:
                bad.append(f"lyric: {s:.0%} the same words as {other}")

    if pictures:
        history = picture_history()
        spent = {h: mv for mv, hs in history.items() if mv != f"mv-{slug}" for h in hs}
        for p in pictures:
            try:
                h = sha(p, "sha1")
            except OSError:
                continue
            if h in spent:
                bad.append(f"picture: {p.name} is already in {spent[h]}")
                break
    return sorted(set(bad))


def stamp(slug: str, pictures: list[Path] | None = None) -> None:
    led = load(LEDGER, {"version": 1, "mvs": {}})
    song = SONGS / f"song-{slug}.mp3"
    text = lyric_text(slug)
    led.setdefault("mvs", {})[slug] = {
        "audio": sha(song) if song.exists() else "",
        "lyric": hashlib.sha256(normalise(text).encode()).hexdigest() if text else "",
        "lyric_text": text[:4000],
        "pictures": [sha(p, "sha1") for p in (pictures or []) if p.exists()],
    }
    save(LEDGER, led)


def report() -> int:
    lib = Path("/workspace/ax-tools/media-library/pictures")
    pics = sorted([p for p in lib.rglob("*.jpg")] + [p for p in lib.rglob("*.png")])
    fresh, reused = fresh_pictures(pics, "")
    songs = sorted(SONGS.glob("song-*.mp3"))
    audio: dict[str, list[str]] = {}
    for s in songs:
        audio.setdefault(sha(s), []).append(s.name)
    dup_audio = {k: v for k, v in audio.items() if len(v) > 1}

    lyr = sorted(LYRICS.glob("*.txt"))
    texts = {p.stem: p.read_text(encoding="utf-8") for p in lyr}
    near = []
    names = sorted(texts)
    for i, a in enumerate(names):
        for b in names[i + 1:]:
            s = similarity(texts[a], texts[b])
            if s >= SIMILAR:
                near.append((round(s, 2), a, b))

    print(f"pictures  : {len(pics)} files, {len(fresh) + len(reused)} distinct, "
          f"{len(reused)} already used, {len(fresh)} unused")
    print(f"songs     : {len(songs)} masters, {len(audio)} distinct audio, "
          f"{len(dup_audio)} duplicated")
    for k, v in dup_audio.items():
        print(f"            {k[:12]}… = {', '.join(v)}")
    print(f"lyrics    : {len(lyr)} files, {len(near)} pairs at >= {SIMILAR:.0%} similarity")
    for s, a, b in near[:10]:
        print(f"            {s:.0%}  {a}  ==  {b}")
    led = load(LEDGER, {"mvs": {}})
    print(f"no-repeat : {len(led.get('mvs', {}))} MV(s) stamped in {LEDGER.relative_to(ROOT)}")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true")
    ap.add_argument("--check")
    ap.add_argument("--seed", action="store_true",
                    help="stamp audio+lyrics for MVs already in the picture ledger")
    args = ap.parse_args()
    if args.seed:
        led = load(PICTURE_LEDGER, {"mvs": {}})
        n = 0
        for mv in led.get("mvs", {}):
            slug = mv[3:] if mv.startswith("mv-") else mv
            if (SONGS / f"song-{slug}.mp3").exists():
                stamp(slug)
                n += 1
        print(f"seeded {n} MV(s)")
        return 0
    if args.report or not args.check:
        return report()
    bad = check(args.check)
    for line in bad:
        print(f"REPEAT {line}")
    print("clean" if not bad else f"{len(bad)} repeat(s)")
    return 1 if bad else 0


if __name__ == "__main__":
    sys.exit(main())
