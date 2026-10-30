#!/usr/bin/env python3
"""Build and ship the stills stock the 4 channels draw from.

Why this exists next to `stills_rail.py`:
  `stills_rail.py` *finds and downloads* stills. This script decides *which*
  themes each channel needs, compresses them to a shippable size, writes the
  attribution block, and can rebuild the whole stock from a one-line query list.

The pixels are the point, but they are also 60 MB raw, which does not travel.
Two things make that a non-problem:
  * `pack` compresses to ~1920px q80 and tars it, so the set moves as one file.
  * `rebuild` re-downloads the same themes from the query list below. The query
    list is ~1 KB, so a fresh sandbox can recreate the stock with one command
    even if the tarball was never carried across.

Licences: Wikimedia Commons only, CC0 / PD / CC BY / CC BY-SA. NC and ND are
excluded by `stills_rail`. BY and BY-SA still need the credit line in the video
description, which `credits()` emits.
"""
import argparse
import json
import os
import subprocess
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import stills_rail as sr  # noqa: E402

# One theme per channel, so a builder can pull "the ch2 stills" without thought.
THEMES = {
    "philosophy": ["quiet road sunrise", "old man hands coffee", "rain on window",
                   "mountain path fog", "open sky clouds", "lone tree field",
                   "still lake reflection dawn", "candle in dark"],
    "dhamma": ["night sky stars", "temple dawn thailand", "lotus flower pond",
               "moon over water", "misty forest morning", "calm sea horizon",
               "zen garden stones", "soft candle glow"],
    "music": ["concert stage lights", "studio microphone dark", "electric guitar closeup",
              "neon night city", "vinyl record turntable", "piano keys dark"],
    "drama": ["dramatic storm clouds", "moody mountain range", "abandoned building fog",
              "forest path dusk", "ocean waves cliff", "desert dunes sunset"],
}
PER_QUERY = 4


def rebuild(root, per_query=PER_QUERY, log=print):
    manifest = {}
    total = 0
    for theme, queries in THEMES.items():
        pool = sr.harvest(queries, per_query=per_query,
                          cache_path=os.path.join(root, theme, "pool.json"))
        got = sr.download(pool, os.path.join(root, theme), log=lambda m: None)
        manifest[theme] = {"count": len(got), "files": [
            {"path": g["path"], "licence": g["licence"], "credit": g["credit"],
             "source": g["source"], "title": g["title"]} for g in got]}
        total += len(got)
        log(f"  {theme:11} {len(got):2} stills")
    json.dump(manifest, open(os.path.join(root, "MANIFEST.json"), "w"),
              ensure_ascii=False, indent=1)
    log(f"  TOTAL {total} stills -> {root}")
    return manifest


def compress(root, out_root, max_w=1920, quality=80):
    """Shrink the stock so it travels. `sips` is absent; PIL is the tool here."""
    from PIL import Image
    saved = 0
    for dirpath, _, files in os.walk(root):
        for fn in files:
            if not fn.lower().endswith((".jpg", ".jpeg", ".png")):
                continue
            src = os.path.join(dirpath, fn)
            rel = os.path.relpath(src, root)
            dst = os.path.join(out_root, rel)
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            im = Image.open(src).convert("RGB")
            if im.width > max_w:
                im = im.resize((max_w, int(im.height * max_w / im.width)), Image.LANCZOS)
            im.save(dst, "JPEG", quality=quality, optimize=True, progressive=True)
            saved += 1
    return saved


def credits(root, out_txt):
    """The attribution block a BY / BY-SA still requires in the description."""
    man = json.load(open(os.path.join(root, "MANIFEST.json"), encoding="utf-8"))
    lines = ["ภาพประกอบ (ภาพถ่าย) — เครดิตและสัญญาอนุญาต", ""]
    seen = set()
    for theme, d in man.items():
        for f in d["files"]:
            if "cc0" in f["licence"].lower() or "public domain" in f["licence"].lower():
                continue
            key = (f["title"], f["credit"])
            if key in seen:
                continue
            seen.add(key)
            who = f["credit"] or "Wikimedia Commons contributor"
            lines.append(f"- {f['title']} — {who} — {f['licence']} — {f['source']}")
    lines.append("")
    open(out_txt, "w", encoding="utf-8").write("\n".join(lines))
    return len(seen)


def main():
    ap = argparse.ArgumentParser(description="Build/ship the channel stills stock.")
    ap.add_argument("cmd", choices=["rebuild", "compress", "credits", "pack", "verify"])
    ap.add_argument("--root", default="stock")
    ap.add_argument("--out", default="stock_compressed")
    ap.add_argument("--tar", default="out/ax-stock.tar.gz")
    ap.add_argument("--per-query", type=int, default=PER_QUERY)
    a = ap.parse_args()

    if a.cmd == "rebuild":
        rebuild(a.root, a.per_query)
    elif a.cmd == "compress":
        n = compress(a.root, a.out)
        print(f"compressed {n} images -> {a.out}")
    elif a.cmd == "credits":
        n = credits(a.root, "stock/CREDITS.txt")
        print(f"credits for {n} attributed files -> stock/CREDITS.txt")
    elif a.cmd == "pack":
        os.makedirs(os.path.dirname(a.tar), exist_ok=True)
        subprocess.run(["tar", "czf", a.tar, a.root], check=True)
        print(f"packed {a.root} -> {a.tar} "
              f"({os.path.getsize(a.tar)//1024} KB)")
    elif a.cmd == "verify":
        man = json.load(open(os.path.join(a.root, "MANIFEST.json"), encoding="utf-8"))
        missing = 0
        for theme, d in man.items():
            for f in d["files"]:
                if not os.path.exists(f["path"]):
                    missing += 1
        tot = sum(d["count"] for d in man.values())
        print(f"themes={len(man)} stills={tot} missing_files={missing}")
        if missing:
            raise SystemExit("stock is incomplete")


if __name__ == "__main__":
    main()
