"""Offline audio synthesis for the backing track.

No sample libraries and no accounts: every instrument is additive synthesis in
numpy, so the backing is deterministic and royalty-free. The result is a small
band (pad, plucked keys, bass, soft drums) which is enough to carry a vocal
without competing with it.
"""
from __future__ import annotations

import wave
from dataclasses import dataclass

import numpy as np

from common import SR

# Harmonic amplitude sets. Higher partials make a timbre brighter.
TIMBRES = {
    "pad":     [1.0, 0.45, 0.28, 0.14, 0.07],
    "strings": [1.0, 0.6, 0.42, 0.28, 0.16, 0.08],
    "keys":    [1.0, 0.35, 0.18, 0.07, 0.03],
    "bass":    [1.0, 0.3, 0.09],
    "flute":   [1.0, 0.12, 0.05],
}


def _adsr(n: int, attack: float, decay: float, sustain: float, release: float) -> np.ndarray:
    a = int(attack * SR)
    d = int(decay * SR)
    r = int(release * SR)
    a = min(a, n)
    d = min(d, max(0, n - a))
    r = min(r, max(0, n - a - d))
    s = max(0, n - a - d - r)
    parts = [
        np.linspace(0.0, 1.0, a, endpoint=False) if a else np.empty(0),
        np.linspace(1.0, sustain, d, endpoint=False) if d else np.empty(0),
        np.full(s, sustain),
        np.linspace(sustain, 0.0, r) if r else np.empty(0),
    ]
    env = np.concatenate(parts)
    if env.size < n:
        env = np.concatenate([env, np.zeros(n - env.size)])
    return env[:n]


def tone(freq: float, dur: float, timbre: str = "keys", *, amp: float = 0.2,
         attack: float = 0.01, release: float = 0.15, vibrato: float = 0.0,
         vibrato_rate: float = 5.0) -> np.ndarray:
    n = int(dur * SR)
    if n <= 0:
        return np.empty(0, dtype=np.float32)
    t = np.arange(n) / SR
    if vibrato > 0:
        # Phase modulation for a steady vibrato; integrating keeps it continuous.
        mod = vibrato * np.sin(2 * np.pi * vibrato_rate * t)
        phase = 2 * np.pi * freq * (t + np.cumsum(mod) / SR)
    else:
        phase = 2 * np.pi * freq * t
    harmonics = TIMBRES.get(timbre, TIMBRES["keys"])
    x = np.zeros(n, dtype=np.float64)
    nyq = SR / 2
    for k, h in enumerate(harmonics, start=1):
        f = freq * k
        if f >= nyq * 0.98:
            break
        x += h * np.sin(phase * k)
    x /= max(1e-9, sum(harmonics[:len(harmonics)]))
    env = _adsr(n, attack, 0.15, 0.75, release)
    return (x * env * amp).astype(np.float32)


def pluck(freq: float, dur: float, *, amp: float = 0.2) -> np.ndarray:
    n = int(dur * SR)
    if n <= 0:
        return np.empty(0, dtype=np.float32)
    t = np.arange(n) / SR
    harmonics = TIMBRES["keys"]
    x = np.zeros(n, dtype=np.float64)
    for k, h in enumerate(harmonics, start=1):
        if freq * k >= SR * 0.49:
            break
        x += h * np.sin(2 * np.pi * freq * k * t) * np.exp(-t * (2.2 + 0.7 * k))
    x /= sum(harmonics)
    return (x * amp).astype(np.float32)


# --- drums -----------------------------------------------------------------

def _noise(n: int, rng: np.random.Generator) -> np.ndarray:
    return rng.standard_normal(n).astype(np.float32)


def kick(dur: float = 0.28, *, amp: float = 0.5) -> np.ndarray:
    n = int(dur * SR)
    t = np.arange(n) / SR
    f = 130.0 * np.exp(-t * 22.0) + 48.0
    phase = 2 * np.pi * np.cumsum(f) / SR
    env = np.exp(-t * 11.0)
    return (np.sin(phase) * env * amp).astype(np.float32)


def snare(dur: float = 0.20, *, amp: float = 0.28, rng: np.random.Generator | None = None) -> np.ndarray:
    rng = rng or np.random.default_rng(1)
    n = int(dur * SR)
    t = np.arange(n) / SR
    body = 0.4 * np.sin(2 * np.pi * 190 * t) * np.exp(-t * 26.0)
    noise = _noise(n, rng) * np.exp(-t * 24.0)
    x = 0.6 * noise + body
    # A crude high-pass: differencing tilts the spectrum up.
    x = np.diff(x, prepend=x[:1])
    return (x * amp).astype(np.float32)


def hihat(dur: float = 0.06, *, amp: float = 0.12, rng: np.random.Generator | None = None) -> np.ndarray:
    rng = rng or np.random.default_rng(2)
    n = int(dur * SR)
    t = np.arange(n) / SR
    x = _noise(n, rng) * np.exp(-t * 60.0)
    x = np.diff(x, prepend=x[:1])
    return (x * amp).astype(np.float32)


# --- mixing helpers --------------------------------------------------------

def add_at(buf: np.ndarray, clip: np.ndarray, start: int) -> None:
    if clip.size == 0:
        return
    end = min(len(buf), start + len(clip))
    if end <= start:
        return
    buf[start:end] += clip[:end - start]


def write_wav(path, stereo: np.ndarray, sr: int = SR) -> None:
    """Write float stereo in [-1,1] to a 16-bit PCM WAV."""
    x = np.clip(stereo, -1.0, 1.0)
    pcm = (x * 32767.0).astype("<i2")
    with wave.open(str(path), "wb") as wf:
        wf.setnchannels(2)
        wf.setsampwidth(2)
        wf.setframerate(sr)
        wf.writeframes(pcm.tobytes())


def rms(x: np.ndarray) -> float:
    return float(np.sqrt(np.mean(np.square(x)))) if x.size else 0.0


def normalize(x: np.ndarray, target_rms: float = 0.12, *,
              floor: bool = False, floor_pct: float = 30.0) -> np.ndarray:
    """Scale to a target RMS.

    With `floor`, the RMS is measured only over frames louder than
    `floor_pct` percent of the peak. A vocal track is mostly silence between
    syllables, so a plain RMS would over-amplify the few notes that exist.
    """
    if floor:
        win = 1024
        n = (len(x) // win) * win
        if n:
            frames = x[:n].reshape(-1, win)
            fr = np.sqrt((frames ** 2).mean(axis=1))
            thr = np.percentile(fr, floor_pct)
            sel = frames[fr >= thr]
            r = float(np.sqrt((sel ** 2).mean())) if sel.size else rms(x)
        else:
            r = rms(x)
    else:
        r = rms(x)
    if r < 1e-9:
        return x
    return (x * (target_rms / r)).astype(np.float32)
