"""Offline mood music, rendered with real instruments (the sfizz sampler).

This is the no-account fallback for the music library. K (2026-11-09) rejected
the ffmpeg tone-generator version as "fake": the music must come from a program
that makes realistic sound. `soundfont` renders through the sfizz sampler over
recordings of real instruments when its banks are present, and prefers a
pre-rendered real-instrument bed (pulled from the media release) over the
General-MIDI SoundFont otherwise, so a runner never ships the timbre K rejected.
It is still free, offline and deterministic, so the pipeline can run end to end
without a login, and the result is filed in the music manifest with the same
shape as a generated song.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import library  # noqa: E402

REPO = Path(__file__).resolve().parent.parent.parent

# Mood presets. `bpm` is the tempo the bed is rendered at; the scale is kept for
# the mood->preset mapping the story pipeline relies on.
MOODS = {
    "calm":    {"tempo": 60, "bpm": 56},
    "warm":    {"tempo": 66, "bpm": 62},
    "sad":     {"tempo": 52, "bpm": 50},
    "hopeful": {"tempo": 72, "bpm": 66},
    "mystic":  {"tempo": 48, "bpm": 48},
    "epic":    {"tempo": 84, "bpm": 76},
}


def _run(args: list[str]) -> subprocess.CompletedProcess:
    return subprocess.run(args, capture_output=True, text=True)


def _measure(path: Path) -> dict:
    out = _run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(path),
                "-filter_complex", "ebur128=peak=true", "-f", "null", "-"])
    lufs = None
    for line in out.stderr.splitlines():
        s = line.strip()
        if s.startswith("I:"):
            lufs = float(s.split()[1])
    return {"integrated_lufs": lufs}


def _synthesise(mood: str, out: Path, duration: float) -> dict:
    """Render the bed with REAL instruments via `soundfont` (fluidsynth).

    K (2026-11-09): the ffmpeg sine/tremolo synth this used to be "sounds fake —
    stop using it; the music must come from a program that makes realistic
    sound." `soundfont` plays a SoundFont of recorded instruments (music box,
    piano, nylon guitar, warm pad, strings, contrabass) through fluidsynth, so
    the timbre is a real recording, not a tone generator. Free and offline; see
    that module.

    `soundfont` lives with the music engine (music938-1), so its scripts dir is
    put on the path here. The output stays an MP3 so every existing caller of
    `make()` is unchanged.
    """
    sys.path.insert(0, str(REPO / "music938-1" / "scripts"))
    import soundfont  # noqa: PLC0415

    wav = out.with_suffix(".bed.wav")
    info = soundfont.render_bed(mood, "C", wav, seconds=duration)
    res = _run(["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
                "-i", str(wav), "-c:a", "libmp3lame", "-b:a", "192k", str(out)])
    wav.unlink(missing_ok=True)
    if res.returncode != 0 or not out.exists() or out.stat().st_size == 0:
        raise RuntimeError(f"music encode failed: {res.stderr.strip()[-900:]}")
    return {"bytes": out.stat().st_size, "bpm": MOODS[mood]["bpm"],
            "source": info.get("source") or "soundfont-sampler", **_measure(out)}


def make(mood: str, key: str, *, duration: float = 90.0, force: bool = False) -> dict:
    if mood not in MOODS:
        raise ValueError(f"unknown mood {mood!r}; choose from {sorted(MOODS)}")
    existing = library.find("music", key)
    if existing and not force:
        return {"status": "REUSED", "entry": existing}

    out = library.KINDS["music"] / f"{library.entry_id('music', key)}.mp3"
    info = _synthesise(mood, out, duration)
    entry = library.add("music", key, out, source=info["source"], mood=mood,
                        duration_seconds=duration, bpm=info["bpm"],
                        integrated_lufs=info["integrated_lufs"])
    return {"status": "CREATED", "entry": entry}


# Keywords a story's MOOD line may use, mapped to the closest preset. A story
# should not have to know the preset names to get a bed.
MOOD_HINTS = {
    "sad": ("sad", "เศร้า", "โศก", "mourn", "loss", "ทิ้ง", "จากไป"),
    "calm": ("calm", "สงบ", "นิ่ง", "gentle", "soft", "นุ่ม", "folk", "lull"),
    "warm": ("warm", "อบอุ่น", "อุ่น", "home", "family", "หมู่บ้าน"),
    "hopeful": ("hopeful", "หวัง", "สว่าง", "bright", "rise", "journey", "เดินทาง"),
    "mystic": ("mystic", "ลึกลับ", "ขลัง", "magic", "หิน", "memory", "ความจำ"),
    "epic": ("epic", "สงคราม", "battle", "hero", "ยิ่งใหญ่", "storm"),
}


def preset_for(mood_text: str) -> str:
    """Pick a preset from a free-text MOOD line, defaulting to calm."""
    low = (mood_text or "").lower()
    for preset, hints in MOOD_HINTS.items():
        if any(h in low for h in hints):
            return preset
    return "calm"


def ensure_for_story(story_name: str, mood_text: str, *, duration: float = 120.0) -> dict:
    """Guarantee a bed exists for this story, generating one when absent."""
    key = f"{story_name}-mood"
    existing = library.find("music", key)
    if existing:
        return {"status": "REUSED", "entry": existing, "preset": existing.get("mood")}
    preset = preset_for(mood_text)
    result = make(preset, key, duration=duration)
    result["preset"] = preset
    return result



def main() -> int:
    ap = argparse.ArgumentParser(description="Synthesise a mood music bed offline")
    ap.add_argument("key")
    ap.add_argument("mood", choices=sorted(MOODS))
    ap.add_argument("--duration", type=float, default=90.0)
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    result = make(args.mood, args.key, duration=args.duration, force=args.force)
    print(json.dumps(result, ensure_ascii=False, indent=2) if args.json
          else f"{result['status']}: {result['entry']['file']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
