#!/usr/bin/env python3
"""Where the picture library and the finished-video shelf live, and how to find
them again when the preferred place is gone.

K (2026-11-20): the picture library sits on PC1's D: drive, and if that
connection drops and the library cannot be reached, a new library must be made
so clip work never stops. Finished videos wait on a separate shelf from the
published material.

D: is not mountable from the sandbox (the only channel into PC1 is a workflow
run), so this resolver is a *ladder*, not a single path: it takes the first
candidate that is writable, creates it if it does not exist, and records the
choice so the render step reads the same place. On the Windows runner the PC1
candidate wins; in the sandbox the durable `/workspace` one does. Losing PC1
therefore degrades to a working library instead of a failed render.

    python3 ops/media_home.py show
    python3 ops/media_home.py ensure            # create both, print them
    python3 ops/media_home.py ensure --pictures # just the picture library
"""
from __future__ import annotations

import argparse
import json
import os
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
STATE = ROOT / "music938-1" / "work" / "media-home.json"

# 4K material is large: a few thousand stills is tens of GB, so the picture
# library wants real disk. `/workspace` survives a pod recycle but not a replaced
# sandbox; the release stays the off-site backup either way.
PICTURES_CANDIDATES = [
    os.environ.get("AX_LIBRARY_DIR", ""),
    r"D:\AX-bank\pictures",
    "/workspace/ax-tools/media-library/pictures",
    str(ROOT / "music938-1" / "library" / "pictures"),
]
FINISHED_CANDIDATES = [
    os.environ.get("AX_FINISHED_DIR", ""),
    r"D:\AX-bank\finished",
    "/workspace/ax-tools/media-library/finished",
    str(ROOT / "music938-1" / "library" / "finished"),
]


def _usable(path: str) -> Path | None:
    """A candidate is usable if it exists and we can write to it, or if its
    parent exists so we can create it. An unreachable drive (D: off PC1) fails
    the parent test instead of raising.

    A Windows path is skipped off Windows. `Path(r"D:\\AX-bank")` is a *relative*
    path on Linux, so without this guard the resolver happily creates a directory
    literally named `D:\\AX-bank` in the repo and calls PC1 "reachable".
    """
    if not path:
        return None
    if len(path) > 2 and path[1] == ":" and os.name != "nt":
        return None
    p = Path(path)
    try:
        if p.exists():
            return p if os.access(p, os.W_OK) else None
        parent = p.parent
        while not parent.exists() and parent != parent.parent:
            parent = parent.parent
        return p if os.access(parent, os.W_OK) else None
    except OSError:
        return None


def resolve(kind: str, create: bool = True) -> Path:
    """First writable candidate for `kind` ('pictures' or 'finished')."""
    if kind not in ("pictures", "finished"):
        raise SystemExit(f"media_home: unknown kind {kind!r}")
    for cand in (PICTURES_CANDIDATES if kind == "pictures" else FINISHED_CANDIDATES):
        p = _usable(cand)
        if p is None:
            continue
        if create:
            p.mkdir(parents=True, exist_ok=True)
        _remember(kind, p)
        return p
    raise SystemExit(f"media_home: no writable location for {kind}")


def _remember(kind: str, path: Path) -> None:
    try:
        doc = json.loads(STATE.read_text()) if STATE.exists() else {}
    except (OSError, ValueError):
        doc = {}
    doc[kind] = str(path)
    try:
        STATE.parent.mkdir(parents=True, exist_ok=True)
        STATE.write_text(json.dumps(doc, indent=1) + "\n")
    except OSError:
        pass  # the record is a convenience; a read-only tree must not fail a render


def pictures() -> Path:
    return resolve("pictures")


def finished() -> Path:
    return resolve("finished")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    sub.add_parser("show", help="print the resolved locations")
    e = sub.add_parser("ensure", help="create the locations")
    e.add_argument("--pictures", action="store_true")
    e.add_argument("--finished", action="store_true")
    a = ap.parse_args(argv)

    kinds = ["pictures", "finished"]
    if a.cmd == "ensure" and (a.pictures or a.finished):
        kinds = [k for k in kinds if getattr(a, k)]
    for k in kinds:
        p = resolve(k)
        n = sum(1 for _ in p.iterdir()) if p.exists() else 0
        print(f"{k:9s} {p}  ({n} entries)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
