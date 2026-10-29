#!/usr/bin/env bash
# One-shot environment setup for the music938-1 song pipeline.
#
# Everything here is free and offline-capable: ffmpeg for audio, a Piper Thai
# voice model for the vocal, and a handful of Python packages for phonemisation
# and imaging. Run once per fresh sandbox.
set -u

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MODEL_DIR="/workspace/ax-tools/music938-models"
MODEL_BASE="https://huggingface.co/rhasspy/piper-voices/resolve/main/th/th_TH/tsync2/medium"
VOICE="th_TH-tsync2-medium"

echo "== apt packages =="
if ! command -v ffmpeg >/dev/null 2>&1; then
  sudo apt-get update -qq && sudo apt-get install -y -qq ffmpeg
fi
# espeak-ng is a piper runtime dependency for non-Thai phonemes.
sudo apt-get install -y -qq espeak-ng fonts-noto-core >/dev/null 2>&1 || true
command -v ffmpeg >/dev/null || { echo "ffmpeg missing" >&2; exit 1; }

echo "== python packages =="
python3 -m pip install -q --user \
  piper-tts numpy pillow pythainlp python-crfsuite tltk==1.11 \
  pandas unicode-rbnf nltk scikit-learn sklearn-crfsuite gensim requests

echo "== piper Thai voice =="
mkdir -p "$MODEL_DIR"
if [ ! -s "$MODEL_DIR/$VOICE.onnx" ]; then
  curl -sL -o "$MODEL_DIR/$VOICE.onnx" "$MODEL_BASE/$VOICE.onnx"
  curl -sL -o "$MODEL_DIR/$VOICE.onnx.json" "$MODEL_BASE/$VOICE.onnx.json"
fi
ls -la "$MODEL_DIR"

echo "== verify =="
python3 - "$MODEL_DIR/$VOICE.onnx" <<'PY'
import sys, wave, io
from piper import PiperVoice
v = PiperVoice.load(sys.argv[1])
buf = io.BytesIO()
with wave.open(buf, "wb") as wf:
    v.synthesize_wav("ทดสอบเสียง", wf)
print("piper ok, bytes:", len(buf.getvalue()))
PY
echo "setup complete"
