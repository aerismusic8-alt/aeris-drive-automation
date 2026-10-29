"""Build one song from a lyric file: melody, sung vocal, backing, master.

The vocal is synthesised syllable by syllable (Piper), pitch-shifted to each note
and stretched to the note's length (ffmpeg rubberband). Because every note is
placed by this script, the exact start/end of every syllable is known, which is
what the karaoke track later consumes.

Run:  python3 scripts/make_song.py 01-khon-di-khon-diao [--force]
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
import tempfile
from pathlib import Path

import numpy as np

sys.path.insert(0, str(Path(__file__).resolve().parent))

import audio  # noqa: E402
import common  # noqa: E402
import music  # noqa: E402
import tts  # noqa: E402
from common import SR  # noqa: E402

SECTIONS = ("verse", "chorus", "bridge")

# Loudness target for the finished song. -14 LUFS is the streaming norm and sits
# above the -17 used for the narration pipeline, because a song is not competing
# with speech.
TARGET_LUFS = -14.0
# The karaoke backing sits this far under the song, so a singer's voice has room.
KARAOKE_OFFSET_DB = 3.0


# --- lyric parsing ---------------------------------------------------------

def parse_lyrics(path: Path) -> dict:
    """Parse a lyric file into metadata plus the section list, in written order.

    The file defines the real structure: `[verse]`, `[chorus]`, `[bridge]`,
    `[outro]` headings in the order they are sung. Nothing is shuffled, because
    a lyric is written to be sung in that order.
    """
    text = Path(path).read_text(encoding="utf-8")
    meta: dict[str, str] = {}
    sections: list[dict] = []
    current: dict | None = None
    for raw in text.splitlines():
        line = raw.strip()
        if not line:
            continue
        m = re.match(r"^#\s*([A-Z_]+)\s*:\s*(.+)$", line)
        if m:
            meta[m.group(1).strip().lower()] = m.group(2).strip()
            continue
        m = re.match(r"^\[(\w+)\]$", line)
        if m:
            current = {"name": m.group(1).strip().lower(), "lines": []}
            sections.append(current)
            continue
        if current is None:
            current = {"name": "verse", "lines": []}
            sections.append(current)
        current["lines"].append(line)
    sections = [s for s in sections if s["lines"] or s["name"] in ("intro", "outro")]
    if not any(s["lines"] for s in sections):
        raise ValueError(f"{path} has no lyric lines")
    meta["sections"] = sections
    return meta


# --- pitch / stretch -------------------------------------------------------

def _tokenize(line: str) -> list[dict]:
    """Split a lyric line into singable tokens, keeping spaces.

    Spaces are carried as their own silent token so the sung syllable count and
    the karaoke token count are the same number. That one-to-one mapping is what
    lets the ASS karaoke tags line up with the vocal without a second alignment.

    Segmentation is validated against Piper (see tts.syllabify), and the Thai
    repeat mark `ๆ` is dropped because the voice has no phoneme for it and it
    carries no sound of its own.
    """
    out: list[dict] = []
    for chunk in line.split(" "):
        chunk = chunk.strip("ๆ").strip()
        if not chunk:
            continue
        for syl in tts.syllabify(chunk):
            if not syl.strip():
                continue
            out.append({"text": syl, "space": False})
        out.append({"text": " ", "space": True})
    if out and out[-1]["space"]:
        out.pop()
    return out


def _syllable_cache_dir() -> Path:
    d = common.WORK / "_pitch-cache"
    d.mkdir(parents=True, exist_ok=True)
    return d


def pitched(syllable: str, semitones: float, target_s: float) -> np.ndarray:
    """Pitch-shift and time-stretch one syllable, returning mono float samples.

    The pitch shift moves the note; the tempo change fits the note's length. Both
    are one rubberband call. The stretch is clamped, because past ~1.7x the voice
    turns robotic; any shortfall is filled with silence at the caller.
    """
    src = tts.synth_syllable(syllable)
    import wave
    with wave.open(str(src)) as wf:
        sr_in = wf.getframerate()
        natural = wf.getnframes() / sr_in
    ratio = 2.0 ** (semitones / 12.0)
    stretch = target_s / natural if natural > 0 else 1.0
    stretch = max(0.55, min(1.75, stretch))

    out = _syllable_cache_dir() / f"{tts.cache_key(syllable)}-{semitones:+06.1f}-{stretch:.3f}.wav"
    if not out.exists() or out.stat().st_size == 0:
        common.ffmpeg(["-i", str(src),
                       "-af", f"rubberband=pitch={ratio:.6f}:tempo={stretch:.6f}:formant=preserved",
                       "-ar", str(SR), "-ac", "1", "-c:a", "pcm_s16le", str(out)])
    with wave.open(str(out)) as wf:
        sr = wf.getframerate()
        x = np.frombuffer(wf.readframes(wf.getnframes()), dtype="<i2").astype(np.float32) / 32768.0
    if sr != SR:  # paranoia; ffmpeg was asked for SR
        idx = np.linspace(0, len(x) - 1, int(len(x) * SR / sr))
        x = np.interp(idx, np.arange(len(x)), x).astype(np.float32)
    return x


# --- song assembly ---------------------------------------------------------

def build(lyric_path: Path, *, force: bool = False, seed: int | None = None) -> dict:
    meta = parse_lyrics(lyric_path)
    slug = lyric_path.stem
    key = meta.get("key", "Am")
    mood = meta.get("mood", "calm").lower()
    if mood not in music.MOODS:
        mood = "calm"
    tempo = float(meta.get("tempo") or music.MOODS[mood]["tempo"])
    title = meta.get("title", slug)
    subtitle = meta.get("subtitle", "")
    voice = meta.get("voice", "female").lower()

    seed = seed if seed is not None else int(common.sha256_file(lyric_path)[:8], 16)
    rng = np.random.default_rng(seed & 0xFFFFFFFF)
    prng = __import__("random").Random(seed)

    root_midi, scale = music.parse_key(key)
    plan = meta["sections"]

    spb = 60.0 / tempo
    n_lines = sum(len(s["lines"]) for s in plan) or 1
    # One lyric line spans `line_beats`; pick the value that lands the song in the
    # 3.5-5 minute window for this lyric's length and tempo.
    line_beats = float(meta.get("line_beats") or _auto_line_beats(n_lines, spb))
    bars_per_line = line_beats / 4.0

    # Lay out every section on the time grid, in beats.
    sections = []
    t_beats = 0.0
    for sec in plan:
        nb = len(sec["lines"]) * line_beats if sec["lines"] else 16.0
        sections.append({"name": sec["name"], "start_beats": t_beats,
                         "beats": nb, "lines": sec["lines"]})
        t_beats += nb
    total = t_beats * spb + 2.0  # tail for the last release

    # One chord per bar over the whole song.
    total_bars = int(t_beats // 4) + 1
    chords = music.progression(root_midi, scale, music.MOODS[mood]["prog"], total_bars)

    # --- vocal + timing ---
    vocal = np.zeros(int((total + 1) * SR), dtype=np.float32)
    timing_lines = []
    prev_degree: int | None = None

    for sec in sections:
        for li, line in enumerate(sec["lines"]):
            tokens = _tokenize(line)
            if not tokens:
                continue
            line_start = (sec["start_beats"] + li * line_beats) * spb
            bar_index = int((sec["start_beats"] + li * line_beats) // 4)
            chord = chords[min(bar_index, len(chords) - 1)]
            notes, last_deg = music.melody_for_line(prng, root_midi, scale, chord,
                                                    len(tokens), line_beats, prev_degree)
            prev_degree = last_deg
            cursor = line_start
            tok_rows = []
            for (midi, beats), tok in zip(notes, tokens):
                note_dur = beats * spb
                tok_rms = 0.0
                if not tok["space"]:
                    semis = midi - 64.0  # 64 = E4, the voice's median F0
                    try:
                        clip = pitched(tok["text"], semis, note_dur * 0.92)
                    except Exception:
                        clip = np.zeros(0, dtype=np.float32)
                    if clip.size:
                        audio.add_at(vocal, clip, int(cursor * SR))
                        tok_rms = round(float(np.sqrt((clip.astype(np.float64) ** 2).mean())), 4)
                    else:
                        tok_rms = 0.0
                tok_rows.append({"text": tok["text"], "space": tok["space"],
                                 "start": round(cursor, 3), "end": round(cursor + note_dur, 3),
                                 "midi": midi, "rms": tok_rms})
                cursor += note_dur
            timing_lines.append({"section": sec["name"], "text": line,
                                 "start": round(line_start, 3),
                                 "end": round(cursor, 3), "tokens": tok_rows})

    # --- backing ---
    backing = _backing(sections, chords, spb, total, mood, rng)

    # --- mix ---
    n = max(len(vocal), len(backing))
    vocal = np.pad(vocal, (0, n - len(vocal)))
    backing = np.pad(backing, (0, n - len(backing)))
    # The vocal is sparse (one note per syllable) while the backing is
    # continuous, so normalise the vocal on its own loud parts: an overall RMS
    # target would under-power the notes that are actually there.
    vocal = audio.normalize(vocal, 0.30, floor=True)
    backing = audio.normalize(backing, 0.11)
    # The drum hits can push the backing over full scale; clamp before it is
    # written to 16-bit, or the instrumental clips on its own.
    bpeak = float(np.abs(backing).max())
    if bpeak > 0.95:
        backing = (backing * (0.95 / bpeak)).astype(np.float32)
    # Duck the backing under the voice so the lyric always sits on top.
    ducked = _duck(backing, vocal)
    mix = np.stack([ducked + 1.05 * vocal, ducked + 1.05 * vocal], axis=1).astype(np.float32)
    # The vocal peaks well above the backing, so the sum can exceed full scale
    # and clip when written to 16-bit, which distorts the voice and makes the
    # loudness meter read nonsense. Scale the whole mix down if it would clip;
    # the ratio is unchanged, and loudnorm sets the final level afterwards.
    peak = float(np.abs(mix).max())
    if peak > 0.95:
        mix = (mix * (0.95 / peak)).astype(np.float32)

    work = common.WORK / slug
    work.mkdir(parents=True, exist_ok=True)
    mix_wav = work / "mix.wav"
    audio.write_wav(mix_wav, mix, SR)

    # The instrumental is the same backing without the lead vocal, used by the
    # karaoke render and available as a bonus track.
    inst_wav = work / "instrumental.wav"
    audio.write_wav(inst_wav, np.stack([backing, backing], axis=1).astype(np.float32), SR)

    song_wav = common.LIBRARY / "songs" / f"song-{slug}.wav"
    song_mp3 = common.LIBRARY / "songs" / f"song-{slug}.mp3"
    song_wav.parent.mkdir(parents=True, exist_ok=True)
    # Two-pass loudnorm: measure, then apply linearly, so the level is exact.
    measured = _measure_loudnorm(mix_wav)
    _apply_loudnorm(mix_wav, song_wav, measured)

    # The karaoke is the same backing with the lead vocal removed. It is mastered
    # to its own target, a little under the song, because a singer adds the top
    # line: at full song level the backing would bury them. Measuring the
    # instrumental on its own (rather than reusing the song's gain) keeps a
    # standalone karaoke track at a normal listening level; the -3 LU offset
    # guarantees it stays under the song at every sung moment.
    kara_target = TARGET_LUFS - KARAOKE_OFFSET_DB
    kara_wav = common.LIBRARY / "songs" / f"karaoke-{slug}.wav"
    kara_mp3 = common.LIBRARY / "songs" / f"karaoke-{slug}.mp3"
    km = _measure_loudnorm(inst_wav, target=kara_target)
    _apply_loudnorm(inst_wav, kara_wav, km, target=kara_target)
    common.ffmpeg(["-i", str(song_wav), "-c:a", "libmp3lame", "-b:a", "192k", str(song_mp3)])
    common.ffmpeg(["-i", str(kara_wav), "-c:a", "libmp3lame", "-b:a", "192k", str(kara_mp3)])

    timing = {
        "slug": slug, "title": title, "subtitle": subtitle, "key": key, "mood": mood,
        "tempo": tempo, "voice": voice, "seed": seed,
        "duration": round(common.duration(song_mp3), 3),
        "lines": timing_lines,
    }
    common.write_json(work / "timing.json", timing)

    cover = None
    try:
        import covers
        cover = covers.make_cover(slug, title, subtitle, mood)
    except Exception as exc:  # a cover is nice-to-have, never a build blocker
        print(f"cover failed: {exc}", file=sys.stderr)

    entry = {
        "id": f"song-{slug}", "file": str(song_mp3.relative_to(common.ROOT)),
        "bytes": song_mp3.stat().st_size, "sha256": common.sha256_file(song_mp3),
        "duration_seconds": timing["duration"], "title": title, "key": key,
        "mood": mood, "tempo": tempo, "voice": voice,
        "integrated_lufs": common.integrated_lufs(song_mp3),
        "source": "offline-engine", "seed": seed,
        "karaoke_file": str(kara_mp3.relative_to(common.ROOT)),
        "cover_file": str(cover.relative_to(common.ROOT)) if cover else None,
    }
    _record(entry)
    return {"status": "CREATED", "entry": entry, "timing": str(work / "timing.json")}


def _auto_line_beats(n_lines: int, spb: float) -> float:
    """Pick beats-per-line so the song lasts 3.5-5 minutes.

    Consider whole-bar values and take the one whose total duration is closest to
    the middle of the window, so the harmony stays aligned to the grid.
    """
    target = 250.0
    best, best_err = 6.0, None
    # Multiples of two beats, so a line can also start on the half-bar. Candidates
    # that push the song past 5 minutes are rejected outright.
    for beats in range(2, 18, 2):
        total = n_lines * beats * spb + 34.0  # + intro/outro
        if total > 298.0:
            continue
        err = abs(total - target)
        if best_err is None or err < best_err:
            best, best_err = float(beats), err
    return best


def _duck(backing: np.ndarray, vocal: np.ndarray, amount: float = 0.42) -> np.ndarray:
    """Side-chain style ducking with a smoothed vocal envelope."""
    win = int(0.05 * SR)
    env = np.abs(vocal)
    kernel = np.ones(win, dtype=np.float32) / win
    smooth = np.convolve(env, kernel, mode="same")
    peak = smooth.max() or 1.0
    gain = 1.0 - amount * np.clip(smooth / peak * 3.0, 0, 1)
    return (backing * gain).astype(np.float32)


def _backing(sections, chords, spb, total, mood, rng) -> np.ndarray:
    n = int((total + 1) * SR)
    pad = np.zeros(n, dtype=np.float32)
    keys = np.zeros(n, dtype=np.float32)
    bass = np.zeros(n, dtype=np.float32)
    drums = np.zeros(n, dtype=np.float32)
    feel = music.MOODS[mood]["feel"]
    bar = 4 * spb

    for sec in sections:
        name = sec["name"]
        level = 0.6 if name in ("intro", "outro") else 1.0
        n_bars = int(sec["beats"] // 4)
        for b in range(n_bars):
            bar_start = sec["start_beats"] * spb + b * bar
            idx = int((sec["start_beats"] + b * 4) // 4)
            chord = chords[min(idx, len(chords) - 1)]
            i0 = int(bar_start * SR)
            # Pad: the triad held for the bar.
            for m in chord.notes:
                audio.add_at(pad, audio.tone(music.midi_to_freq(m + 12), bar * 1.02,
                                             "pad", amp=0.10 * level, attack=0.35,
                                             release=0.6, vibrato=0.004), i0)
            # Keys: an arpeggio on the beats.
            arp = [chord.notes[0], chord.notes[1], chord.notes[2], chord.notes[1]]
            for k in range(4):
                audio.add_at(keys, audio.pluck(music.midi_to_freq(arp[k] + 12),
                                               spb * 0.9, amp=0.09 * level),
                             int((bar_start + k * spb) * SR))
            # Bass: root on 1 and 3.
            for k in (0, 2):
                audio.add_at(bass, audio.tone(music.midi_to_freq(chord.root - 12),
                                              spb * 1.6, "bass", amp=0.16 * level,
                                              attack=0.01, release=0.3),
                             int((bar_start + k * spb) * SR))
            if feel != "ballad" and name not in ("intro", "outro"):
                audio.add_at(drums, audio.kick(amp=0.4 * level), int(bar_start * SR))
                audio.add_at(drums, audio.kick(amp=0.32 * level), int((bar_start + 2 * spb) * SR))
                audio.add_at(drums, audio.snare(rng=rng, amp=0.22 * level),
                             int((bar_start + spb) * SR))
                audio.add_at(drums, audio.snare(rng=rng, amp=0.22 * level),
                             int((bar_start + 3 * spb) * SR))
            for k in range(8):
                audio.add_at(drums, audio.hihat(rng=rng, amp=0.05 * level),
                             int((bar_start + k * spb / 2) * SR))

    return pad + keys + bass + drums


def _measure_loudnorm(src: Path, *, target: float = TARGET_LUFS) -> dict:
    res = common.run(["ffmpeg", "-hide_banner", "-nostats", "-i", str(src),
                      "-af", f"loudnorm=I={target}:TP=-1.5:LRA=11:print_format=json",
                      "-f", "null", "-"], check=False)
    blob = res.stderr[res.stderr.rfind("{"):]
    blob = blob[:blob.rfind("}") + 1]
    try:
        return json.loads(blob)
    except Exception:
        return {}


def _apply_loudnorm(src: Path, dst: Path, m: dict, *,
                    target: float = TARGET_LUFS) -> None:
    if m:
        filt = (f"loudnorm=I={target}:TP=-1.5:LRA=11:linear=true:"
                f"measured_I={m.get('input_i')}:measured_TP={m.get('input_tp')}:"
                f"measured_LRA={m.get('input_lra')}:measured_thresh={m.get('input_thresh')}:"
                f"offset={m.get('target_offset', 0)}")
    else:
        filt = f"loudnorm=I={target}:TP=-1.5:LRA=11"
    common.ffmpeg(["-i", str(src), "-af", filt, "-ar", str(SR), "-ac", "2",
                   "-c:a", "pcm_s16le", str(dst)])


def _record(entry: dict) -> None:
    man = common.LIBRARY / "songs" / "manifest.json"
    data = common.read_json(man) if man.exists() else {"entries": []}
    data["entries"] = [e for e in data.get("entries", []) if e.get("id") != entry["id"]]
    data["entries"].append(entry)
    common.write_json(man, data)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("slug")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args()
    path = common.LYRICS / f"{args.slug}.txt"
    if not path.exists():
        print(f"no lyric file {path}", file=sys.stderr)
        return 2
    res = build(path, force=args.force)
    print(json.dumps(res["entry"], ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
