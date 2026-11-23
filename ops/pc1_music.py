#!/usr/bin/env python3
"""Read the music library on PC1 (D:\\music1) and hand files to the sandbox.

The sandbox has no route to PC1's D:, so this script runs **on PC1** inside
`.github/workflows/ax-pc1-music-pull.yml` and its result comes back as a build
artifact. Two modes:

  list   index every audio file (path, size, mtime) -> out/music-index.json
  pull   copy the files matching --query (and at most --want) -> out/*.mp3 + out/pull.json

K (2026-11-23): "pc1 D:\\music1 เข้าไปดูในนี้ได้เลย" — the reference charts rank
songs by views; this is where the audio for the measurement stage comes from.

    python ops/pc1_music.py list --root D:\\music1 --out out
    python ops/pc1_music.py pull --root D:\\music1 --query "cocktail" --want 5 --out out
"""
from __future__ import annotations

import argparse
import json
import shutil
import sys
from pathlib import Path

AUDIO_EXT = {".mp3", ".m4a", ".aac", ".wav", ".flac", ".ogg", ".opus", ".wma"}


def scan(root: Path) -> list[dict]:
    if not root.exists():
        raise SystemExit(f"not found: {root}")
    rows = []
    for p in root.rglob("*"):
        if not p.is_file() or p.suffix.lower() not in AUDIO_EXT:
            continue
        st = p.stat()
        rows.append({"path": str(p), "rel": str(p.relative_to(root)),
                     "name": p.name, "ext": p.suffix.lower(),
                     "bytes": st.st_size, "mtime": int(st.st_mtime)})
    rows.sort(key=lambda r: r["rel"].lower())
    return rows


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("mode", choices=["list", "pull"])
    ap.add_argument("--root", default=r"D:\music1")
    ap.add_argument("--query", default="", help="case-insensitive match on the relative path")
    ap.add_argument("--want", type=int, default=0, help="0 = every match")
    ap.add_argument("--out", default="out")
    args = ap.parse_args()

    root, out = Path(args.root), Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    rows = scan(root)
    total_mb = sum(r["bytes"] for r in rows) / 1e6
    print(f"root: {root}")
    print(f"audio files: {len(rows)}  ({total_mb:.1f} MB)")

    if args.mode == "list":
        (out / "music-index.json").write_text(
            json.dumps({"root": str(root), "count": len(rows),
                        "total_mb": round(total_mb, 1), "files": rows},
                       ensure_ascii=False, indent=2), encoding="utf-8")
        by_ext: dict[str, int] = {}
        for r in rows:
            by_ext[r["ext"]] = by_ext.get(r["ext"], 0) + 1
        print("by type:", ", ".join(f"{k} {v}" for k, v in sorted(by_ext.items())))
        for r in rows[:40]:
            print(f"  {r['bytes']/1e6:8.1f} MB  {r['rel']}")
        if len(rows) > 40:
            print(f"  ... {len(rows) - 40} more")
        return 0

    q = args.query.lower()
    hits = [r for r in rows if not q or q in r["rel"].lower()]
    if args.want:
        hits = hits[:args.want]
    if not hits:
        print(f"no match for {args.query!r}", file=sys.stderr)
        return 1
    picked = []
    for r in hits:
        dst = out / r["name"]
        if dst.exists():
            dst = out / f"{len(picked):02d}-{r['name']}"
        shutil.copy2(r["path"], dst)
        picked.append({"name": dst.name, "source": r["path"], "bytes": dst.stat().st_size})
        print(f"  copied {r['rel']} -> {dst.name}")
    (out / "pull.json").write_text(
        json.dumps({"root": str(root), "query": args.query, "files": picked},
                   ensure_ascii=False, indent=2), encoding="utf-8")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
