#!/usr/bin/env python3
"""v2 of the K-voice conversion: fix the three things that made v1 unusable.

v1 problems, and what changes here:
  1. Reference was a 60 s slice of a very quiet (−43 dB) phone recording, so the
     matching set was noisy. Now: denoise + high-pass + loudnorm, and use the
     steady part of K's take.
  2. kNN-VC output is 16 kHz, so everything above 8 kHz is gone — it sounds
     muffled/dull. Now: spectral tilt fix (cut the boxy 500 Hz, lift presence
     and air) and an optional blend of the *source* singer's high band, which
     restores real breath and sibilance.
  3. The raw output had no dynamics control. Now: gentle compression + a
     two-pass loudness target, then the mix.

Produces a short A/B clip rather than a whole song, so K can judge fast.

    voice-clone/vc-venv/bin/python scripts/voice_convert_v2.py 01-khon-di-thi-chak-pai \
        --start 135 --dur 60 --topk 4 --tag A
"""
from __future__ import annotations

import argparse
import os
import subprocess
from pathlib import Path

os.environ.setdefault("TORCH_HOME", "/workspace/ax-tools/torch-cache")

ROOT = Path(__file__).resolve().parent.parent
FFMPEG = "/workspace/ax-tools/bin/ffmpeg"
REF_RAW = ROOT / "voice-inbox" / "k-voice-raw.m4a"
OUT_DIR = ROOT / "library" / "songs-voice-v2"
PREVIEW = ROOT / "voice-preview"

CHUNK_SECONDS = 15.0


def _ff(*args):
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", *args], check=True)


def _patch_torchaudio():
    import numpy as np
    import soundfile as sf
    import torch
    import torchaudio

    def _load(path, *a, **k):
        data, sr = sf.read(str(path), dtype="float32", always_2d=True)
        return torch.from_numpy(data.T), sr

    def _save(path, tensor, sr, *a, **k):
        data = tensor.detach().cpu().numpy()
        if data.ndim == 2 and data.shape[0] <= 2:
            data = data.T
        sf.write(str(path), np.asarray(data, dtype="float32"), int(sr))

    torchaudio.load = _load
    torchaudio.save = _save


