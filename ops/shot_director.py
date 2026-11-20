#!/usr/bin/env python3
"""A shot planner: cut on the music, not on the clock.

K (2026-11-20): "k อยากได้ผู้กำกับภาพยนต์ มาสร้างวีดีโอให้ ทำได้ไหม".

`clip_lane.render` used to give every still `seconds / len(stills)` — six equal
slices regardless of what the song was doing. That is a slideshow: a cut lands
wherever arithmetic puts it, which is almost never where the music moves. A
director cuts on the beat, holds longer when the song breathes, and changes the
camera when the section changes.

This module is that decision, separated from the encoder so it can be tested
without rendering anything. It reads the song itself — no lyrics file required,
because only some masters have one — and answers one question: where do the cuts
go, and what does the camera do between them?

The grammar it follows, which is what makes a cut read as deliberate:

  * **Cut on an onset.** A cut on a drum hit reads as intent; the same cut 300 ms
    earlier reads as a mistake. So every boundary snaps to the nearest onset.
  * **Shot length follows energy.** Loud, busy sections get short shots (a cut
    every ~2 s); quiet sections hold (up to ~6 s). Cutting at one rate through
    both is what makes a clip feel mechanical.
  * **Never too short, never too long.** Below ~1.2 s a shot reads as a flash
    frame; past ~6 s the picture is a still and the eye leaves.
  * **Change the camera between shots.** The same push-in twice in a row looks
    like one long shot that stuttered, so moves rotate and never repeat.
  * **Open wide.** The first shot is the establishing one: longer, and a slow
    move, so the place is read before the cutting starts.

Everything here is free: the analysis is ffmpeg decoding to PCM plus numpy, both
already installed by `scripts/bootstrap-pod.sh`. No librosa, no API, no key.
"""
from __future__ import annotations

import math
import random
import shutil
import subprocess
from pathlib import Path

# A shot shorter than this reads as a flash frame, longer than this reads as a
# still. Both are measured against what the eye tracks, not against the tempo.
MIN_SHOT = 1.2
MAX_SHOT = 6.0

# Energy decides the target length between those bounds. A loud passage aims
# near MIN, a quiet one near MAX.
LOUD_TARGET = 2.0
QUIET_TARGET = 4.8

HOP = 0.05          # analysis window, 50 ms: fine enough to place a cut
SR = 8000           # mono 8 kHz is plenty for an energy envelope

# Camera moves, as zoompan expressions. `on` is the output frame index and `N`
# the frames in the shot, so every move is normalised to the shot it is in.
MOVES = ("push_in", "pull_out", "pan_right", "pan_left", "tilt_down", "tilt_up")


def _pcm(song: Path, seconds: float, sr: int = SR) -> "object":
    """Decode the first `seconds` of a song to mono float32. Free: ffmpeg only."""
    import numpy as np  # noqa: PLC0415

    ff = shutil.which("ffmpeg")
    if not ff:
        return np.zeros(0, dtype=np.float32)
    proc = subprocess.run(
        [ff, "-v", "error", "-t", f"{seconds:.3f}", "-i", str(song),
         "-ac", "1", "-ar", str(sr), "-f", "s16le", "-"],
        capture_output=True, check=False)
    if proc.returncode != 0 or not proc.stdout:
        return np.zeros(0, dtype=np.float32)
    return np.frombuffer(proc.stdout, dtype=np.int16).astype(np.float32) / 32768.0


def envelope(song: Path, seconds: float, hop: float = HOP) -> list[float]:
    """Per-window RMS, normalised to 0..1. The shape of the song's loudness."""
    import numpy as np  # noqa: PLC0415

    x = _pcm(song, seconds)
    if x.size == 0:
        return []
    w = max(1, int(hop * SR))
    n = x.size // w
    if n == 0:
        return []
    rms = np.sqrt((x[: n * w].reshape(n, w) ** 2).mean(axis=1))
    peak = float(rms.max())
    if peak <= 1e-6:
        return [0.0] * n
    return [float(v) for v in (rms / peak)]


def onsets(env: list[float], hop: float = HOP) -> list[float]:
    """Times where the energy jumps — the audible start of a note or hit.

    A rise is scored against the local level rather than a global threshold, so a
    quiet verse still yields its own cuts instead of going uncut because the
    chorus is louder.
    """
    if len(env) < 3:
        return []
    diffs = [env[i] - env[i - 1] for i in range(1, len(env))]
    rises = [d for d in diffs if d > 0]
    if not rises:
        return []
    rises.sort()
    # The top ~8% of rises: enough to catch the beat, few enough that every
    # window does not become a cut.
    thr = rises[int(len(rises) * 0.92)]
    thr = max(thr, 0.02)
    out, last = [], -1e9
    for i, d in enumerate(diffs):
        t = (i + 1) * hop
        if d >= thr and t - last >= MIN_SHOT:
            out.append(t)
            last = t
    return out


def _local_energy(env: list[float], t: float, hop: float = HOP,
                  span: float = 1.5) -> float:
    """Mean energy in a window around `t`, so a target length follows the music."""
    if not env:
        return 0.5
    a = max(0, int((t - span / 2) / hop))
    b = min(len(env), int((t + span / 2) / hop) + 1)
    if b <= a:
        return 0.5
    return sum(env[a:b]) / (b - a)


