#!/usr/bin/env python3
"""Realistic-sound rendering from real instrument recordings (sfizz sampler).

K (2026-11-09): "the sleep music — what program is it made with? Stop using it.
Find a program that makes realistic sound." It was `fluidsynth` playing a
General-MIDI SoundFont: one thin sample stretched across the range, which reads
as MIDI, not as an instrument. A *sampler* plays multi-velocity recordings of a
real instrument instead, and the free one wired here is sfizz.

sfizz_render (built from source into `tools/sfizz/`) plays an `.sfz` program
whose samples are real recordings:

  * Salamander Grand Piano V3 — a real Yamaha C5, CC0 (Alexander Holm)
  * Sonatina Symphonic Orchestra — CC0 orchestral samples (Mattias Westlund)

Those banks are large (gigabytes), so they live outside the repo under
`/workspace/ax-tools/instruments/` and are located at runtime. When a bank or
the binary is missing the module reports it and the caller keeps the fluidsynth
path, so nothing breaks on a bare pod.

    python3 scripts/sampler.py --list
    python3 scripts/sampler.py --probe
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

ROOT = Path(__file__).resolve().parent.parent

# The vendored sampler binary (gitignored, like tools/luau). ffmpeg/mido come
# from the same durable tree the rest of the pack uses.
_BIN = Path("/workspace/ax-tools/bin")
if (_BIN / "ffmpeg").exists() and str(_BIN) not in os.environ.get("PATH", ""):
    os.environ["PATH"] = str(_BIN) + os.pathsep + os.environ.get("PATH", "")

SFIZZ_CANDIDATES = [
    ROOT / "tools" / "sfizz" / "sfizz_render",
    Path("/workspace/ax-tools/bin/sfizz_render"),
]

# Real recorded instruments, found at runtime. Each is an .sfz program plus its
# sample folder; sfizz resolves the samples relative to the program file.
INSTRUMENT_DIRS = [
    Path("/workspace/ax-tools/instruments"),
]

_SALAMANDER = "salamander/Salamander Grand Piano V3.sfz"
_SSO = "sso/Sonatina Symphonic Orchestra"

# role -> (bank relative to an instrument dir). "sustain"/"legato" programs are
# chosen over staccato/marcato so a held note sounds like a held note.
ROLES: dict[str, list[str]] = {
    "piano": [_SALAMANDER, f"{_SSO}/Grand Piano/Grand Piano.sfz"],
    "harp": [f"{_SSO}/Concert Harp.sfz"],
    "strings": [f"{_SSO}/Strings - Performance/All Strings Sustain.sfz",
                f"{_SSO}/Strings - Notation/All Strings Sustain.sfz"],
    "cello": [f"{_SSO}/Strings - Performance/Celli Sustain.sfz",
              f"{_SSO}/Strings - Notation/Celli Sustain.sfz"],
    "bass": [f"{_SSO}/Strings - Performance/Basses KS.sfz",
             f"{_SSO}/Strings - Notation/Basses KS.sfz"],
    "flute": [f"{_SSO}/Woodwinds - Performance/Flute Solo 1 Sustain.sfz",
              f"{_SSO}/Woodwinds - Notation/Flute Solo 1 Sustain.sfz"],
    "clarinet": [f"{_SSO}/Woodwinds - Performance/Clarinet Solo Sustain.sfz",
                 f"{_SSO}/Woodwinds - Notation/Clarinet Solo Sustain.sfz"],
}


def sfizz_bin() -> Path | None:
    for p in SFIZZ_CANDIDATES:
        if p.exists():
            return p
    return shutil.which("sfizz_render") and Path(shutil.which("sfizz_render"))


def find_program(role: str) -> Path | None:
    """Return the first existing .sfz for a role, or None."""
    for rel in ROLES.get(role, []):
        for base in INSTRUMENT_DIRS:
            p = base / rel
            if p.exists():
                return p
    return None


def available() -> bool:
    """True when the binary and at least one real bank are present."""
    return sfizz_bin() is not None and any(find_program(r) for r in ROLES)


def render(midi: Path, out_wav: Path, program: Path, *,
           samplerate: int = 44100, gain: float = 1.0) -> None:
    """Render `midi` through the real-instrument `program` to `out_wav`."""
    bin_ = sfizz_bin()
    if bin_ is None:
        raise FileNotFoundError(
            "sfizz_render not found; build it with scripts/install-sfizz.sh")
    with tempfile.NamedTemporaryFile(suffix=".wav", delete=False) as tf:
        raw = Path(tf.name)
    try:
        res = subprocess.run(
            [str(bin_), "--sfz", str(program), "--midi", str(midi),
             "--wav", str(raw), "--samplerate", str(samplerate),
             "--quality", "3", "--use-eot"],
            capture_output=True, text=True)
        if res.returncode != 0 or not raw.exists() or raw.stat().st_size == 0:
            raise RuntimeError(f"sfizz_render failed: {res.stderr.strip()[-600:]}")
        # sfizz writes at full scale; apply the caller's gain in the same pass
        # the rest of the pack uses for level, keeping one loudness path.
        af = f"volume={gain:.3f}" if gain != 1.0 else "anull"
        ff = subprocess.run(
            ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error", "-i", str(raw),
             "-af", f"{af},aresample={samplerate}", "-c:a", "pcm_s16le",
             str(out_wav)], capture_output=True, text=True)
        if ff.returncode != 0 or not out_wav.exists():
            raise RuntimeError(f"sampler master failed: {ff.stderr.strip()[-600:]}")
    finally:
        raw.unlink(missing_ok=True)


def _channels_of(midi: Path) -> list[int]:
    import mido
    chans = set()
    for msg in mido.MidiFile(str(midi)):
        if msg.type in ("note_on", "note_off"):
            chans.add(msg.channel)
    return sorted(chans)


def render_multichannel(midi: Path, out_wav: Path,
                        channel_roles: dict[int, str], *,
                        samplerate: int = 44100,
                        gains: dict[int, float] | None = None) -> dict:
    """Render each MIDI channel through its own real instrument and mix.

    The bed MIDI carries melody/harp/bass/arp on separate channels, each with a
    General-MIDI program. A sampler plays one program at a time, so the channels
    are split, rendered through their own `.sfz`, and summed with ffmpeg. A
    channel whose role has no bank is skipped and reported, never silently
    substituted.
    """
    import mido

    gains = gains or {}
    src = mido.MidiFile(str(midi))
    present = _channels_of(midi)
    parts: list[Path] = []
    rendered: dict[str, int] = {}
    missing: dict[str, int] = {}
    tmp = Path(tempfile.mkdtemp(prefix="sampler-"))
    try:
        for ch in present:
            role = channel_roles.get(ch)
            program = find_program(role) if role else None
            if program is None:
                missing[role or f"ch{ch}"] = ch
                continue
            one = mido.MidiFile(ticks_per_beat=src.ticks_per_beat)
            track = mido.MidiTrack()
            one.tracks.append(track)
            for msg in src.tracks[0]:
                if getattr(msg, "channel", ch) == ch or msg.is_meta:
                    track.append(msg.copy())
            m = tmp / f"ch{ch}.mid"
            one.save(str(m))
            w = tmp / f"ch{ch}.wav"
            render(m, w, program, samplerate=samplerate,
                   gain=gains.get(ch, 1.0))
            parts.append(w)
            rendered[role] = ch
        if not parts:
            raise RuntimeError(
                f"no real instrument available for {channel_roles} "
                f"(missing: {missing})")
        if len(parts) == 1:
            shutil.copy(parts[0], out_wav)
        else:
            cmd = ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error"]
            for w in parts:
                cmd += ["-i", str(w)]
            cmd += ["-filter_complex",
                    "".join(f"[{i}:a]" for i in range(len(parts)))
                    + f"amix=inputs={len(parts)}:normalize=0[a]",
                    "-map", "[a]", "-c:a", "pcm_s16le", str(out_wav)]
            ff = subprocess.run(cmd, capture_output=True, text=True)
            if ff.returncode != 0:
                raise RuntimeError(f"mix failed: {ff.stderr.strip()[-600:]}")
        return {"rendered": rendered, "missing": missing,
                "programs": {r: str(find_program(r)) for r in rendered}}
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--list", action="store_true", help="show the roles and banks")
    ap.add_argument("--probe", action="store_true",
                    help="check the binary and render one note per role")
    args = ap.parse_args()

    if args.list or not (args.list or args.probe):
        print(f"sfizz_render: {sfizz_bin() or 'MISSING'}")
        for role in ROLES:
            p = find_program(role)
            print(f"  {role:9} {'ok ' if p else 'MISSING'} {p or ''}")
        print(f"available: {available()}")
        return 0

    if args.probe:
        import mido
        bin_ = sfizz_bin()
        if bin_ is None:
            print("sfizz_render MISSING — run scripts/install-sfizz.sh")
            return 1
        out = []
        for role in ROLES:
            p = find_program(role)
            if not p:
                out.append({"role": role, "ok": False, "why": "no bank"})
                continue
            tmp = Path(tempfile.mkdtemp(prefix="probe-"))
            try:
                m = mido.MidiFile()
                t = mido.MidiTrack()
                m.tracks.append(t)
                t.append(mido.Message("note_on", note=60, velocity=70, time=0))
                t.append(mido.Message("note_off", note=60, velocity=0, time=960))
                mp = tmp / "n.mid"
                m.save(str(mp))
                wp = tmp / "n.wav"
                render(mp, wp, p)
                out.append({"role": role, "ok": wp.stat().st_size > 0,
                            "bytes": wp.stat().st_size})
            except Exception as e:  # noqa: BLE001
                out.append({"role": role, "ok": False, "why": str(e)[:120]})
            finally:
                shutil.rmtree(tmp, ignore_errors=True)
        print(json.dumps(out, ensure_ascii=False, indent=1))
        return 0 if all(o["ok"] for o in out) else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