def _prepare_ref(dest: Path, seconds: float = 60.0) -> Path:
    """Clean reference: kill hiss, drop rumble, level it, take a steady slice."""
    _ff("-i", str(REF_RAW), "-t", str(seconds),
        "-af", "highpass=f=70,afftdn=nf=-25,loudnorm=I=-20:TP=-3:LRA=11",
        "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(dest))
    return dest


def _features_chunked(knn_vc, wav: Path, chunk_s: float = CHUNK_SECONDS):
    import torch
    import torchaudio

    x, sr = torchaudio.load(str(wav))
    step = int(chunk_s * sr)
    feats = []
    for i in range(0, x.shape[1], step):
        seg = x[:, i:i + step]
        if seg.shape[1] < sr:
            break
        feats.append(knn_vc.get_features(seg, vad_trigger_level=0))
    return torch.cat(feats, dim=0)


def run(slug: str, start: float, dur: float, topk: int, air: float, tag: str) -> Path:
    import numpy as np
    import soundfile as sf
    import torch

    _patch_torchaudio()
    work = ROOT / "work" / slug
    stems = work / "stems"
    if not (stems / "vocals.m4a").exists():
        raise SystemExit(f"no stems for {slug}; run fetch_stems.py first")

    seg = work / f"seg-{tag}"
    seg.mkdir(parents=True, exist_ok=True)
    for name in ("vocals", "drums", "bass", "other"):
        _ff("-ss", str(start), "-t", str(dur), "-i", str(stems / f"{name}.m4a"),
            "-ar", "16000" if name == "vocals" else "48000",
            "-ac", "1" if name == "vocals" else "2",
            "-c:a", "pcm_s16le", str(seg / f"{name}.wav"))

    ref = _prepare_ref(seg / "ref-clean.wav")

    print("loading kNN-VC on CPU ...", flush=True)
    knn_vc = torch.hub.load("bshall/knn-vc", "knn_vc", prematched=True,
                            trust_repo=True, pretrained=True, device="cpu")
    matching = _features_chunked(knn_vc, ref)
    query = _features_chunked(knn_vc, seg / "vocals.wav")
    print(f"matching {query.shape[0]} frames, topk={topk}", flush=True)
    out = knn_vc.match(query, matching, topk=topk).detach().cpu().numpy().astype("float32")
    sf.write(str(seg / "vocal-conv.wav"), out, knn_vc.sr)

    # Post: fix the 16 kHz dullness, control dynamics, restore air.
    chain = ("highpass=f=85,"
             "equalizer=f=500:t=q:w=1:g=-3,"
             "equalizer=f=2600:t=q:w=2:g=2.5,"
             "equalizer=f=8000:t=q:w=2:g=4,"
             "acompressor=threshold=-18dB:ratio=3:attack=10:release=150,"
             "loudnorm=I=-16:TP=-1.5:LRA=11")
    _ff("-i", str(seg / "vocal-conv.wav"), "-af", chain, "-ar", "48000",
        "-ac", "1", str(seg / "vocal-post.wav"))

    air_input = ["-i", str(seg / "vocal-post.wav")]
    if air > 0:
        # The source singer's own top band carries the real breath/sibilance the
        # 16 kHz vocoder cannot invent. Blend it under the converted vocal.
        _ff("-i", str(seg / "vocals.wav"), "-af",
            "highpass=f=6500,volume=%.2f" % air, "-ar", "48000", "-ac", "1",
            str(seg / "air.wav"))
        air_input = ["-i", str(seg / "vocal-post.wav"), "-i", str(seg / "air.wav")]

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    mp3 = OUT_DIR / f"{slug}-{tag}.mp3"
    if air > 0:
        fc = ("[0:a][1:a]amix=inputs=2:normalize=0[v];"
              "[2:a][3:a][4:a]amix=inputs=3:normalize=0[i];"
              "[v][i]amix=inputs=2:normalize=0:weights=1 1[m];"
              "[m]loudnorm=I=-15:TP=-1.5:LRA=11[out]")
        ins = ["-i", str(seg / "vocal-post.wav"), "-i", str(seg / "air.wav"),
               "-i", str(seg / "drums.wav"), "-i", str(seg / "bass.wav"),
               "-i", str(seg / "other.wav")]
    else:
        fc = ("[0:a]anull[v];"
              "[1:a][2:a][3:a]amix=inputs=3:normalize=0[i];"
              "[v][i]amix=inputs=2:normalize=0:weights=1 1[m];"
              "[m]loudnorm=I=-15:TP=-1.5:LRA=11[out]")
        ins = ["-i", str(seg / "vocal-post.wav"),
               "-i", str(seg / "drums.wav"), "-i", str(seg / "bass.wav"),
               "-i", str(seg / "other.wav")]
    _ff(*ins, "-filter_complex", fc, "-map", "[out]",
        "-c:a", "libmp3lame", "-q:a", "2", str(mp3))
    PREVIEW.mkdir(parents=True, exist_ok=True)
    import shutil
    shutil.copy2(mp3, PREVIEW / f"v2-{slug}-{tag}.mp3")
    print(f"wrote {mp3}", flush=True)
    return mp3


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("slug")
    ap.add_argument("--start", type=float, default=135.0)
    ap.add_argument("--dur", type=float, default=60.0)
    ap.add_argument("--topk", type=int, default=4)
    ap.add_argument("--air", type=float, default=0.15)
    ap.add_argument("--tag", default="A")
    a = ap.parse_args()
    run(a.slug, a.start, a.dur, a.topk, a.air, a.tag)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
