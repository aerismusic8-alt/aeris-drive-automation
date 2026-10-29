"""Thai speech synthesis with Piper, cached per syllable.

The song engine needs one sung syllable per note, so the unit of synthesis is the
syllable, not the line. Piper is offline and deterministic, which matters twice:
a rebuild produces identical audio, and a syllable only has to be synthesised
once no matter how many songs use it.

Piper's Thai voice needs `tltk` for phonemisation; that dependency is heavy but
it is what turns Thai script into the IPA the voice model was trained on.
"""
from __future__ import annotations

import hashlib
import re
import wave
from pathlib import Path

import numpy as np

from common import CACHE, SR, run

# The voice is a 63 MB ONNX model kept outside the repo (like tools/), because it
# is a binary and is fetched, not committed.
MODEL_DIR = Path("/workspace/ax-tools/music938-models")
MODEL = MODEL_DIR / "th_TH-tsync2-medium.onnx"

_voice = None
_VOICE_SR = 22050

# Thai combining marks: a base consonant plus any tone marks / vowels that ride
# on it. Splitting must never separate a mark from its base.
_COMBINING = re.compile(r"[\u0E31\u0E34-\u0E3A\u0E47-\u0E4E]")


def _clean(syllable: str) -> str:
    return syllable.strip()


# --- syllable segmentation -------------------------------------------------

_speak_cache: dict[str, bool] = {}


def is_speakable(text: str) -> bool:
    """True when Piper's Thai voice has phonemes for this text.

    Piper is the authority here: a string it cannot phonemise would render as
    silence, and a silent syllable is a hole in the song.
    """
    text = text.strip()
    if not text:
        return False
    if text not in _speak_cache:
        import logging
        logging.getLogger("piper").setLevel(logging.ERROR)
        try:
            _speak_cache[text] = bool(_voice_obj().phonemize(text))
        except Exception:
            _speak_cache[text] = False
    return _speak_cache[text]


def syllabify(word: str) -> list[str]:
    """Split a Thai word into syllables that are all actually speakable.

    pythainlp's syllable tokenizer is a statistical model and sometimes splits
    inside a vowel cluster, e.g. `เปียกชื้น` -> `เปี|ยก|ชื้น`, where `เปี` has no
    phonemes. When a part is unspeakable, merge it with following parts until the
    result speaks, or failing that attach it to the previous syllable.
    """
    from pythainlp.tokenize import syllable_tokenize
    parts = [p for p in syllable_tokenize(word) if p.strip()]
    out: list[str] = []
    i = 0
    while i < len(parts):
        part = parts[i]
        if is_speakable(part):
            out.append(part)
            i += 1
            continue
        merged = False
        for j in range(i + 2, len(parts) + 1):
            cand = "".join(parts[i:j])
            if is_speakable(cand):
                out.append(cand)
                i = j
                merged = True
                break
        if merged:
            continue
        if out and is_speakable(out[-1] + part):
            out[-1] = out[-1] + part
            i += 1
            continue
        # Nothing speaks; keep the part so the line length is still correct.
        out.append(part)
        i += 1
    return out


def cache_key(syllable: str) -> str:
    return hashlib.sha1(syllable.encode("utf-8")).hexdigest()[:16]


def _voice_obj():
    global _voice, _VOICE_SR
    if _voice is None:
        from piper import PiperVoice
        if not MODEL.exists():
            raise FileNotFoundError(
                f"Piper Thai voice missing at {MODEL}. Run scripts/setup-env.sh.")
        _voice = PiperVoice.load(str(MODEL))
        _VOICE_SR = int(_voice.config.sample_rate)
    return _voice


def _trim(x: np.ndarray, thresh: float = 0.012, pad_ms: int = 12) -> np.ndarray:
    """Drop leading/trailing silence so a syllable's length is its voiced length."""
    if x.size == 0:
        return x
    energy = np.abs(x)
    idx = np.where(energy > thresh)[0]
    if idx.size == 0:
        return x
    pad = int(_VOICE_SR * pad_ms / 1000)
    a = max(0, idx[0] - pad)
    b = min(len(x), idx[-1] + pad)
    return x[a:b]


def synth_syllable(syllable: str, *, force: bool = False) -> Path:
    """Synthesise one syllable to a mono WAV, cached by its text."""
    syllable = _clean(syllable)
    if not syllable:
        raise ValueError("empty syllable")
    CACHE.mkdir(parents=True, exist_ok=True)
    out = CACHE / f"{cache_key(syllable)}.wav"
    if out.exists() and out.stat().st_size > 0 and not force:
        return out

    voice = _voice_obj()
    chunks = list(voice.synthesize(syllable))
    if not chunks:
        raise RuntimeError(f"piper produced no audio for {syllable!r}")
    audio = np.concatenate([np.asarray(c.audio_float_array, dtype=np.float32)
                            for c in chunks])
    audio = _trim(audio)
    pcm = np.clip(audio, -1.0, 1.0)
    pcm16 = (pcm * 32767.0).astype("<i2")

    tmp = out.with_suffix(".tmp.wav")
    with wave.open(str(tmp), "wb") as wf:
        wf.setnchannels(1)
        wf.setsampwidth(2)
        wf.setframerate(_VOICE_SR)
        wf.writeframes(pcm16.tobytes())
    tmp.replace(out)
    return out


def voiced_seconds(syllable: str) -> float:
    p = synth_syllable(syllable)
    with wave.open(str(p)) as wf:
        return wf.getnframes() / wf.getframerate()


def sample_rate() -> int:
    _voice_obj()
    return _VOICE_SR
