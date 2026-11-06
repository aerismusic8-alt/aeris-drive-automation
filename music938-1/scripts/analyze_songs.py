#!/usr/bin/env python3
"""Measure the songbook so a rewrite is decided by numbers, not by taste.

K (2026-11-06): "เอาผลงานที่รออัพทั้งหมดให้ทีมวิเคราะห์ ... ตั้งแต่บทร้อง เนื้อร้อง
ทำนอง จังหวะ ท่อนฮุก ติดหู ท่อนริพ จำง่าย อันไหนไม่ดีรื้อทำใหม่ทั้งโครงเลย".
The AI panel gives the judgement; this script gives the evidence it argues over,
so a "keep" or "rebuild" verdict can be checked against something repeatable.

What is measured, and why each one is the thing that decides a verdict:

  hook_repeat    How many times the chorus's opening line appears in the song.
                 A hook that appears once is not a hook; Thai pop lives on the
                 line a stranger can hum after one listen.
  hook_share     The hook line's words as a fraction of all words. Too low and
                 the song has no anchor; the chorus is 3 of 6 sections, so the
                 natural band is roughly 0.15-0.35.
  distinct       Unique lines / total lines. A low number means the verses are
                 copies of each other, which is the "8 copies of one song"
                 problem K flagged, measured.
  syl_std        Standard deviation of syllables per line. Flow sings what it is
                 given; a high spread is where the vocal drifts off the beat.
  rhyme          Fraction of adjacent line-pairs whose final syllable shares a
                 vowel sound. Thai rhyme is a sound match, so this strips tone
                 marks and compares the vowel of the last syllable.
  chorus_same    Whether every chorus block is word-identical. Identical
                 choruses are correct; a *differing* chorus with no bridge
                 change is usually a drafting accident.

    python3 scripts/analyze_songs.py                 # JSON + markdown report
    python3 scripts/analyze_songs.py --json          # JSON only
"""
from __future__ import annotations

import argparse
import glob
import json
import re
import statistics
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

from pythainlp.tokenize import syllable_tokenize  # noqa: E402

LYRICS = ROOT / "lyrics"
OUT_JSON = ROOT / "work" / "song-analysis.json"
OUT_MD = ROOT / "work" / "song-analysis.md"

# Tone marks, the karan (silencer), and the repeat mark carry no vowel sound, so
# they must not decide whether two lines rhyme.
_STRIP = re.compile(r"[\u0e48-\u0e4b\u0e4c\u0e47\u0e46]")
_THAI = re.compile(r"[ก-๙]")

# The vowel of a syllable, as the letter or mark that carries the sound. Ordered
# longest-first so "เ_าะ" is read before "เ_า" and "ะ".
_VOWELS = [
    "เ_าะ", "โ_ะ", "เ_อ", "เ_า", "เ_ี", "เ_ื", "เ_็", "ั_ว", "็_ว", "ั_ย",
    "ไ_", "ใ_", "เ_", "โ_", "แ_", "ำ", "ะ", "า", "ิ", "ี", "ึ", "ื", "ุ", "ู",
    "อ", "ย", "ว", "ร", "น", "ง", "ม", "ก", "ด", "บ", "่",
]


def syllables(line: str) -> list[str]:
    return [s for s in syllable_tokenize(line) if _THAI.search(s)]


def rhyme_key(line: str) -> str:
    """A coarse 'does this sound end the same' key for the last syllable."""
    syl = syllables(line)
    if not syl:
        return ""
    last = _STRIP.sub("", syl[-1])
    # Reduce to the vowel sound plus the final consonant, ignoring the onset.
    for v in _VOWELS:
        if v.replace("_", "") in last:
            return v.replace("_", "")
    return last[-1:]


def rhyme_rate(lines: list[str]) -> float:
    keys = [rhyme_key(ln) for ln in lines]
    pairs = [(keys[i], keys[i + 1]) for i in range(len(keys) - 1)]
    pairs = [p for p in pairs if p[0] and p[1]]
    if not pairs:
        return 0.0
    return sum(1 for a, b in pairs if a == b) / len(pairs)


def parse(path: Path) -> dict:
    text = path.read_text(encoding="utf-8")
    meta: dict[str, str] = {}
    for k, v in re.findall(r"^#\s*([A-Z_]+):\s*(.+)$", text, re.M):
        meta[k.strip()] = v.strip()
    sections: list[tuple[str, list[str]]] = []
    for raw in text.splitlines():
        s = raw.strip()
        m = re.match(r"\[(verse|chorus|bridge|intro|outro|pre[- ]?chorus)\]", s, re.I)
        if m:
            sections.append((m.group(1).lower(), []))
        elif s and not s.startswith("#") and sections:
            sections[-1][1].append(s)
    return {"slug": path.stem, "meta": meta, "sections": sections}


