#!/usr/bin/env python3
"""Fill the 4K picture library a little at a time, from free sources only.

K (2026-11-20): generate images with free AI, keep piling them into the library,
and keep the content varied so it can carry the stories the channel will make.

Two free feeds, both key-less:

* **Wikimedia Commons** — real photographs, and its originals are 4K or larger,
  which is the only source that reliably clears the 4K floor. Licence-checked.
* **genart** — our own procedural renderer (`ops/genart.py`), natively 4096 px,
  reproducible from (algorithm, palette, seed). It is abstract, so it is filed
  under the `abstract` theme where a story can use it as texture or a backdrop.

Dreamina is deliberately *not* a feed here: its free tier is 2K, and 2K fails the
4K floor. `ops/art_bank.py` still banks those at their own size for cover work.

Everything lands under `media_home.pictures()` in `<theme>/` with one `index.json`
that records theme, licence, credit and use count. `story_reel.py` picks from
that index least-used-first, so the library is spent evenly and a clip costs
nothing after generation.

    python3 ops/picture_library.py fill --theme horror --want 40
    python3 ops/picture_library.py fill --all --want 40     # every theme
    python3 ops/picture_library.py stats
"""
from __future__ import annotations

import argparse
import datetime
import json
import os
import random
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ops"))

MIN_W = 3840            # the 4K floor; a smaller source is refused, not upscaled
TARGET_W = 3840

# Story themes the channel makes. Each is a set of English Commons queries —
# Commons returns nothing for Thai — chosen to be visually distinct so clips do
# not all look like the same street at night.
THEMES: dict[str, list[str]] = {
    "horror": ["dark corridor night", "abandoned house fog", "old wooden door dark",
               "candle in dark room", "misty forest night", "empty street lamp night",
               "rain window night", "old staircase dark"],
    "lesson": ["quiet road sunrise", "old man hands coffee", "rain on window",
               "lone tree field", "mountain path fog", "still lake reflection dawn",
               "village morning mist", "bicycle country road"],
    "humour": ["street market bangkok", "thai food stall night", "songthaew street",
               "tuk tuk traffic", "night market lanterns", "cats alley street",
               "motorbike street rain", "food vendor smoke"],
    "city": ["bangkok skyline night", "neon street rain", "skytrain station",
             "rooftop city dusk", "traffic light trail", "alley neon sign"],
    "nature": ["waterfall jungle", "rice terrace green", "tropical beach sunset",
               "mountain clouds", "river mangrove", "rain forest leaves"],
    "temple": ["thai temple golden", "buddha statue temple", "stupa wat sunrise",
               "monk alms morning", "temple lantern night", "ancient ruin stone"],
    "abstract": [],  # served by genart, not Commons
}


def _now() -> str:
    return datetime.datetime.now(datetime.timezone.utc).isoformat(timespec="seconds")


def library() -> Path:
    import media_home  # noqa: PLC0415

    return media_home.pictures()


def load_index(lib: Path) -> dict:
    p = lib / "index.json"
    if p.exists():
        try:
            return json.loads(p.read_text(encoding="utf-8"))
        except (OSError, ValueError):
            pass
    return {"images": []}


def save_index(lib: Path, doc: dict) -> None:
    """Write via a temp file + rename: a reader must never see half an index.

    A fill and an MV build run at the same time (the rail and the agent), and a
    non-atomic write left the build reading a partial catalogue — measured
    2026-11-22: 78 available city stills, the MV saw 15 and held every shot 15 s.
    """
    tmp = lib / "index.json.tmp"
    tmp.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    tmp.replace(lib / "index.json")


def have_theme(doc: dict, theme: str) -> int:
    return sum(1 for r in doc["images"] if r.get("theme") == theme)


def from_commons(theme: str, want: int, lib: Path, log=print) -> list[dict]:
    """Download `want` 4K photographs for `theme`. Returns index rows."""
    import stills_rail as sr  # noqa: PLC0415
    from PIL import Image  # noqa: PLC0415

    dest_dir = lib / theme
    dest_dir.mkdir(parents=True, exist_ok=True)
    queries = THEMES.get(theme, [])
    if not queries:
        return []

    rows, seen = [], set()
    random.shuffle(queries)
    for q in queries:
        if len(rows) >= want:
            break
        # Commons only, not `search_multi`: Openverse's "large" tier answers with
        # 1024-1280 px files, which the 4K floor then rejects, so interleaving it
        # just wastes a download per slot.
        items = sr.search(q, limit=8, min_width=MIN_W)
        if not items:
            continue
        nums = [int(m.group(1)) for f in dest_dir.glob("s*")
                if (m := re.match(r"s(\d+)", f.stem))]
        got = sr.download(items[:want - len(rows)], str(dest_dir),
                          log=lambda *_: None, start=(max(nums) + 1) if nums else 0)
        for it in got:
            p = Path(it["path"])
            try:
                with Image.open(p) as im:
                    w, h = im.size
            except Exception:  # noqa: BLE001 - one bad file must not stop the fill
                p.unlink(missing_ok=True)
                continue
            if max(w, h) < MIN_W:
                p.unlink(missing_ok=True)   # keep the library honestly 4K
                continue
            key = (it.get("title") or p.name)
            if key in seen:
                p.unlink(missing_ok=True)
                continue
            seen.add(key)
            rows.append({
                "id": f"{theme}-{len(rows):04d}", "theme": theme,
                "file": f"{theme}/{p.name}", "w": w, "h": h,
                "title": it.get("title"), "licence": it.get("licence"),
                "credit": it.get("credit"), "origin": "Wikimedia Commons",
                "source": it.get("source"), "uses": 0, "at": _now(),
            })
        log(f"  [{theme}] {len(rows)}/{want} from Commons")
    return rows


