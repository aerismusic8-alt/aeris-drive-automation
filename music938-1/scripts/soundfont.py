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
import tempfile
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

# The pre-rendered real-instrument beds, shipped on the media release and pulled
# back on a runner that cannot build the sampler. `render_bed` prefers one over
# the General-MIDI fallback, so a rail never re-synthesises the timbre K rejected.
ROOT = Path(__file__).resolve().parent.parent
_BEDS = ROOT / "library" / "ambient"
_BED_TAG = "sampler1"
# A whole 180 s stereo bed is ~30 MB; anything far smaller is a truncated pull and
# must not be trusted (the same failure the bed cache guards against).
_MIN_BED_BYTES = 44100 * 2 * 2 * 150

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


def build_midi(mood: str, *, bars: int, path: Path, seed: int = 0) -> dict:
    """Write a 4/4 MIDI arrangement for `mood` and return its description.

    Four voices, all real instruments, every note struck or plucked so it decays:
      * bass   — the chord root, short, low and soft
      * harp   — the chord tones plucked across the bar, the harmonic bed
      * arp    — an eighth-note broken chord on a soft piano/guitar
      * melody — a slow music-box line over the top, phrased in two-bar cells

    There is deliberately no sustained pad: a chord held under the whole bed is
    what K heard as "เสียงฮัม" (a hum). Humanisation (velocity and a few ticks of
    timing jitter) is what stops a sampler from reading as a sequencer.

    `seed` varies the motif, the chord-progression rotation and the arpeggio
    direction, so two songs that share a mood and a key still get different
    music. Without it the offline lane rendered one bed per (mood, key) and
    shipped five songs that were two files — the exact "ดนตรีห้ามซ้ำกัน"
    violation K set the arrangement system to prevent (measured 2026-11-14).
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
    # sitting on one scale run (which would read as a drone). `seed` rotates the
    # shape and the progression, so two songs in one mood do not share a melody.
    base_motif = [(0, 0.0, 1.0), (2, 1.0, 0.5), (1, 1.5, 0.5),
                  (3, 2.0, 1.0), (2, 3.0, 1.0)]
    rot = seed % len(base_motif)
    motif = base_motif[rot:] + base_motif[:rot]
    prog_rot = seed % len(prog)
    prog = prog[prog_rot:] + prog[:prog_rot]

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

        # arp: broken chord, eighth notes, soft, direction varied by the seed so
        # the same chord does not always sweep the same way
        shape = [chord[0], chord[1], chord[2], chord[1]]
        if seed % 2:
            shape = shape[::-1]
        eighth = ticks_per_beat // 2
        for i in range(8):
            pitch = shape[i % len(shape)] + (12 if (i >= 4) != bool(seed % 2) else 0)
            jitter = ((i * 7 + b * 3 + seed) % 5) - 2   # -2..+2 ticks, deterministic
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


# ── real-instrument rendering (sfizz) ─────────────────────────────────────────
# A General-MIDI SoundFont is one thin sample stretched across the keyboard; it
# is what K heard as "fake". When the sfizz sampler and its real banks are
# present the bed and the song backing render through multi-velocity recordings
# of actual instruments instead. `USE_REAL_INSTRUMENTS=0` forces the GM path.
_REAL_ENV = "USE_REAL_INSTRUMENTS"

# MIDI channel -> instrument role, matching the channel layout the two MIDI
# builders below write. Channel 9 is the GM drum kit, which has no SFZ bank, so
# it stays on fluidsynth and is mixed under the sampled voices.
_BED_CHANNEL_ROLES = {0: "harp", 1: "harp", 2: "bass", 3: "piano"}
_BACKING_CHANNEL_ROLES = {0: "piano", 1: "harp", 2: "bass"}


def real_instruments_enabled() -> bool:
    if os.environ.get(_REAL_ENV, "").strip().lower() in ("0", "false", "no"):
        return False
    try:
        import sampler  # noqa: PLC0415
    except Exception:  # noqa: BLE001
        return False
    return sampler.available()


# When set, a bed or backing that would fall back to the General-MIDI SoundFont
# raises instead of rendering. K (2026-11-09) rejected that timbre outright, so a
# rail that publishes audio sets this and fails loudly rather than shipping the
# sound he refused (advisor panel, duck + pollinations, 2026-11-12: "never a
# silent GM fallback — fail the workflow before publication").
_REQUIRE_REAL_ENV = "AX_REQUIRE_REAL_INSTRUMENTS"


def require_real_instruments() -> bool:
    return os.environ.get(_REQUIRE_REAL_ENV, "").strip().lower() not in ("", "0", "false", "no")


def _gm_fallback_or_raise(what: str) -> None:
    if require_real_instruments():
        raise RuntimeError(
            f"{what} would render through the General-MIDI SoundFont, which K "
            f"rejected as fake (2026-11-09), and {_REQUIRE_REAL_ENV} is set. "
            f"Install the sfizz sampler and its real banks (scripts/install-sfizz.sh) "
            f"or pull the pre-rendered beds (scripts/pull_media.py --only beds). "
            f"Unset {_REQUIRE_REAL_ENV} to allow the fallback on a dev pod.")


def pulled_bed(mood: str, key: str) -> Path | None:
    """A pre-rendered real-instrument bed from the media release, if present.

    A runner cannot build the sfizz sampler and its gigabyte banks, so it pulls
    the approved beds instead of re-synthesising them. This is the free, durable
    route the advisor panel named (duck + pollinations, 2026-11-12): render once
    on a pod that has the sampler, ship the WAV, and let the rail tile it. The
    file must be a whole bed, or a truncated pull would loop a fragment.
    """
    p = _BEDS / f"{_BED_TAG}-{mood}-{key}.wav"
    return p if p.exists() and p.stat().st_size >= _MIN_BED_BYTES else None


def _mix_wavs(parts: list[Path], out_wav: Path) -> None:
    if len(parts) == 1:
        shutil.copy(parts[0], out_wav)
        return
    cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
    for p in parts:
        cmd += ["-i", str(p)]
    cmd += ["-filter_complex",
            "".join(f"[{i}:a]" for i in range(len(parts)))
            + f"amix=inputs={len(parts)}:normalize=0[a]",
            "-map", "[a]", "-c:a", "pcm_s16le", str(out_wav)]
    res = subprocess.run(cmd, capture_output=True, text=True)
    if res.returncode != 0:
        raise RuntimeError(f"mix failed: {res.stderr.strip()[-600:]}")


def _render_real(midi: Path, out_wav: Path, channel_roles: dict[int, str],
                 gains: dict[int, float], *, drums_gain: float | None = None) -> dict:
    """Render tonal channels through real instruments; keep drums on GM.

    Returns the sampler's own report so the caller can log which bank each voice
    used. Drums (channel 9) have no SFZ bank, so they render through fluidsynth
    and mix under the sampled voices; when the MIDI carries no drums this is a
    pure sampled render.
    """
    import sampler  # noqa: PLC0415

    with tempfile.TemporaryDirectory() as td:
        tdp = Path(td)
        tonal = tdp / "tonal.wav"
        report = sampler.render_multichannel(midi, tonal, channel_roles,
                                             gains=gains)
        drum_midi = _only_channel(midi, 9)
        parts = [tonal]
        if drum_midi is not None:
            dp = tdp / "drums.wav"
            _render_midi(drum_midi, dp, find_soundfont(),
                         drums_gain if drums_gain is not None else 0.7)
            parts.append(dp)
        _mix_wavs(parts, out_wav)
        report["drums"] = drum_midi is not None
    return report


def _only_channel(midi: Path, ch: int) -> Path | None:
    """Return a temp MIDI with only channel `ch` (None if it has no notes)."""
    import mido  # noqa: PLC0415

    src = mido.MidiFile(str(midi))
    has = any(getattr(m, "channel", None) == ch and m.type == "note_on"
              for m in src.tracks[0])
    if not has:
        return None
    out = mido.MidiFile(ticks_per_beat=src.ticks_per_beat)
    track = mido.MidiTrack()
    out.tracks.append(track)
    for m in src.tracks[0]:
        if getattr(m, "channel", None) == ch or m.is_meta:
            track.append(m.copy())
    dest = Path(tempfile.mkstemp(suffix=".mid")[1])
    out.save(str(dest))
    return dest


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


# General MIDI percussion (channel 9). Real drum samples, so the beat is a
# recorded kit and not the additive-synth kick/snare/hihat the story bed used.
DRUM_KICK = 36
DRUM_SNARE = 38
DRUM_HIHAT = 42


def build_backing_midi(mood: str, chords, *, spb: float, total: float,
                       path: Path, feel: str = "mid") -> dict:
    """Write a MIDI backing for an existing chord progression (a song's own).

    Unlike `build_midi`, the harmony is supplied rather than invented: `chords`
    is the per-bar progression `make_song` already computed, so the instrument
    bed follows the vocal's chords exactly. Voices mirror that arrangement —
    plucked keys on the beats, harp on the chord tones, a short root bass — plus
    a real drum kit on GM channel 9 when the feel is not a ballad. No sustained
    pad: a held chord is the hum K rejected.

    Each `chords` entry needs `.notes` (MIDI, low to high) and `.root`; a plain
    (notes, root) pair is accepted too.
    """
    import mido  # local import: keeps --list and --help working without it

    preset = MOODS[mood]
    ticks_per_beat = 480
    beat = spb
    mid = mido.MidiFile(ticks_per_beat=ticks_per_beat)
    track = mido.MidiTrack()
    mid.tracks.append(track)
    track.append(mido.MetaMessage("set_tempo", tempo=mido.bpm2tempo(60.0 / beat),
                                  time=0))
    # 0 keys, 1 harp, 2 bass, 9 percussion.
    for ch, prog_num in ((0, preset["arp"]), (1, preset["harp"]),
                         (2, preset["bass"])):
        track.append(mido.Message("program_change", channel=ch,
                                  program=prog_num, time=0))
    for ch in (0, 1, 2):
        track.append(mido.Message("control_change", channel=ch, control=91,
                                  value=70, time=0))
        track.append(mido.Message("control_change", channel=ch, control=93,
                                  value=25, time=0))

    events: list[tuple[int, mido.Message]] = []

    def note(ch: int, pitch: int, start: int, dur: int, vel: int) -> None:
        events.append((start, mido.Message("note_on", channel=ch, note=pitch,
                                           velocity=vel, time=0)))
        events.append((start + dur, mido.Message("note_off", channel=ch,
                                                 note=pitch, velocity=0, time=0)))

    def sec(t: float) -> int:
        return int(round(t / beat * ticks_per_beat))

    def _parts(c):
        if isinstance(c, (tuple, list)):
            notes, root = c[0], c[1]
        else:
            notes, root = c.notes, c.root
        return list(notes), int(root)

    bar = 4 * beat
    bar_ticks = ticks_per_beat * 4
    eighth = ticks_per_beat // 2
    n_bars = max(1, int(round(total / bar)))
    drums = feel != "ballad"
    for b in range(n_bars):
        notes, root = _parts(chords[min(b, len(chords) - 1)])
        t0 = b * bar_ticks
        # keys: the chord tones arpeggiated once per beat, an octave up
        shape = [notes[0], notes[1 % len(notes)], notes[2 % len(notes)],
                 notes[1 % len(notes)]]
        for k in range(4):
            pitch = shape[k] + 12
            jitter = ((k * 7 + b * 3) % 5) - 2
            note(0, pitch, t0 + k * ticks_per_beat + jitter,
                 int(ticks_per_beat * 0.9), 44 + ((k + b) % 3) * 4)
        # harp: the chord tones plucked across the bar
        for i, p in enumerate(notes):
            start = t0 + i * (bar_ticks // max(1, len(notes)))
            note(1, p, start, int(bar_ticks * 0.5), 40)
        # bass: the root on 1 and 3, short so it decays
        for k in (0, 2):
            note(2, root - 12, t0 + k * ticks_per_beat,
                 int(ticks_per_beat * 1.6), 52)
        if drums:
            for k in (0, 2):
                note(9, DRUM_KICK, t0 + k * ticks_per_beat, 30, 96)
            for k in (1, 3):
                note(9, DRUM_SNARE, t0 + k * ticks_per_beat, 30, 78)
            for k in range(8):
                note(9, DRUM_HIHAT, t0 + k * eighth, 20, 52)

    events.sort(key=lambda e: e[0])
    prev = 0
    for tick, msg in events:
        msg.time = max(0, tick - prev)
        track.append(msg)
        prev = tick
    track.append(mido.MetaMessage("end_of_track", time=ticks_per_beat * 2))
    path.parent.mkdir(parents=True, exist_ok=True)
    mid.save(str(path))
    return {"bars": n_bars, "bpm": 60.0 / beat, "seconds": n_bars * bar}


def render_backing(mood: str, chords, *, spb: float, total: float,
                   feel: str = "mid", gain: float | None = None):
    """Render a song's chord progression as a real-instrument backing.

    Returns a mono float32 array at 44.1 kHz, exactly `total` seconds long, so
    `make_song` can drop it in where its additive-synth bed used to be. The MIDI
    and the sampler's raw take are written to temp files and removed, leaving no
    artefact next to the caller's own output.
    """
    import numpy as np
    import tempfile

    preset = MOODS[mood]
    with tempfile.TemporaryDirectory() as td:
        midi = Path(td) / "backing.mid"
        raw = Path(td) / "backing.wav"
        build_backing_midi(mood, chords, spb=spb, total=total, path=midi,
                           feel=feel)
        gains = {ch: 1.0 for ch in _BACKING_CHANNEL_ROLES}
        if real_instruments_enabled():
            _render_real(midi, raw, _BACKING_CHANNEL_ROLES, gains,
                         drums_gain=preset["gain"])
        else:
            _gm_fallback_or_raise("the song backing")
            _render_midi(midi, raw, find_soundfont(),
                         gain if gain is not None else preset["gain"])
        x = _read_wav_f32(raw)
    if x.ndim > 1:
        x = x.mean(axis=1)
    x = x.astype(np.float32)
    want = int(round(total * 44100))
    if x.shape[0] < want:
        x = np.pad(x, (0, want - x.shape[0]))
    return x[:want]


def render_bed(mood: str, key: str, out: Path, *, seconds: float = 180.0,
               gain: float | None = None, seed: int = 0) -> dict:
    """Render a loopable real-instrument bed to `out` (16-bit WAV).

    `key` selects the root octave placement only; the mood preset owns the scale
    and harmony. `seed` varies the melody, progression rotation and arpeggio, so
    two songs in the same mood are not the same music (see `build_midi`). The
    MIDI is written to a temp file next to `out` and removed after the render, so
    only the WAV is kept.
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

    build_midi(mood, bars=bars, path=midi, seed=seed)
    g = gain if gain is not None else preset["gain"]
    if real_instruments_enabled():
        _render_real(midi, raw, _BED_CHANNEL_ROLES,
                     {ch: g for ch in _BED_CHANNEL_ROLES})
    else:
        # No sampler on this host. Prefer the bed already rendered through real
        # instruments and shipped on the media release; only if that is absent do
        # we fall back to General-MIDI, and never silently when the caller
        # requires real instruments.
        shipped = pulled_bed(mood, key)
        if shipped is not None:
            midi.unlink(missing_ok=True)
            # The pulled bed is a seamless loop, so tile it to the requested
            # length. Copying it verbatim would shrink a song bed that asked for
            # 210 s down to the 180 s loop unit.
            import numpy as np  # noqa: PLC0415

            x = _read_wav_f32(shipped)
            # A runner has one shipped loop per (mood, key), so without a phase
            # shift every song in a mood would tile to the same audio — the
            # duplicate-music defect this seed exists to prevent. Rotating a
            # seamless loop keeps it seamless and opens on a different bar.
            if seed and x.shape[0] > 1:
                off = int(seed) % x.shape[0]
                if off:
                    x = np.concatenate([x[off:], x[:off]], axis=0)
            want = int(round(seconds * 44100))
            reps = -(-want // x.shape[0])
            tiled = np.tile(x, (reps, 1))[:want]
            _write_wav_s16(out, tiled)
            return {"mood": mood, "key": key, "seconds": tiled.shape[0] / 44100,
                    "file": str(out), "bytes": out.stat().st_size,
                    "source": "pulled-bed"}
        _gm_fallback_or_raise("the ambient bed")
        _render_midi(midi, raw, find_soundfont(), g)

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
