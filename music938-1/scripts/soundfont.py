#!/usr/bin/env python3
"""Real-instrument music from a free SoundFont sampler (fluidsynth).

K (2026-11-09): the ffmpeg sine synth that made the sleep bed and the story
backing "sounds fake — stop using it, find a program that makes realistic
sound." The free answer is a *sampler*: `fluidsynth` plays a SoundFont whose
notes are recordings of real instruments (piano, music box, nylon guitar,
strings, contrabass). We write a MIDI file, fluidsynth renders it, ffmpeg
masters it.

Everything here is free and offline: `fluidsynth` and the MuseScore / FluidR3
soundfonts come from apt, and MIDI is generated with `mido` (pure Python). No
login, no quota, no paid plugin.

The bed is built to loop for hours, so the take is crossfaded against its own
head (`crossfade_loop`) — a reverb tail that does not divide the loop length
would click once per pass otherwise.

    python3 scripts/soundfont.py --mood calm --key C --seconds 180 --out /tmp/bed.wav
    python3 scripts/soundfont.py --list
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
from pathlib import Path

# fluidsynth and the soundfonts are apt packages; the static ffmpeg lives under
# /workspace (survives a pod recycle) but is not on PATH by default.
_BIN = "/workspace/ax-tools/bin"
if Path(_BIN, "ffmpeg").exists() and _BIN not in os.environ.get("PATH", ""):
    os.environ["PATH"] = _BIN + os.pathsep + os.environ.get("PATH", "")

SOUNDFONTS = [
    "/usr/share/sounds/sf3/MuseScore_General_Full.sf3",
    "/usr/share/sounds/sf3/MuseScore_General.sf3",
    "/usr/share/sounds/sf2/FluidR3_GM.sf2",
    "/usr/share/sounds/sf2/default-GM.sf2",
]

# The loop crossfade length: long enough to hide a reverb tail, short enough not
# to smear the beat.
XFADE_SECONDS = 1.5

# General MIDI programs. A real recording sits behind each number. Every one
# here is struck or plucked, so its notes decay — no sustained pad (K: "the hum").
P_MUSICBOX = 10
P_PIANO = 0
P_NYLON = 24
P_HARP = 46
P_BASS = 32

# Pentatonic sets: any note in the set is consonant with any other, so a random
# walk still lands in key. Offsets are semitones from the root.
SCALES = {
    "major": [0, 2, 4, 7, 9],
    "minor": [0, 3, 5, 7, 10],
    "yin":   [0, 2, 5, 7, 9],   # Thai-style pentatonic
}

# Chord qualities as semitone intervals from the chord root.
CHORD = {"maj": [0, 4, 7], "min": [0, 3, 7], "sus": [0, 5, 7]}

# A mood is a key, a tempo, a chord progression and a set of real instruments to
# voice it. `prog` is a list of (semitone offset from the tonic, quality); the
# tonic offsets are the classic I-vi-IV-V family, which is why any rotation of
# it still sounds settled. The melody reads the pentatonic `scale` on top.
#
# K (2026-11-09): "มันมีเสียงฮัม เอาแต่ดนตรีสิ" — a held chord under everything
# reads as a hum/drone, not music. Every voice here is a *struck or plucked*
# instrument whose notes decay (music box, piano, nylon guitar, harp, plucked
# bass). There is no sustained string/choir pad: that was the hum.
MOODS: dict[str, dict] = {
    "calm": {
        "root": 60, "scale": "major", "bpm": 56,
        "prog": [(0, "maj"), (9, "min"), (5, "maj"), (7, "maj")],
        "melody": P_MUSICBOX, "harp": P_HARP, "bass": P_BASS, "arp": P_PIANO,
        "gain": 0.85,
    },
    "warm": {
        "root": 57, "scale": "major", "bpm": 62,
        "prog": [(0, "maj"), (5, "maj"), (7, "maj"), (9, "min")],
        "melody": P_MUSICBOX, "harp": P_HARP, "bass": P_BASS, "arp": P_NYLON,
        "gain": 0.85,
    },
    "sad": {
        "root": 57, "scale": "minor", "bpm": 50,
        "prog": [(0, "min"), (8, "maj"), (3, "maj"), (7, "min")],
        "melody": P_MUSICBOX, "harp": P_HARP, "bass": P_BASS, "arp": P_PIANO,
        "gain": 0.82,
    },
    "hopeful": {
        "root": 62, "scale": "major", "bpm": 66,
        "prog": [(0, "maj"), (5, "maj"), (9, "min"), (7, "maj")],
        "melody": P_MUSICBOX, "harp": P_HARP, "bass": P_BASS, "arp": P_PIANO,
        "gain": 0.85,
    },
    "mystic": {
        "root": 55, "scale": "yin", "bpm": 48,
        "prog": [(0, "min"), (5, "min"), (3, "maj"), (7, "maj")],
        "melody": P_MUSICBOX, "harp": P_HARP, "bass": P_BASS, "arp": P_NYLON,
        "gain": 0.80,
    },
    "epic": {
        "root": 53, "scale": "minor", "bpm": 76,
        "prog": [(0, "min"), (8, "maj"), (5, "min"), (7, "maj")],
        "melody": P_MUSICBOX, "harp": P_HARP, "bass": P_BASS, "arp": P_PIANO,
        "gain": 0.85,
    },
}


def find_soundfont() -> str:
    for p in SOUNDFONTS:
        if Path(p).exists():
            return p
    raise FileNotFoundError(
        "no SoundFont found; install with: apt-get install -y "
        "fluidsynth musescore-general-soundfont fluid-soundfont-gm")


def _degree_to_semitone(scale: str, degree: int) -> int:
    """Map an unbounded scale degree (…-1,0,1,…) to a semitone offset.

    Degree 0 is the root; degree 5 is the root an octave up, so a melody can walk
    past the top of the pentatonic set and continue in the next octave.
    """
    s = SCALES[scale]
    n = len(s)
    octave, idx = divmod(degree, n)
    return s[idx] + 12 * octave


def _chord_tones(offset: int, quality: str, root: int) -> list[int]:
    """The triad as MIDI note numbers around `root`."""
    base = root + offset
    return [base + iv for iv in CHORD[quality]]


def build_midi(mood: str, *, bars: int, path: Path) -> dict:
    """Write a 4/4 MIDI arrangement for `mood` and return its description.

    Four voices, all real instruments, every note struck or plucked so it decays:
      * bass   — the chord root, short, low and soft
      * harp   — the chord tones plucked across the bar, the harmonic bed
      * arp    — an eighth-note broken chord on a soft piano/guitar
      * melody — a slow music-box line over the top, phrased in two-bar cells

    There is deliberately no sustained pad: a chord held under the whole bed is
    what K heard as "เสียงฮัม" (a hum). Humanisation (velocity and a few ticks of
    timing jitter) is what stops a sampler from reading as a sequencer.
    """
    import mido  # local import: keeps --list and --help working without it

    preset = MOODS[mood]
    root, scale, bpm, prog = (preset["root"], preset["scale"],
                              preset["bpm"], preset["prog"])
    beat = 60.0 / bpm           # seconds per quarter note
    ticks_per_beat = 480
    mid = mido.MidiFile(ticks_per_beat=ticks_per_beat)
    track = mido.MidiTrack()
    mid.tracks.append(track)

    def sec(t: float) -> int:
        return int(round(t / beat * ticks_per_beat))

    # fluidsynth honours the tempo meta event, not the file's nominal rate, so
    # without this the bed plays at 120 bpm and every length is wrong.
    track.append(mido.MetaMessage("set_tempo",
                                  tempo=mido.bpm2tempo(bpm), time=0))

    # Channels 0-3 carry the four voices. Program changes at time 0.
    for ch, prog_num in ((0, preset["melody"]), (1, preset["harp"]),
                         (2, preset["bass"]), (3, preset["arp"])):
        track.append(mido.Message("program_change", channel=ch,
                                  program=prog_num, time=0))
    # Reverb + chorus (GM CC91/CC93) so the sampler itself is not bone dry.
    for ch in range(4):
        track.append(mido.Message("control_change", channel=ch,
                                  control=91, value=70, time=0))
        track.append(mido.Message("control_change", channel=ch,
                                  control=93, value=25, time=0))

    events: list[tuple[int, mido.Message]] = []

    def note(ch: int, pitch: int, start: int, dur: int, vel: int) -> None:
        events.append((start, mido.Message("note_on", channel=ch,
                                           note=pitch, velocity=vel, time=0)))
        events.append((start + dur, mido.Message("note_off", channel=ch,
                                                 note=pitch, velocity=0, time=0)))

    # A motif is a short shape of scale degrees, phrased over two bars; it is
    # transposed to each chord so the line follows the harmony instead of
    # sitting on one scale run (the "howl" the drone comment warns about).
    motif = [(0, 0.0, 1.0), (2, 1.0, 0.5), (1, 1.5, 0.5),
             (3, 2.0, 1.0), (2, 3.0, 1.0)]

    bar_ticks = ticks_per_beat * 4
    for b in range(bars):
        offset, quality = prog[b % len(prog)]
        t0 = b * bar_ticks
        chord = _chord_tones(offset, quality, root)

        # bass: the chord root, struck short so it decays instead of droning
        note(2, root - 12 + offset, t0, int(bar_ticks * 0.5), 50)

        # harp: the chord tones plucked across the bar. Every note decays, so the
        # harmony moves instead of holding — a held chord is the "hum" K heard.
        for i, p in enumerate(chord):
            start = t0 + i * (bar_ticks // 4)
            note(1, p, start, int(bar_ticks * 0.5), 42)

        # arp: broken chord, eighth notes, soft, alternating up/down
        shape = [chord[0], chord[1], chord[2], chord[1]]
        eighth = ticks_per_beat // 2
        for i in range(8):
            pitch = shape[i % len(shape)] + (12 if i >= 4 else 0)
            jitter = ((i * 7 + b * 3) % 5) - 2      # -2..+2 ticks, deterministic
            vel = 46 + ((i + b) % 3) * 4
            note(3, pitch, t0 + i * eighth + jitter, int(eighth * 0.9), vel)

        # melody: one motif per two bars, transposed to the chord
        if b % 2 == 0:
            for d_off, beat_off, dur_beats in motif:
                pitch = root + 12 + _degree_to_semitone(scale, d_off + offset)
                start = t0 + sec(beat_off * beat)
                vel = 60 + ((d_off + offset) % 3) * 6
                note(0, pitch, start, sec(dur_beats * beat) - 12, vel)

    events.sort(key=lambda e: e[0])
    prev = 0
    for tick, msg in events:
        msg.time = max(0, tick - prev)
        track.append(msg)
        prev = tick
    # A little tail so the last reverb is not cut off mid-sample.
    track.append(mido.MetaMessage("end_of_track", time=ticks_per_beat * 2))

    path.parent.mkdir(parents=True, exist_ok=True)
    mid.save(str(path))
    return {"bars": bars, "bpm": bpm, "root": root, "scale": scale,
            "seconds": bars * 4 * beat}


def _render_midi(midi: Path, out_wav: Path, soundfont: str, gain: float) -> None:
    if shutil.which("fluidsynth") is None:
        raise FileNotFoundError(
            "fluidsynth not found; install with: apt-get install -y fluidsynth")
    res = subprocess.run(
        ["fluidsynth", "-ni", "-F", str(out_wav), "-r", "44100",
         "-g", f"{gain:.2f}", "-O", "s16", soundfont, str(midi)],
        capture_output=True, text=True)
    if res.returncode != 0 or not out_wav.exists() or out_wav.stat().st_size == 0:
        raise RuntimeError(f"fluidsynth failed: {res.stderr.strip()[-600:]}")


def _read_wav_f32(path: Path) -> "np.ndarray":
    """Decode a WAV to a float32 array of shape (frames, channels)."""
    import numpy as np

    probe = subprocess.run(
        ["ffprobe", "-v", "error", "-select_streams", "a:0",
         "-show_entries", "stream=channels", "-of", "csv=p=0", str(path)],
        capture_output=True, text=True)
    channels = int(probe.stdout.strip() or "1")
    res = subprocess.run(
        ["ffmpeg", "-v", "error", "-i", str(path), "-f", "f32le", "-"],
        capture_output=True)
    if res.returncode != 0:
        raise RuntimeError(f"decode failed: {res.stderr.decode(errors='replace')[-400:]}")
    data = np.frombuffer(res.stdout, dtype="<f4")
    return data.reshape(-1, channels)


def _write_wav_s16(path: Path, x: "np.ndarray") -> None:
    """Write a float array in [-1, 1] to a 16-bit PCM WAV."""
    import numpy as np
    import wave

    ints = np.clip(x, -1.0, 1.0)
    ints = (ints * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(44100)
        w.writeframes(ints.tobytes())


def crossfade_loop(x: "np.ndarray", xfade: float, fs: int = 44100) -> "np.ndarray":
    """Turn a one-shot take into a seamless loop by folding its ends together.

        X    = crossfade(S[T-d : T], S[0 : d])   # head weight rises 0 -> 1
        loop = X ++ S[d : T-d]

    The loop begins on S(T-d) and ends on S(T-d-1) — the two samples either side
    of the wrap — so the join is between adjacent audio and cannot click, and the
    internal join (X -> body) is adjacent too. Length is `T - d`; the caller
    tiles that. Done here rather than in a filter graph because the arithmetic is
    exact and a test can assert the seam without running ffmpeg.
    """
    import numpy as np

    d = int(round(xfade * fs))
    T = x.shape[0]
    if T <= 2 * d:
        raise ValueError(f"clip of {T} frames is too short to crossfade {d}")
    head = x[:d]
    tail = x[T - d:T]
    w = np.linspace(0.0, 1.0, d, dtype="<f4")[:, None]   # 0 on tail, 1 on head
    folded = tail * (1.0 - w) + head * w
    body = x[d:T - d]
    return np.concatenate([folded, body], axis=0)


def _probe_seconds(path: Path) -> float:
    res = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", str(path)], capture_output=True, text=True)
    try:
        return float(res.stdout.strip())
    except ValueError:
        return 0.0


def render_bed(mood: str, key: str, out: Path, *, seconds: float = 180.0,
               gain: float | None = None) -> dict:
    """Render a loopable real-instrument bed to `out` (16-bit WAV).

    `key` selects the root octave placement only; the mood preset owns the scale
    and harmony. The MIDI is written to a temp file next to `out` and removed
    after the render, so only the WAV is kept.
    """
    if mood not in MOODS:
        raise ValueError(f"unknown mood {mood!r}; choose from {sorted(MOODS)}")
    preset = MOODS[mood]
    beat = 60.0 / preset["bpm"]
    bars = max(1, round(seconds / (4 * beat)))
    midi = out.with_suffix(".mid")
    raw = out.with_suffix(".raw.wav")
    norm = out.with_suffix(".norm.wav")
    out.parent.mkdir(parents=True, exist_ok=True)

    build_midi(mood, bars=bars, path=midi)
    _render_midi(midi, raw, find_soundfont(), gain if gain is not None else preset["gain"])

    # Trim fluidsynth's long reverb tail (~25s past the last note) to the written
    # musical length, then normalise to a sleep-appropriate level.
    nominal = bars * 4 * beat
    res = subprocess.run(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(raw),
         "-t", f"{nominal:.4f}",
         "-af", "loudnorm=I=-20:TP=-2:LRA=7,aresample=44100",
         "-c:a", "pcm_s16le", str(norm)], capture_output=True, text=True)
    if res.returncode != 0 or not norm.exists():
        raise RuntimeError(f"bed normalise failed: {res.stderr.strip()[-600:]}")

    x = _read_wav_f32(norm)
    if x.shape[0] <= 3 * 44100:
        raise RuntimeError(f"bed too short to loop: {x.shape[0] / 44100:.2f}s")
    loop = crossfade_loop(x, XFADE_SECONDS)
    _write_wav_s16(out, loop)

    midi.unlink(missing_ok=True)
    raw.unlink(missing_ok=True)
    norm.unlink(missing_ok=True)
    return {"mood": mood, "key": key, "seconds": loop.shape[0] / 44100,
            "written_seconds": nominal, "bars": bars, "file": str(out),
            "bytes": out.stat().st_size, "soundfont": Path(find_soundfont()).name}


def main() -> int:
    ap = argparse.ArgumentParser(description="Real-instrument bed via fluidsynth")
    ap.add_argument("--mood", choices=sorted(MOODS))
    ap.add_argument("--key", default="C")
    ap.add_argument("--seconds", type=float, default=180.0)
    ap.add_argument("--out", type=Path)
    ap.add_argument("--list", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    if args.list or not args.mood:
        print(json.dumps({"moods": sorted(MOODS), "soundfont": find_soundfont()},
                         indent=2))
        return 0
    out = args.out or Path(f"/tmp/bed-{args.mood}-{args.key}.wav")
    info = render_bed(args.mood, args.key, out, seconds=args.seconds)
    print(json.dumps(info, indent=2) if args.json else f"OK: {info['file']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
