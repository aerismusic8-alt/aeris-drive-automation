#!/usr/bin/env python3
"""An AI image sequence that loops: N scenes, crossfaded, cut back to the start.

K (2026-11-19): "สร้างวีดีโอ ai เอามาต่อกันวนไปนะ" — AI video, joined, looping.

Why this is images and not generated video. Dreamina's video models are VIP-only
for this account: `node quote` on every t2v and i2v draft answers
`error.code 1, totalMaxCredits 0, confirmable false`, and the i2v path says it
outright — "The selected model or resolution requires VIP membership." The free
Hugging Face image-to-video spaces all answer `ZeroGPU runs limit exceeded`
without a token, and huggingface.co/join is behind a CloudFront challenge. So a
generated-motion clip cannot be made for free right now, and this tool does not
pretend otherwise.

What it does instead, with the one AI image model that *is* free here
(seedream 4.0 through the same credits as the covers): render N scenes that share
one visual language, give each a slow move, crossfade them, and close the last
back onto the first so the file loops with no visible seam.

    python3 ops/ai_loop.py --theme "garage punk, wet concrete, sodium light" \\
        --scenes 4 --seconds 6 --out work/loop.mp4

The clip is gated by `clip_standard` (`motion` profile), so a below-floor render
is deleted rather than published.
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
sys.path.insert(0, str(ROOT / "ops"))

W, H = 832, 480          # the `motion` profile's frame, and cheap to encode
FPS = 16

# Each scene gets a different camera move, so a loop of stills does not read as
# one still. The moves are ffmpeg zoompan expressions, alternating in and out.
# `{n}` is the frame count; x/y need it too, so it is formatted into every field.
MOVES = [
    ("in", "zoom+0.0012", "iw/2-(iw/zoom/2)", "ih/2-(ih/zoom/2)"),
    ("out", "if(eq(on,0),1.28,max(zoom-0.0012,1.0))", "iw/2-(iw/zoom/2)", "ih/2-(ih/zoom/2)"),
    ("right", "1.18", "(iw-iw/zoom)*on/({n}-1)", "ih/2-(ih/zoom/2)"),
    ("left", "1.18", "(iw-iw/zoom)*(1-on/({n}-1))", "ih/2-(ih/zoom/2)"),
]


def _dreamina(prompt: str, out: Path, project: str, ceiling: int = 12) -> Path:
    """One seedream 4.0 still. Reuses the ai_covers backend contract."""
    cli = shutil.which("dreamina") or "/workspace/ax-tools/bin/dreamina"
    if out.exists():
        return out
    out.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        [cli, "node", "create", "image", "--project-id", project,
         "--model", "seedream_4.0", "--mode", "t2i", "--ratio", "16:9",
         "--resolution", "2K", "--title", out.stem[:60], "--prompt", prompt,
         "--run", "--wait", "--credit-ceiling", str(ceiling), "--format", "json"],
        capture_output=True, text=True, timeout=900)
    try:
        doc = json.loads(proc.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"dreamina gave no JSON: {proc.stdout[-200:]}") from exc
    res = (doc.get("data") or {}).get("submission", {}).get("resources") or []
    if not doc.get("ok") or not res:
        raise RuntimeError(f"dreamina image failed: {json.dumps(doc.get('error') or doc)[:250]}")
    subprocess.run([cli, "resource", "download", res[0]["resourceId"],
                    "--project-id", project, "-o", str(out), "--format", "json"],
                   capture_output=True, text=True, timeout=600)
    if not out.exists():
        raise RuntimeError(f"download produced no file for {out}")
    return out


def render(scenes: list[Path], out: Path, seconds: float) -> Path:
    """Crossfade the scenes and close the ring back onto scene 1."""
    per = max(2.0, seconds / len(scenes))
    fade = min(0.9, per * 0.28)
    frames = int(per * FPS)

    args = ["-y"]
    for p in scenes:
        args += ["-loop", "1", "-t", f"{per + fade:.3f}", "-i", str(p)]

    parts = []
    for i in range(len(scenes)):
        name, z, x, y = MOVES[i % len(MOVES)]
        z, x, y = (e.format(n=frames) for e in (z, x, y))
        parts.append(
            f"[{i}:v]scale={W}:{H}:force_original_aspect_ratio=increase,"
            f"crop={W}:{H},setsar=1,"
            f"zoompan=z='{z}':x='{x}':y='{y}':d={frames}:s={W}x{H}:fps={FPS},"
            f"trim=duration={per:.3f},setpts=PTS-STARTPTS[v{i}]")
    # v0 is needed twice — once in the chain, once for the loop seam — so split
    # it; reusing the same pad label makes xfade see the unscaled source.
    parts.append("[v0]split=2[v0a][v0b]")

    # Chain xfades left to right.
    cur = "v0a"
    offset = per - fade
    for i in range(1, len(scenes)):
        nxt = f"x{i}"
        parts.append(f"[{cur}][v{i}]xfade=transition=fade:duration={fade:.3f}:"
                     f"offset={offset:.3f}[{nxt}]")
        cur = nxt
        offset += per - fade
    chain_dur = per + (len(scenes) - 1) * (per - fade)

    # The loop seam. The tail dissolves into scene 1 held at zoom 1.0 — the exact
    # picture frame 0 shows, since zoompan at z=1 is a pass-through — so the last
    # frame equals the first and the file repeats with no jump. Fading into the
    # *moving* v0b instead lands a fraction of a zoom in, which is a visible tick.
    parts.append("[v0b]trim=end_frame=1,loop=loop=-1:size=1:start=0,"
                 f"trim=duration={fade:.3f},setpts=PTS-STARTPTS[head]")
    parts.append(f"[{cur}][head]xfade=transition=fade:duration={fade:.3f}:"
                 f"offset={chain_dur - fade:.3f}[vout]")

    out.parent.mkdir(parents=True, exist_ok=True)
    cmd = (["ffmpeg", *args, "-filter_complex", ";".join(parts), "-map", "[vout]",
            "-c:v", "libx264", "-preset", "medium", "-crf", "20",
            "-pix_fmt", "yuv420p", "-movflags", "+faststart", str(out)])
    proc = subprocess.run(cmd, capture_output=True, text=True)
    if proc.returncode != 0:
        raise RuntimeError(f"ffmpeg failed:\n{proc.stderr[-1200:]}")
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--theme", required=True, help="one sentence of visual language")
    ap.add_argument("--scenes", type=int, default=4)
    ap.add_argument("--seconds", type=float, default=6.0, help="seconds per scene")
    ap.add_argument("--out", default="work/ai-loop.mp4")
    ap.add_argument("--project-id", default=os.environ.get("DREAMINA_PROJECT_ID", ""))
    ap.add_argument("--dry-run", action="store_true", help="print the plan, spend nothing")
    args = ap.parse_args()

    beats = [
        "a wide establishing shot", "a low close detail", "a figure turning away",
        "light breaking across the frame", "an empty room after", "the horizon",
    ]
    prompts = [f"{args.theme}. {beats[i % len(beats)]}, cinematic, no text, no letters"
               for i in range(args.scenes)]

    if args.dry_run:
        for p in prompts:
            print("scene:", p)
        print(f"plan: {args.scenes} scenes x {args.seconds}s, {args.scenes * 8} credits")
        return 0

    if not args.project_id:
        raise SystemExit("--project-id or DREAMINA_PROJECT_ID is required")
    with tempfile.TemporaryDirectory() as td:
        paths = [_dreamina(p, Path(td) / f"scene{i}.png", args.project_id)
                 for i, p in enumerate(prompts)]
        out = Path(args.out)
        render(paths, out, args.seconds)

    import clip_standard
    try:
        clip_standard.assert_ok(str(out), "motion")
    except Exception as exc:
        out.unlink(missing_ok=True)
        raise SystemExit(f"clip below the motion floor, deleted: {exc}") from exc
    print(f"ok: {out} ({args.scenes} scenes, loops)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