def plan(song: Path, n_stills: int, seconds: float, seed: int = 11,
         log=print) -> list[dict]:
    """The shot list: contiguous, sums to `seconds`, cuts snapped to onsets.

    Each shot is `{start, dur, still, move, energy}`. `still` is an index into the
    still list the caller holds, so this module never touches a picture.
    """
    if n_stills <= 0 or seconds <= 0:
        return []

    env = envelope(song, seconds)
    marks = onsets(env)
    if not marks:
        log("director: no onsets in the audio; falling back to bounded even cuts")

    rng = random.Random(seed)
    shots: list[dict] = []
    t = 0.0
    idx = 0
    last_move = None
    while seconds - t > 1e-6:
        left = seconds - t
        e = _local_energy(env, t + left / 2)
        # Loud -> short, quiet -> long. A linear map keeps it predictable.
        target = QUIET_TARGET + (LOUD_TARGET - QUIET_TARGET) * e

        if idx == 0:
            # The establishing shot: longer than the music would give it, so the
            # place is read before the cutting begins.
            dur = min(MAX_SHOT, max(target, 3.0))
        else:
            dur = target
        # Snap the end to an onset near the target, else to the target itself.
        # The window is the whole allowed range, not a fixed +-0.6 s: beats are
        # often 1-2 s apart, so a narrow window gives up on most cuts and the
        # shot lands mid-phrase, which is the slideshow this replaced. Any onset
        # that keeps the shot readable is a better cut than the arithmetic one.
        want = t + dur
        if marks:
            near = [m for m in marks
                    if MIN_SHOT <= m - t <= MAX_SHOT and m > t + 1e-6]
            if near:
                want = min(near, key=lambda m: abs(m - (t + target)))
        dur = max(MIN_SHOT, min(MAX_SHOT, want - t))
        # The last shot takes whatever is left, so the sum is exact.
        if left - dur < MIN_SHOT:
            dur = left

        # Rotate the camera and never repeat the previous move: the same push-in
        # twice reads as one stuttering shot rather than two cuts.
        choices = [m for m in MOVES if m != last_move]
        move = rng.choice(choices)
        last_move = move

        shots.append({"start": round(t, 3), "dur": round(dur, 3),
                      "still": idx % n_stills, "move": move,
                      "energy": round(e, 3)})
        t += dur
        idx += 1

    if shots:
        # Absorb rounding drift into the last shot so the video is exactly
        # `seconds` long; a frame of drift makes `-shortest` trim the audio tail.
        drift = seconds - sum(s["dur"] for s in shots)
        shots[-1]["dur"] = round(shots[-1]["dur"] + drift, 3)
        log(f"director: {len(shots)} shot(s) over {seconds:.0f}s, "
            f"{len(marks)} onset(s), "
            f"moves={sorted({s['move'] for s in shots})}")
    return shots


def zoompan(shot: dict, frames: int, w: int, h: int, fps: int) -> str:
    """The zoompan expression for one shot's camera move.

    `d` is frames per INPUT frame. The caller feeds a still looped at `fps`, so
    the input already has one frame per output frame and `d` must be 1: each
    input frame makes exactly one output frame and `on` runs 0..n-1 across the
    shot. Passing `d=n` here is the per^2 bug -- every input frame would emit the
    whole shot again, the move would finish in the first `n` frames and the rest
    would repeat one frozen image, which the floor catches as "picture is frozen".
    """
    n = max(1, frames)
    # 12% travel over the shot: enough to see, small enough not to crop a face.
    step = 0.12 / n
    if shot["move"] == "push_in":
        z, x, y = f"min(1+{step:.6f}*on,1.12)", "iw/2-(iw/zoom/2)", "ih/2-(ih/zoom/2)"
    elif shot["move"] == "pull_out":
        z, x, y = f"max(1.12-{step:.6f}*on,1)", "iw/2-(iw/zoom/2)", "ih/2-(ih/zoom/2)"
    elif shot["move"] == "pan_right":
        z, x, y = "1.10", f"(iw-iw/zoom)*on/{n}", "ih/2-(ih/zoom/2)"
    elif shot["move"] == "pan_left":
        z, x, y = "1.10", f"(iw-iw/zoom)*(1-on/{n})", "ih/2-(ih/zoom/2)"
    elif shot["move"] == "tilt_down":
        z, x, y = "1.10", "iw/2-(iw/zoom/2)", f"(ih-ih/zoom)*on/{n}"
    else:  # tilt_up
        z, x, y = "1.10", "iw/2-(iw/zoom/2)", f"(ih-ih/zoom)*(1-on/{n})"
    return (f"zoompan=z='{z}':x='{x}':y='{y}':d=1:"
            f"s={w}x{h}:fps={fps}")


def describe(shots: list[dict]) -> str:
    """A one-line-per-shot readout, for the log and for review."""
    return "\n".join(
        f"  {s['start']:6.2f}s  {s['dur']:4.2f}s  still {s['still']:2d}  "
        f"{s['move']:10s}  energy {s['energy']:.2f}" for s in shots)
