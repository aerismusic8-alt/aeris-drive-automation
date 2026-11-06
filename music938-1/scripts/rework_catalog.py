#!/usr/bin/env python3
"""Rework the songbook so the catalogue stops sounding like one song.

The measured problem (2026-11-06): 20 of 22 songs had no `# GENRE:` header, so
every one fell back to the same "เพื่อชีวิต" style; 21 of 22 used a female voice;
and tempo clustered at 64-96 BPM. K heard it as "เพลงซ้ำกัน" and the advisor panel
agreed the cause is one production template used across the whole catalogue.

This rewrites only the *headers* of the lyric files — `# GENRE:`, `# TEMPO:` and
`# VOICE:` — leaving the lyrics themselves untouched. The genre drives the Flow
Music style, the tempo spreads the catalogue, and the voice alternates. The
arrangement is derived separately from the genre (`scripts/arrangement.py`), so
two songs in the same genre still get different music.

    python3 scripts/rework_catalog.py --dry-run     # show the plan
    python3 scripts/rework_catalog.py               # apply it
"""
from __future__ import annotations

import argparse
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LYRICS = ROOT / "lyrics"

# slug -> (genre, tempo, voice). Genres rotate so no two neighbours share one and
# no genre holds more songs than the arrangement pool has signatures for. Tempos
# spread the old 64-96 cluster across 84-160. Voices alternate.
PLAN: dict[str, tuple[str, int, str]] = {
    "01-khon-di-thi-chak-pai": ("indie", 88, "female"),
    "02-rak-thi-mai-mi-wan-chop": ("lukthung", 104, "female"),
    "03-khit-thueng-thoe-thuk-khuen": ("indie", 92, "male"),
    "04-saeng-chao-wan-mai": ("pop", 116, "female"),
    "05-fon-tok-nai-chai": ("pop", 100, "male"),
    "06-doen-khon-diao": ("indie", 96, "male"),
    "07-huachai-si-thao": ("rock", 138, "male"),
    "08-klap-ban-rao": ("lukthung", 120, "female"),
    "09-phleng-khong-khon-nueai": ("pop", 124, "male"),
    "10-dok-mai-rim-thang": ("rock", 116, "male"),
    "11-sanya-chak-chai": ("indie", 84, "female"),
    "12-khuen-thi-mai-mi-dao": ("pop", 108, "male"),
    "13-rak-thi-chak-pai": ("lukthung", 132, "female"),
    "14-phleng-klom-khong-mae": ("indie", 76, "female"),
    "15-thanon-sai-kao": ("rock", 152, "male"),
    "16-khwam-fan-thi-yang-mai-tai": ("lukthung", 144, "female"),
    "17-wan-thi-fa-pen-chai": ("pop", 128, "male"),
    "18-khon-thi-chan-khoei-rak": ("indie", 80, "male"),
    "19-lom-nao-kap-khwam-khit-thueng": ("lukthung", 136, "female"),
    "20-khop-khun-thi-yang-hai-chai": ("rock", 130, "male"),
    "21-sao-na-khoi-phi": ("lukthung", 112, "female"),
    "24-yut-mai-yom": ("rock", 160, "male"),
}

ORDER = ["title", "subtitle", "genre", "key", "mood", "tempo", "voice"]

# Already published. Their audio cannot be re-rendered without re-uploading, so a
# new genre tag would only make the metadata disagree with the sound. K ordered
# the *unreleased* 17 reworked; these five are left exactly as they were.
RELEASED: set[str] = {
    "01-khon-di-thi-chak-pai", "02-rak-thi-mai-mi-wan-chop",
    "03-khit-thueng-thoe-thuk-khuen", "04-saeng-chao-wan-mai",
    "05-fon-tok-nai-chai",
}

# The headers the five released songs had before this rework, restored verbatim.
_ORIGINAL: dict[str, tuple[str | None, int, str]] = {
    "01-khon-di-thi-chak-pai": (None, 68, "female"),
    "02-rak-thi-mai-mi-wan-chop": (None, 76, "female"),
    "03-khit-thueng-thoe-thuk-khuen": (None, 66, "female"),
    "04-saeng-chao-wan-mai": (None, 82, "female"),
    "05-fon-tok-nai-chai": (None, 72, "female"),
}


def rewrite(text: str, genre: str | None, tempo: int, voice: str) -> str:
    """Set the headers, keeping every other line and the order stable.

    `genre=None` removes the `# GENRE:` line, which is how a released song is
    restored to its original headerless form.
    """
    have: dict[str, str] = {}
    body: list[str] = []
    for line in text.splitlines():
        m = re.match(r"#\s*([A-Za-z]+)\s*:\s*(.*)", line)
        if m:
            have[m.group(1).lower()] = m.group(2).strip()
        else:
            body.append(line)
    if genre:
        have["genre"] = genre
    else:
        have.pop("genre", None)
    have["tempo"] = str(tempo)
    have["voice"] = voice
    head = [f"# {k.upper()}: {have[k]}" for k in ORDER if k in have]
    for k in sorted(have):
        if k not in ORDER:
            head.append(f"# {k.upper()}: {have[k]}")
    return "\n".join(head) + "\n" + "\n".join(body).lstrip("\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    changed = 0
    for slug, (genre, tempo, voice) in sorted(PLAN.items()):
        path = LYRICS / f"{slug}.txt"
        if not path.exists():
            print(f"  ! {slug}: no lyric file")
            continue
        text = path.read_text(encoding="utf-8")
        if slug in RELEASED:
            # Restore the original header so a rework never rewrites a live song.
            og, ot, ov = _ORIGINAL[slug]
            new = rewrite(text, og, ot, ov)
            print(f"  = {slug:34s} released — left as it was")
        else:
            new = rewrite(text, genre, tempo, voice)
        old_genre = (re.search(r"# GENRE: (\w+)", text) or [None, "-"])[1] \
            if re.search(r"# GENRE: (\w+)", text) else "-"
        old_tempo = (re.search(r"# TEMPO: (\d+)", text) or [None, "-"])[1] \
            if re.search(r"# TEMPO: (\d+)", text) else "-"
        old_voice = (re.search(r"# VOICE: (\w+)", text) or [None, "-"])[1] \
            if re.search(r"# VOICE: (\w+)", text) else "-"
        if slug not in RELEASED:
            mark = "=" if (old_genre, old_tempo, old_voice) == (genre, str(tempo), voice) else "*"
            print(f"  {mark} {slug:34s} {old_genre:9s}/{old_tempo:>3s}/{old_voice:6s} "
                  f"-> {genre:9s}/{tempo:>3d}/{voice}")
        if not args.dry_run and new != text:
            path.write_text(new, encoding="utf-8")
            changed += 1

    from collections import Counter
    pending = {s: v for s, v in PLAN.items() if s not in RELEASED}
    print(f"\ngenres: {dict(Counter(g for g, _, _ in pending.values()))}")
    print(f"voices: {dict(Counter(v for _, _, v in pending.values()))}")
    tempos = sorted(t for _, t, _ in pending.values())
    print(f"tempo: {tempos[0]}-{tempos[-1]} BPM, {len(set(tempos))} distinct")
    if not args.dry_run:
        print(f"\nrewrote {changed} lyric file(s)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
