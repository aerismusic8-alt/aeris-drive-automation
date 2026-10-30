#!/usr/bin/env python3
"""Audio QC that answers the question K actually cares about.

K's rule: the SOUND is what holds a viewer. So the checks here are about the voice
being intelligible and never buried, not about how pretty the pictures are.

  python3 ops/ax_audio_qc.py <file>            # loudness, silence, speech/bed balance
  python3 ops/ax_audio_qc.py --duck <mix> <narration> <music>

Every number printed is measured with ffmpeg. Nothing is inferred.
"""
import json
import os
import re
import subprocess
import sys

import imageio_ffmpeg

FF = imageio_ffmpeg.get_ffmpeg_exe()


def duration(path):
    err = subprocess.run([FF, "-hide_banner", "-i", path],
                         capture_output=True, text=True).stderr
    m = re.search(r"Duration: (\d+):(\d+):(\d+\.?\d*)", err)
    if not m:
        raise RuntimeError(f"no duration for {path}")
    return int(m.group(1)) * 3600 + int(m.group(2)) * 60 + float(m.group(3))


def loudness(path, start=None, dur=None):
    """Integrated LUFS. Uses the LAST 'Integrated loudness:' block only."""
    args = [FF, "-hide_banner"]
    if start is not None:
        args += ["-ss", str(start)]
    args += ["-i", path]
    if dur is not None:
        args += ["-t", str(dur)]
    args += ["-af", "ebur128=peak=true", "-f", "null", "-"]
    err = subprocess.run(args, capture_output=True, text=True).stderr
    tail = err.split("Integrated loudness:")[-1]
    i = re.search(r"I:\s*(-?\d+\.?\d*)\s*LUFS", tail)
    l = re.search(r"LRA:\s*(-?\d+\.?\d*)\s*LU", tail)
    return (float(i.group(1)) if i else None,
            float(l.group(1)) if l else None)


def true_peak(path):
    err = subprocess.run([FF, "-hide_banner", "-i", path, "-af", "ebur128=peak=true",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    m = re.findall(r"Peak:\s*(-?\d+\.?\d*)\s*dBFS", err.split("Integrated loudness:")[-1])
    return float(m[-1]) if m else None


def silence_events(path, noise="-45dB", min_dur=1.2):
    err = subprocess.run([FF, "-hide_banner", "-i", path,
                          "-af", f"silencedetect=noise={noise}:d={min_dur}",
                          "-f", "null", "-"], capture_output=True, text=True).stderr
    return [round(float(m), 2) for m in re.findall(r"silence_duration:\s*(\d+\.?\d*)", err)]


def speech_windows(narration, window=2.0, min_lufs=-32.0):
    """Find windows that actually contain speech, by loudness, not by guesswork."""
    total = duration(narration)
    out = []
    t = 0.0
    while t + window <= total:
        l, _ = loudness(narration, start=t, dur=window)
        if l is not None and l > min_lufs:
            out.append((t, l))
        t += window
    return out


def duck_report(mix, narration, music, samples=14, window=2.0):
    """Prove the bed moves down under the voice.

    For each speech window we measure the narration alone, the raw music bed
    alone, and the final mix. If ducking works the mix sits close to the
    narration (voice on top) instead of splitting the difference.
    """
    total = duration(narration)
    wins = speech_windows(narration, window=window)
    if not wins:
        print("no speech windows detected")
        return None
    step = max(1, len(wins) // samples)
    picks = wins[::step][:samples]
    rows = []
    for t, nl in picks:
        ml, _ = loudness(music, start=t % max(duration(music) - window, 1), dur=window)
        xl, _ = loudness(mix, start=t, dur=window)
        rows.append((t, nl, ml, xl))
    print(f"{'t(s)':>7} {'voice':>7} {'bed':>7} {'mix':>7} {'mix-voice':>10}")
    for t, nl, ml, xl in rows:
        d = f"{xl - nl:+.1f}" if (xl is not None and nl is not None) else "n/a"
        print(f"{t:7.1f} {nl:7.1f} {ml if ml is not None else float('nan'):7.1f} "
              f"{xl if xl is not None else float('nan'):7.1f} {d:>10}")
    vs = [r[1] for r in rows]
    xs = [r[3] for r in rows if r[3] is not None]
    print(f"\nvoice mean {sum(vs)/len(vs):.1f} LUFS | mix mean {sum(xs)/len(xs):.1f} LUFS | "
          f"voice-to-mix offset {sum(xs)/len(xs) - sum(vs)/len(vs):+.1f} dB")
    return rows


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        return
    if a[0] == "--duck":
        duck_report(a[1], a[2], a[3])
        return
    path = a[0]
    l, lra = loudness(path)
    print(json.dumps({
        "file": os.path.basename(path),
        "seconds": round(duration(path), 1),
        "integrated_lufs": l,
        "lra_lu": lra,
        "true_peak_dbfs": true_peak(path),
        "silence_events_gt_1.2s": silence_events(path),
    }, ensure_ascii=False, indent=2))


if __name__ == "__main__":
    main()
