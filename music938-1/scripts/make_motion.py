#!/usr/bin/env python3
"""Turn a song's cover art into real motion with a free image-to-video model.

K (2026-11-13): "ภาพวีดีโอ การเคลื่อนไหว ให้คะแนน -10/10" and "หาโปรแกรมมาสร้าง
video gen อย่างน้อยๆ ใช้ฟรี gen ได้วันละคลิปก็ได้ หาหลายๆ โปรแกรม".

Why this exists. Every Short so far was one still cover on a slow zoom — measured
at 0.79 mean abs frame diff, i.e. barely moving — and the fallback synthesised
motion (a pan, a zoom) cannot invent the thing that makes a clip feel alive: real
parallax, drifting hair, moving light. A free image-to-video model can. We already
own the cover art, so the cheapest honest step is to animate the art we have.

Rule #1: every backend here is a public Hugging Face Space — free, no API key, no
login, no credit card. A Space that answers "ZeroGPU quota exceeded" is skipped,
not paid for; that is why there is a list of them and not one.

    python3 scripts/make_motion.py --list
    python3 scripts/make_motion.py 01-khon-di-thi-chak-pai
    python3 scripts/make_motion.py 01-khon-di-thi-chak-pai --backend wan777
    python3 scripts/make_motion.py --all

The output is a silent 3-4 s clip in `library/motion/`. `make_short.py` does not
use it yet; this rail only produces the raw motion so it can be reviewed and
scored before it is wired into the Short.
"""
from __future__ import annotations

import argparse
import os
import shutil
import sys
import tempfile
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
COVERS = ROOT / "library" / "covers"
OUT_DIR = ROOT / "library" / "motion"

# The motion prompt matters more than the model. A neutral prompt ("make this
# come alive") produced 0.77 mean abs frame diff; a prompt that names the moving
# elements produced 8.33 — a 10x difference from wording alone. So the default is
# the explicit one, and every clause is a thing the model can actually animate.
MOTION_PROMPT = (
    "cinematic camera push in, dramatic slow zoom, wind moving hair and clothes, "
    "floating particles and dust, dynamic lighting shifts, strong parallax, "
    "photorealistic motion, smooth"
)

# Free image-to-video backends, tried in order. Each entry is
# (name, space_id, call style). `style` selects the argument shape, because the
# two common Gradio front-ends take different names for the same picture.
# A backend that is down or out of ZeroGPU quota raises, and the next one runs.
BACKENDS: list[tuple[str, str, str]] = [
    # Wan 2.2 image-to-video. ZeroGPU, but it served three calls in a row with no
    # token on 2026-11-13, so it is first.
    ("wan777", "kulkas2pintu/wan777", "start_end"),
    # A second Wan 2.2 host, for when the first is busy.
    ("wan222", "kulkas2pintu/wan222", "start_end"),
    # First-last-frame variant: same art at both ends, so the motion is a loop.
    ("flf", "multimodalart/wan-2-2-first-last-frame", "first_last"),
    ("wan555", "Rchoks/wan555", "start_end"),
    ("wanlite", "Saravutw/WAN2.2_I2V_LIGHTNING_4-8step_custom", "start_end"),
]


def _cover(slug: str) -> Path:
    p = COVERS / f"cover-{slug}.jpg"
    if not p.exists():
        raise SystemExit(f"no cover for {slug}: {p}")
    return p


def _generate(backend: tuple[str, str, str], cover: Path, out: Path,
              prompt: str) -> None:
    from gradio_client import Client, handle_file

    name, space, style = backend
    client = Client(space, verbose=False)
    if style == "first_last":
        res = client.predict(
            start_image_pil=handle_file(str(cover)),
            end_image_pil=handle_file(str(cover)),
            prompt=prompt,
            duration_seconds=2.1,
            steps=8,
            api_name="/generate_video",
        )
    else:
        res = client.predict(
            input_image=handle_file(str(cover)),
            last_image=handle_file(str(cover)),
            prompt=prompt,
            steps=4,
            duration_seconds=3.5,
            api_name="/generate_video",
        )
    vid = res[0] if isinstance(res, (list, tuple)) else res
    if isinstance(vid, dict):
        vid = vid.get("video") or vid.get("path")
    if not vid or not os.path.exists(str(vid)):
        raise RuntimeError(f"{name}: no video in result {str(res)[:200]}")
    shutil.copy(str(vid), out)


def build(slug: str, *, backend: str | None = None, prompt: str | None = None,
          force: bool = False) -> dict:
    cover = _cover(slug)
    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / f"motion-{slug}.mp4"
    if out.exists() and not force:
        return {"slug": slug, "path": str(out), "backend": "cached"}

    order = BACKENDS
    if backend:
        order = [b for b in BACKENDS if b[0] == backend]
        if not order:
            raise SystemExit(f"unknown backend {backend!r}; --list to see them")

    prompt = prompt or MOTION_PROMPT
    errors: list[str] = []
    for b in order:
        name = b[0]
        tmp = Path(tempfile.mkdtemp()) / f"{name}.mp4"
        try:
            print(f"  {slug}: trying {name} ({b[1]}) ...", flush=True)
            _generate(b, cover, tmp, prompt)
            out.write_bytes(tmp.read_bytes())
            return {"slug": slug, "path": str(out), "backend": name,
                    "bytes": out.stat().st_size}
        except Exception as e:  # noqa: BLE001 - any backend failure falls through
            msg = f"{name}: {type(e).__name__}: {str(e)[:160]}"
            print(f"    {msg}", flush=True)
            errors.append(msg)
            time.sleep(2)
    raise SystemExit("every backend failed:\n  " + "\n  ".join(errors))


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("slug", nargs="?", help="song slug, e.g. 01-khon-di-thi-chak-pai")
    ap.add_argument("--all", action="store_true", help="every song with a cover")
    ap.add_argument("--backend", help="force one backend by name")
    ap.add_argument("--prompt", help="override the motion prompt")
    ap.add_argument("--force", action="store_true", help="redo even if cached")
    ap.add_argument("--list", action="store_true", help="list the free backends")
    args = ap.parse_args()

    if args.list:
        for name, space, style in BACKENDS:
            print(f"  {name:10s} {space:45s} {style}")
        return 0

    if args.all:
        slugs = sorted(p.name[len("cover-"):-len(".jpg")]
                       for p in COVERS.glob("cover-*.jpg"))
    elif args.slug:
        slugs = [args.slug]
    else:
        ap.error("give a slug or --all")

    for slug in slugs:
        try:
            info = build(slug, backend=args.backend, prompt=args.prompt,
                         force=args.force)
            print(f"{slug}: {info['path']} ({info.get('backend')})")
        except SystemExit as e:
            print(f"{slug}: FAILED {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