def analyse(song: dict) -> dict:
    sections = song["sections"]
    meta = song["meta"]
    all_lines = [ln for _, lines in sections for ln in lines]
    choruses = [lines for sec, lines in sections if sec == "chorus"]
    hook = choruses[0][0] if choruses and choruses[0] else ""
    hook_repeat = sum(1 for ln in all_lines if ln == hook)
    words = re.findall(r"[ก-๙]+", " ".join(all_lines))
    # The hook is the whole chorus, not one line: that is the block a listener
    # repeats. Its share of the lyric says whether the song has a centre.
    chorus_words = len(re.findall(r"[ก-๙]+", " ".join(hook and choruses[0] or [])))
    # How often the hook line recurs *inside* its own chorus. A chorus that states
    # its hook once and moves on is the weakest shape; twice or more is the shape
    # that gets stuck in the head.
    hook_in_chorus = sum(1 for ln in (choruses[0] if choruses else []) if ln == hook)
    syl_counts = [len(syllables(ln)) for ln in all_lines] or [0]
    chorus_same = bool(choruses) and all(c == choruses[0] for c in choruses)
    rhyme_by_section = {sec: round(rhyme_rate(lines), 2)
                        for sec, lines in sections if len(lines) > 1}
    flags: list[str] = []
    if hook_repeat < 3:
        flags.append("hook appears <3 times")
    if words and chorus_words / len(words) < 0.25:
        flags.append("chorus is a small share of the lyric")
    if hook_in_chorus < 2:
        flags.append("hook stated only once per chorus")
    distinct = len(set(all_lines)) / len(all_lines) if all_lines else 0
    if distinct < 0.55:
        flags.append("too few distinct lines (verses repeat)")
    if statistics.pstdev(syl_counts) > 1.6:
        flags.append("uneven line lengths (vocal may drift)")
    if not meta.get("GENRE"):
        flags.append("no genre tag (falls back to one style)")
    if len(choruses) >= 2 and not chorus_same:
        flags.append("choruses differ without a reason")
    return {
        "slug": song["slug"],
        "title": meta.get("TITLE", song["slug"]),
        "genre": meta.get("GENRE", "(none)"),
        "mood": meta.get("MOOD", ""),
        "tempo": int(meta["TEMPO"]) if meta.get("TEMPO", "").isdigit() else None,
        "key": meta.get("KEY", ""),
        "voice": meta.get("VOICE", ""),
        "structure": [sec for sec, _ in sections],
        "sections": len(sections),
        "lines": len(all_lines),
        "hook": hook,
        "hook_repeat": hook_repeat,
        "hook_in_chorus": hook_in_chorus,
        "chorus_share": round(chorus_words / len(words), 3) if words else 0,
        "distinct": round(distinct, 3),
        "syl_mean": round(statistics.mean(syl_counts), 2),
        "syl_std": round(statistics.pstdev(syl_counts), 2),
        "rhyme": rhyme_by_section,
        "rhyme_mean": round(statistics.mean(rhyme_by_section.values()), 2)
        if rhyme_by_section else 0,
        "chorus_identical": chorus_same,
        "flags": flags,
    }


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--json", action="store_true", help="print JSON only")
    args = ap.parse_args()

    rows = [analyse(parse(Path(p))) for p in sorted(glob.glob(str(LYRICS / "*.txt")))]
    OUT_JSON.parent.mkdir(parents=True, exist_ok=True)
    OUT_JSON.write_text(json.dumps(rows, ensure_ascii=False, indent=2), encoding="utf-8")

    if args.json:
        print(json.dumps(rows, ensure_ascii=False, indent=2))
        return 0

    genres: dict[str, int] = {}
    tempos: list[int] = []
    voices: dict[str, int] = {}
    for r in rows:
        genres[r["genre"]] = genres.get(r["genre"], 0) + 1
        if r["tempo"]:
            tempos.append(r["tempo"])
        voices[r["voice"]] = voices.get(r["voice"], 0) + 1

    lines = [
        "# Songbook analysis",
        "",
        f"{len(rows)} songs. Genres: {genres}. Voices: {voices}. "
        f"Tempo {min(tempos)}-{max(tempos)} (mean {round(statistics.mean(tempos))}).",
        "",
        "| slug | genre | tempo | voice | hook x | in-chorus | chorus% | distinct | syl | rhyme | flags |",
        "| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |",
    ]
    for r in rows:
        lines.append(
            f"| {r['slug']} | {r['genre']} | {r['tempo']} | {r['voice']} | "
            f"{r['hook_repeat']} | {r['hook_in_chorus']} | {r['chorus_share']:.2f} | "
            f"{r['distinct']:.2f} | {r['syl_mean']:.1f}±{r['syl_std']:.1f} | "
            f"{r['rhyme_mean']:.2f} | {'; '.join(r['flags'])} |")
    flagged = [r for r in rows if r["flags"]]
    lines += ["", f"**{len(flagged)}/{len(rows)} songs carry at least one flag.**", ""]
    OUT_MD.write_text("\n".join(lines), encoding="utf-8")
    print("\n".join(lines))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
