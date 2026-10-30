#!/usr/bin/env python3
"""Thai narration via edge-tts with the retry the service requires.

edge-tts intermittently returns NoAudioReceived for perfectly valid text, so every
synthesis is retried. Measured on 2026-10-24: 301 Thai chars -> 22.1 s at rate -8%,
i.e. ~13.6 chars/s. Use that to size a script for a target runtime.
"""
import asyncio
import os
import subprocess
import time

import edge_tts

VOICE_MALE = "th-TH-NiwatNeural"
VOICE_FEMALE = "th-TH-PremwadeeNeural"
# edge-tts offers only these two Thai voices.
VOICES = (VOICE_MALE, VOICE_FEMALE)
CHARS_PER_SECOND = 13.6


def _ffmpeg():
    import imageio_ffmpeg
    return imageio_ffmpeg.get_ffmpeg_exe()


def audio_seconds(path):
    out = subprocess.run([_ffmpeg(), "-hide_banner", "-i", path],
                         capture_output=True, text=True).stderr
    for line in out.splitlines():
        if "Duration:" in line:
            hms = line.split("Duration:")[1].split(",")[0].strip()
            h, m, s = hms.split(":")
            return int(h) * 3600 + int(m) * 60 + float(s)
    raise RuntimeError(f"no duration for {path}")


async def _synth(text, voice, out, rate):
    await edge_tts.Communicate(text, voice, rate=rate).save(out)


def synth(text, out, voice=VOICE_MALE, rate="-8%", tries=5):
    """Synthesise one paragraph. Returns (path, seconds). Raises if every try fails."""
    text = text.strip()
    if not text:
        raise ValueError("empty text")
    last = None
    for i in range(tries):
        try:
            asyncio.run(_synth(text, voice, out, rate))
            if os.path.getsize(out) > 1200:
                return out, audio_seconds(out)
            last = "file too small"
        except Exception as e:  # NoAudioReceived and friends are transient
            last = f"{type(e).__name__}: {e}"
        time.sleep(2 + 3 * i)
    raise RuntimeError(f"edge-tts failed after {tries} tries: {last}")


def split_paragraphs(script_text):
    """Scripts use a blank line between paragraphs; '#' lines are comments."""
    body = "\n".join(l for l in script_text.splitlines() if not l.lstrip().startswith("#"))
    return [p.strip().replace("\n", " ") for p in body.split("\n\n") if p.strip()]


def read_script(path):
    """Returns (title, [paragraphs]). A '# TITLE:' line decides the title."""
    raw = open(path, encoding="utf-8").read()
    title = None
    for line in raw.splitlines():
        s = line.strip()
        if s.upper().startswith("# TITLE:"):
            title = s.split(":", 1)[1].strip()
            break
    return title, split_paragraphs(raw)
