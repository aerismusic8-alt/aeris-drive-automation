#!/usr/bin/env python3
"""Audio-first episode rail.

K's rule (2026-10-24): retention is won by the SOUND. People used to leave a radio
on all day just for the DJ's voice. So the narration is the product; stills are
support. This module builds the audio bed first and only then lays pictures on it.

Audio chain, in order:
  1. one TTS file per paragraph, then concatenate with a pause between paragraphs
  2. loudnorm the whole narration to EBU R128 -16 LUFS (measured, not assumed)
  3. music bed looped to the exact narration length, ducked under the voice with
     sidechaincompress, so the voice is never fighting the music
  4. final mix loudnorm again and measured back with ebur128

Nothing here claims a result it did not measure.
"""
import json
import os
import re
import subprocess

import imageio_ffmpeg

import thai_tts

FF = imageio_ffmpeg.get_ffmpeg_exe()
TARGET_LUFS = -16.0


def run(args, capture=True):
    p = subprocess.run([FF, "-hide_banner", "-y"] + args,
                       capture_output=True, text=True)
    if p.returncode != 0:
        raise RuntimeError(f"ffmpeg failed: {' '.join(args[:6])}...\n{p.stderr[-1500:]}")
    return p.stderr if capture else ""


def measure_lufs(path):
    """Integrated loudness from the FINAL 'Integrated loudness:' block only.

    ebur128 prints one summary block per pass; reading an earlier one gives a
    wrong number.
    """
    err = subprocess.run([FF, "-hide_banner", "-i", path, "-af", "ebur128=peak=true",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    blocks = err.split("Integrated loudness:")
    if len(blocks) < 2:
        return None, None
    tail = blocks[-1]
    lufs = re.search(r"I:\s*(-?\d+\.?\d*)\s*LUFS", tail)
    lra = re.search(r"LRA:\s*(-?\d+\.?\d*)\s*LU", tail)
    return (float(lufs.group(1)) if lufs else None,
            float(lra.group(1)) if lra else None)


def measure_silence(path, noise="-45dB", min_dur=1.2):
    err = subprocess.run([FF, "-hide_banner", "-i", path,
                          "-af", f"silencedetect=noise={noise}:d={min_dur}",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    return [float(m) for m in re.findall(r"silence_duration:\s*(\d+\.?\d*)", err)]


def build_narration(paragraphs, out_dir, voice=thai_tts.VOICE_MALE, rate="-8%",
                    gap=0.9, log=print):
    """Synthesise each paragraph and join them with a real pause.

    A pause is inserted as generated silence, not as trailing dead air inside a
    clip, so the rhythm is identical from paragraph to paragraph.
    """
    os.makedirs(out_dir, exist_ok=True)
    parts, total = [], 0.0
    for i, para in enumerate(paragraphs):
        p = os.path.join(out_dir, f"p{i:03d}.mp3")
        if not (os.path.exists(p) and os.path.getsize(p) > 1200):
            _, secs = thai_tts.synth(para, p, voice=voice, rate=rate)
            log(f"  tts p{i:03d}: {secs:6.1f}s  {para[:44]!r}")
        else:
            secs = thai_tts.audio_seconds(p)
            log(f"  tts p{i:03d}: cached {secs:6.1f}s")
        parts.append(p)
        total += secs + gap

    silence = os.path.join(out_dir, "_gap.mp3")
    run(["-f", "lavfi", "-i", f"anullsrc=r=24000:cl=mono", "-t", str(gap),
         "-c:a", "libmp3lame", "-b:a", "96k", silence])

    concat_txt = os.path.join(out_dir, "narration_concat.txt")
    with open(concat_txt, "w", encoding="utf-8") as f:
        for i, p in enumerate(parts):
            f.write(f"file '{os.path.abspath(p)}'\n")
            if i != len(parts) - 1:
                f.write(f"file '{os.path.abspath(silence)}'\n")

    raw = os.path.join(out_dir, "narration_raw.m4a")
    run(["-f", "concat", "-safe", "0", "-i", concat_txt,
         "-c:a", "aac", "-b:a", "160k", raw])
    return raw, thai_tts.audio_seconds(raw), total


def normalize(path, out, target=TARGET_LUFS):
    run(["-i", path, "-af", f"loudnorm=I={target}:TP=-1.5:LRA=11",
         "-c:a", "aac", "-b:a", "192k", out])
    return out


def loop_to_length(music, dur, out, xfade=4.0, log=print):
    """Loop a short track up to `dur` without an audible seam.

    Our CC0 tracks are 40-90 s; a 12-minute episode repeats them many times. A
    hard loop point is audible, so each repeat is crossfaded into the next with
    acrossfade instead of being cut.

    Note: acrossfade shortens the result by one xfade per join, so the number of
    repeats is computed from (dur + n*xfade) rather than from dur alone.
    """
    src = thai_tts.audio_seconds(music)
    stride = src - xfade
    repeats = max(1, int((dur - src) / stride) + 1) if dur > src else 1
    if repeats == 1:
        run(["-i", music, "-t", str(dur), "-c:a", "aac", "-b:a", "192k", out])
        log(f"  bed loop: single pass of {src:.1f}s")
        return out
    args = ["-i", music] * repeats
    parts, prev = [], "[0:a]"
    for i in range(1, repeats):
        outl = f"[x{i}]"
        parts.append(f"{prev}[{i}:a]acrossfade=d={xfade}:c1=tri:c2=tri{outl}")
        prev = outl
    filt = ";".join(parts) + f";{prev}atrim=0:{dur}[bed]"
    run(args + ["-filter_complex", filt, "-map", "[bed]",
               "-c:a", "aac", "-b:a", "192k", out])
    log(f"  bed loop: {repeats} passes of {src:.1f}s, xfade {xfade}s")
    return out


def build_bed(narration, music, out, gain=0.34, duck_ratio=8, threshold=0.05,
              work_dir=None, log=print):
    """Lay the music under the narration and duck it with the voice as the key.

    `gain` is set so the music at its FULL level still sits several dB under the
    narration. Measured on 2026-10-24: at gain 0.9 the unducked bed reached
    -14.8 LUFS while the voice sat at -16.8, so every pause jumped louder than
    the speech. Voice-first means the bed must never win, even in the gaps.
    """
    dur = thai_tts.audio_seconds(narration)
    work_dir = work_dir or os.path.dirname(os.path.abspath(out))
    bed = os.path.join(work_dir, "bed_looped.m4a")
    loop_to_length(music, dur, bed, log=log)

    filt = (
        f"[1:a]volume={gain}[g];"
        f"[g][0:a]sidechaincompress=threshold={threshold}:ratio={duck_ratio}"
        f":attack=5:release=400:makeup=1[ducked];"
        f"[0:a][ducked]amix=inputs=2:duration=first:dropout_transition=0:normalize=0[mix]"
    )
    run(["-i", narration, "-i", bed, "-filter_complex", filt, "-map", "[mix]",
         "-t", str(dur), "-c:a", "aac", "-b:a", "192k", out])
    log(f"  bed built: {dur:.1f}s from {os.path.basename(music)} at gain {gain}")
    return out


def sidecar(path, **kw):
    """Write a JSON sidecar next to a deliverable. Never claim what is not in here."""
    p = path + ".json"
    with open(p, "w", encoding="utf-8") as f:
        json.dump(kw, f, ensure_ascii=False, indent=2)
    return p
