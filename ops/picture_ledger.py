#!/usr/bin/env python3
"""Which picture went into which MV, and keep a picture out of two MVs.

K (2026-11-22): "ห้ามภาพเดิมซ้ำในแต่ละ mv อันไหนใช้กับ mv ไหนต้อง stamp ไว้เลย".

Two rules, one file:

* **No picture twice inside one MV.** `make_music_video.distinct_sources` already
  dedupes a single build; this module is what stops the *next* MV from starting
  with the same stills.
* **Every use is stamped.** A picture's record names the MV (and the shot) it
  appeared in, so "which MV used this picture" is a lookup, not a guess.

`rank()` is the ordering an MV build applies: pictures no MV has used yet come
first, then the least-used, so a growing library is spent evenly. When the
library cannot cover a build, reuse is allowed but it is recorded — a build that
had to reuse a picture is visible in `--report` instead of being invisible.

    python3 ops/picture_ledger.py --report
    python3 ops/picture_ledger.py --mv mv-34-wan-tham-mada-thi-phi-set-v34
    python3 ops/picture_ledger.py --unused 20
"""
from __future__ import annotations

import argparse
import datetime
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LEDGER = ROOT / "music938-1" / "work" / "picture-ledger.json"


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def _key(path: Path) -> str:
    """Repo-relative POSIX path: the ledger survives a pod move, an absolute path does not."""
    p = Path(path).resolve()
    try:
        return p.relative_to(ROOT).as_posix()
    except ValueError:
        return p.as_posix()


def _sha1(path: Path) -> str:
    h = hashlib.sha1()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def load(path: Path = LEDGER) -> dict:
    if path.exists():
        try:
            doc = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError:
            doc = {}
    else:
        doc = {}
    doc.setdefault("version", 1)
    doc.setdefault("mvs", {})
    return doc


def save(doc: dict, path: Path = LEDGER) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    doc["updated"] = _now()
    path.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")


def uses(doc: dict | None = None) -> dict[str, list[str]]:
    """picture key -> the MVs that used it."""
    doc = doc or load()
    out: dict[str, list[str]] = {}
    for mv, rec in doc["mvs"].items():
        for pic in rec.get("pictures", []):
            out.setdefault(pic["key"], []).append(mv)
    return out


def rank(paths: list[Path], doc: dict | None = None) -> list[Path]:
    """Unused pictures first, then least-used; original order breaks ties."""
    doc = doc or load()
    used = {k: len(v) for k, v in uses(doc).items()}
    order = {id(p): i for i, p in enumerate(paths)}
    return sorted(paths, key=lambda p: (used.get(_key(p), 0), order[id(p)]))


def claim(paths: list[Path], want: int, doc: dict | None = None) -> tuple[list[Path], list[Path]]:
    """The `want` freshest pictures, plus the ones that had to be reused."""
    doc = doc or load()
    ranked = rank(paths, doc)
    used = uses(doc)
    chosen = ranked[:want]
    reused = [p for p in chosen if _key(p) in used]
    return chosen, reused


def stamp(slug: str, pictures: list[Path], doc: dict | None = None,
          path: Path = LEDGER) -> dict:
    """Record that `slug` used these pictures, one shot each, in this order."""
    doc = doc or load(path)
    doc["mvs"][slug] = {
        "built": _now(),
        "count": len(pictures),
        "pictures": [
            {"shot": i, "key": _key(p), "sha1": _sha1(p) if Path(p).exists() else ""}
            for i, p in enumerate(pictures)
        ],
    }
    save(doc, path)
    return doc["mvs"][slug]


def report(doc: dict | None = None) -> str:
    doc = doc or load()
    used = uses(doc)
    lines = [f"picture ledger: {len(doc['mvs'])} MV(s), {len(used)} distinct picture(s) stamped"]
    for mv, rec in sorted(doc["mvs"].items()):
        lines.append(f"  {mv[:52]:52} {rec.get('count', 0):3} picture(s)  {rec.get('built','')}")
    shared = {k: v for k, v in used.items() if len(v) > 1}
    if shared:
        lines.append(f"  reused across MVs: {len(shared)}")
        for k, v in list(shared.items())[:5]:
            lines.append(f"    {Path(k).name[:44]:44} -> {', '.join(v)}")
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--report", action="store_true", help="per-MV picture counts and any reuse")
    ap.add_argument("--mv", help="list the pictures one MV used")
    ap.add_argument("--unused", type=int, help="print N pictures no MV has used")
    ap.add_argument("--pictures", default="library/pictures", help="picture root to scan")
    a = ap.parse_args(argv)
    doc = load()
    if a.mv:
        rec = doc["mvs"].get(a.mv) or doc["mvs"].get(a.mv.replace("mv-", ""))
        if not rec:
            print(f"no stamp for {a.mv}", file=sys.stderr)
            return 2
        for p in rec["pictures"]:
            print(f"  {p['shot']:02d} {p['key']}")
        return 0
    if a.unused:
        root = ROOT / a.pictures
        used = uses(doc)
        free = [p for p in sorted(root.rglob("*.jpg")) if _key(p) not in used]
        for p in free[: a.unused]:
            print(_key(p))
        print(f"unused: {len(free)}", file=sys.stderr)
        return 0
    print(report(doc))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