def from_genart(theme: str, want: int, lib: Path, log=print) -> list[dict]:
    """Render `want` 4K abstract works. Free, offline, reproducible."""
    import genart  # noqa: PLC0415
    from PIL import Image  # noqa: PLC0415

    dest_dir = lib / theme
    dest_dir.mkdir(parents=True, exist_ok=True)
    rows = []
    algos = sorted(genart.ALGOS)
    palettes = sorted(genart.PALETTES)
    start = len(list(dest_dir.glob("*.png")))
    for i in range(want):
        algo = algos[(start + i) % len(algos)]
        pal = palettes[(start + i * 3) % len(palettes)]
        seed = 1000 + start + i
        try:
            p = genart.make(algo, "print", pal, seed, "", out_dir=dest_dir,
                            svg=False, log=lambda *_: None)
        except SystemExit:
            continue
        try:
            with Image.open(p) as im:
                w, h = im.size
        except Exception:  # noqa: BLE001
            continue
        rows.append({
            "id": f"{theme}-{i:04d}", "theme": theme, "file": f"{theme}/{p.name}",
            "w": w, "h": h, "title": f"{algo} {pal} {seed}",
            "licence": "own work (generated)", "credit": "AX genart",
            "origin": "genart", "source": "ops/genart.py", "uses": 0, "at": _now(),
        })
        log(f"  [{theme}] {len(rows)}/{want} from genart")
    return rows


def cmd_fill(a) -> int:
    lib = library()
    doc = load_index(lib)
    themes = list(THEMES) if a.all else [a.theme]
    added = 0
    for theme in themes:
        short = max(0, a.want - have_theme(doc, theme)) if a.topup else a.want
        if short <= 0:
            print(f"{theme}: already at {have_theme(doc, theme)} (>= {a.want})")
            continue
        print(f"{theme}: filling {short}")
        rows = (from_genart(theme, short, lib)
                if theme == "abstract" else from_commons(theme, short, lib))
        doc["images"].extend(rows)
        added += len(rows)
        save_index(lib, doc)
    print(f"fill: +{added} still(s) -> {lib} (total {len(doc['images'])})")
    return 0


def reindex(lib: Path, log=print) -> dict:
    """Rebuild the index from the files on disk, one row per file.

    The index can lie: a fill that reused `s000.jpg` appended a row for a picture
    that was never written, so 133 city rows named 14 files and an MV asking for
    78 stills got 15. Disk is the truth; a row that cannot be opened is not a
    picture. Metadata (licence, credit, uses) is carried over from the old row
    when the file name still matches.
    """
    from PIL import Image  # noqa: PLC0415

    idx = lib / "index.json"
    old_rows = {}
    if idx.exists():
        try:
            for r in json.loads(idx.read_text(encoding="utf-8")).get("images", []):
                old_rows.setdefault(r.get("file"), r)
        except (OSError, ValueError):
            pass
    rows, dropped = [], 0
    for f in sorted(lib.rglob("*")):
        if f.suffix.lower() not in {".jpg", ".jpeg", ".png"}:
            continue
        rel = f.relative_to(lib).as_posix()
        try:
            with Image.open(f) as im:
                w, h = im.size
        except Exception:  # noqa: BLE001 - an unreadable file is not a picture
            dropped += 1
            continue
        theme = rel.split("/")[0] if "/" in rel else "abstract"
        prev = old_rows.get(rel) or {}
        rows.append({
            "id": prev.get("id") or f"{theme}-{len(rows):04d}",
            "theme": theme, "file": rel, "w": w, "h": h,
            "title": prev.get("title") or f.stem,
            "licence": prev.get("licence"), "credit": prev.get("credit"),
            "origin": prev.get("origin") or "local",
            "uses": prev.get("uses") or 0,
        })
    save_index(lib, {"images": rows})
    log(f"reindex: {len(rows)} picture(s) on disk, {dropped} unreadable dropped")
    return {"images": rows}


def cmd_stats(a) -> int:
    lib = library()
    doc = load_index(lib)
    by: dict[str, int] = {}
    for r in doc["images"]:
        by[r.get("theme") or "?"] = by.get(r.get("theme") or "?", 0) + 1
    print(f"library: {lib}")
    print(f"total  : {len(doc['images'])}")
    for t in sorted(by):
        print(f"  {t:10s} {by[t]}")
    sub4k = [r for r in doc["images"] if max(r.get("w") or 0, r.get("h") or 0) < MIN_W]
    print(f"below 4K: {len(sub4k)}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0],
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)
    f = sub.add_parser("fill", help="add 4K stills to the library")
    f.add_argument("--theme", default="horror", choices=sorted(THEMES))
    f.add_argument("--all", action="store_true", help="every theme")
    f.add_argument("--want", type=int, default=20)
    f.add_argument("--topup", action="store_true",
                   help="only fill up to --want instead of adding --want more")
    f.set_defaults(func=cmd_fill)
    s = sub.add_parser("stats", help="counts per theme")
    s.set_defaults(func=cmd_stats)
    r = sub.add_parser("reindex", help="rebuild the index from the files on disk")
    r.set_defaults(func=lambda a: (reindex(library()), 0)[1])
    a = ap.parse_args(argv)
    return a.func(a)


if __name__ == "__main__":
    raise SystemExit(main())
