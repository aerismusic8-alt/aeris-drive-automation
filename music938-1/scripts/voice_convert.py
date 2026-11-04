#!/usr/bin/env python3
"""Re-sing a Flow song in K's voice with kNN-VC, then rebuild the mix.

Flow blocks uploading a *vocal* clip ("vocals must be removed") and has no voice
cloning of its own, so the singer cannot be swapped inside Flow. It does expose
the four stems of every clip though, so the vocal is separated for free. This
script takes that vocal stem, converts it to the target speaker with kNN-VC
(zero-shot: WavLM features + nearest-neighbour match to the reference, vocoded
by HiFi-GAN), and lays it back over the drums+bass+other stems. No training, no
paid API, CPU-only.

    voice-clone/vc-venv/bin/python scripts/voice_convert.py 01-khon-di-thi-chak-pai

Reads   work/<slug>/stems/{vocals,drums,bass,other}.m4a
        voice-inbox/k-voice-16k.wav          (reference, 16 kHz mono)
Writes  library/songs-voice/song-<slug>-kvoice.mp3
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
from pathlib import Path

os.environ.setdefault("TORCH_HOME", "/workspace/ax-tools/torch-cache")

ROOT = Path(__file__).resolve().parent.parent
FFMPEG = "/workspace/ax-tools/bin/ffmpeg"
FFPROBE = "/workspace/ax-tools/bin/ffprobe"
REF = ROOT / "voice-inbox" / "k-voice-16k.wav"
OUT_DIR = ROOT / "library" / "songs-voice"


def _ff(*args):
    subprocess.run([FFMPEG, "-y", "-loglevel", "error", *args], check=True)


def _to_wav16k(src: Path, dst: Path):
    _ff("-i", str(src), "-ar", "16000", "-ac", "1", "-c:a", "pcm_s16le", str(dst))


def _patch_torchaudio():
    """torchaudio 2.11 routes load/save through torchcodec, which is not
    installed and would need FFmpeg libs the pod lacks. soundfile reads the
    16 kHz PCM WAVs this script produces, so use it for both directions."""
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


CHUNK_SECONDS = 15.0
REF_SECONDS = 60.0


def _features_chunked(knn_vc, wav: Path, chunk_s: float = CHUNK_SECONDS):
    """Encode a long waveform in chunks.

    WavLM-large's attention is quadratic in sequence length, so encoding a
    multi-minute clip in one pass needs many GB and OOMs a 15 GB pod. Speaker
    features are local, so per-chunk encoding is a faithful substitute.
    """
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


def convert(slug: str, ref: Path) -> Path:
    import numpy as np
    import torch

    _patch_torchaudio()

    stems = ROOT / "work" / slug / "stems"
    vocal = stems / "vocals.m4a"
    if not vocal.exists():
        raise SystemExit(f"missing vocal stem: {vocal}")
    if not ref.exists():
        raise SystemExit(f"missing reference: {ref}")

    tmp = ROOT / "work" / slug
    _to_wav16k(vocal, tmp / "vocals-16k.wav")
    ref_trim = tmp / "ref-60s.wav"
    _ff("-i", str(ref), "-t", str(REF_SECONDS), "-ar", "16000", "-ac", "1",
        "-c:a", "pcm_s16le", str(ref_trim))

    print("loading kNN-VC (WavLM + HiFi-GAN) on CPU ...", flush=True)
    knn_vc = torch.hub.load("bshall/knn-vc", "knn_vc", prematched=True,
                            trust_repo=True, pretrained=True, device="cpu")

    print("encoding reference ...", flush=True)
    matching = _features_chunked(knn_vc, ref_trim)
    print(f"  matching set: {matching.shape[0]} frames", flush=True)
    print("encoding source vocal ...", flush=True)
    query = _features_chunked(knn_vc, tmp / "vocals-16k.wav")
    print(f"matching {query.shape[0]} frames ...", flush=True)
    out = knn_vc.match(query, matching, topk=4)
    out = out.detach().cpu().numpy().astype("float32")
    conv = tmp / "vocals-kvoice.wav"
    import soundfile as sf
    sf.write(str(conv), out, knn_vc.sr)
    print(f"converted vocal -> {conv} ({out.shape[0] / knn_vc.sr:.1f}s)", flush=True)

    # Lay the converted vocal over the instrumental (drums+bass+other).
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    mp3 = OUT_DIR / f"song-{slug}-kvoice.mp3"
    _ff("-i", str(conv),
        "-i", str(stems / "drums.m4a"),
        "-i", str(stems / "bass.m4a"),
        "-i", str(stems / "other.m4a"),
        "-filter_complex",
        "[0:a]aresample=48000,pan=stereo|c0=c0|c1=c0,volume=1.6[v];"
        "[1:a][2:a][3:a]amix=inputs=3:normalize=0[i];"
        "[v][i]amix=inputs=2:normalize=0:weights=1 1,"
        "alimiter=limit=0.97[out]",
        "-map", "[out]", "-c:a", "libmp3lame", "-q:a", "2", str(mp3))
    return mp3


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("slug")
    ap.add_argument("--ref", default=str(REF))
    a = ap.parse_args()
    mp3 = convert(a.slug, Path(a.ref))
    print(f"wrote {mp3}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
