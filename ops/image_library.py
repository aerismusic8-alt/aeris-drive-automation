#!/usr/bin/env python3
"""A reusable AI image bank: generate once into `library/scenes/`, pull forever.

K (2026-11-19): "ภาพสร้างเข้าคลังไว้เลยสิ ทำคลังภาพเหมือน pixel เลย แล้วค่อยไปดึงมาใช้ไง"

That is the whole design. A clip must not pay credits every time it needs a
picture. Generation is a *filling* step — spend once, keep the file — and every
later render is a *picking* step that costs nothing.

    python3 ops/image_library.py fill --genre rock --count 6
    python3 ops/image_library.py pick --genre rock --count 3
    python3 ops/image_library.py list
    python3 ops/image_library.py stats

The bank is keyed by the same genre ids `channel/genres.json` uses, so a song
draws pictures from its own lane. `pick` is least-used-first and advances a
counter, so consecutive songs do not reuse the same three images; `--shuffle`
draws a random set instead.

Files live under `library/scenes/<genre>/`, which is gitignored like the other
media, so `publish` packs each genre into one tar on the `scenes-938` release and
the clip lane fetches it back on a fresh runner. The manifest is the index and
*is* committed, so a fresh pod knows what the bank holds before it downloads
anything.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import random
import shutil
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "music938-1" / "library" / "scenes"
MANIFEST = LIB / "manifest.json"

# One visual language per active lane. These are the *default* prompts; `fill`
# takes `--theme` to override, and a scene recorded here keeps the prompt that
# made it, so the bank stays reproducible.
GENRE_PROMPTS = {
    "rock": "Thai rock, gritty concrete and neon, sweat and stage smoke, high contrast, "
            "cinematic still, film grain, no text, no letters",
    "pop": "Thai pop, bright daylight colour, clean pastel streets, glossy and cheerful, "
           "cinematic still, no text, no letters",
    "edm": "EDM, laser beams and haze, crowd silhouettes, saturated magenta and cyan, "
           "cinematic still, no text, no letters",
    "hiphop": "Thai hiphop, night soi and sodium street light, low camera, concrete texture, "
              "cinematic still, film grain, no text, no letters",
    "rap": "Thai rap, rain on asphalt, hard rim light, tight framing, "
           "cinematic still, film grain, no text, no letters",
    "synthpop": "Synthpop, retro chrome and sunset gradient, 1980s sheen, "
                "cinematic still, no text, no letters",
    "alternative": "Thai alternative, washed-out film, empty roadside, soft haze, "
                   "cinematic still, no text, no letters",
}

# Camera beats, so six images from one lane are six different pictures rather
# than six versions of the same one.
BEATS = [
    "a wide establishing shot",
    "a low close detail of texture",
    "a figure turning away",
    "light breaking across the frame",
    "an empty room after",
    "the horizon at distance",
]

RATIOS = {"land": "16:9", "vert": "9:16", "square": "1:1"}


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def load() -> dict:
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text())
    return {"version": 1, "images": []}


def save(doc: dict) -> None:
    LIB.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(doc, ensure_ascii=False, indent=1) + "\n")


def _cli() -> str:
    return shutil.which("dreamina") or "/workspace/ax-tools/bin/dreamina"


def credits() -> int:
    """Live credit balance, or 0 when the account cannot be read."""
    proc = subprocess.run([_cli(), "auth", "account", "--format", "json"],
                          capture_output=True, text=True, timeout=120)
    try:
        return int((json.loads(proc.stdout.strip().splitlines()[-1]).get("data") or {})
                   .get("availableCredits") or 0)
    except (IndexError, json.JSONDecodeError, ValueError):
        return 0


def generate(prompt: str, out: Path, project: str, ratio: str, ceiling: int) -> Path:
    """One seedream 4.0 still, downloaded to `out`."""
    out.parent.mkdir(parents=True, exist_ok=True)
    proc = subprocess.run(
        [_cli(), "node", "create", "image", "--project-id", project,
         "--model", "seedream_4.0", "--mode", "t2i", "--ratio", ratio,
         "--resolution", "2K", "--title", out.stem[:60], "--prompt", prompt,
         "--run", "--wait", "--credit-ceiling", str(ceiling), "--format", "json"],
        capture_output=True, text=True, timeout=900)
    try:
        doc = json.loads(proc.stdout.strip().splitlines()[-1])
    except (IndexError, json.JSONDecodeError) as exc:
        raise RuntimeError(f"dreamina gave no JSON: {proc.stdout[-300:]}") from exc
    res = (doc.get("data") or {}).get("submission", {}).get("resources") or []
    if not doc.get("ok") or not res:
        raise RuntimeError(f"dreamina image failed: {json.dumps(doc.get('error') or doc)[:300]}")
    subprocess.run([_cli(), "resource", "download", res[0]["resourceId"],
                    "--project-id", project, "-o", str(out), "--format", "json"],
                   capture_output=True, text=True, timeout=600)
    if not out.exists() or out.stat().st_size == 0:
        raise RuntimeError(f"download produced no file for {out}")
    return out


def fill(genre: str, count: int, project: str, ratio_key: str, theme: str | None,
         ceiling: int, dry_run: bool) -> int:
    doc = load()
    taken = {(r["genre"], r["beat"]) for r in doc["images"]}
    base = theme or GENRE_PROMPTS.get(genre)
    if not base:
        raise SystemExit(f"unknown genre {genre!r}; pass --theme or use one of "
                         f"{', '.join(sorted(GENRE_PROMPTS))}")

    # Fill the beats this lane has not used yet, so a second `fill` extends the
    # bank instead of duplicating the first six pictures.
    todo = [b for b in BEATS if (genre, b) not in taken][:count]
    if not todo:
        print(f"{genre}: every beat already has an image; nothing to fill")
        return 0

    have = credits()
    need = len(todo) * 8
    print(f"{genre}: {len(todo)} scene(s) to make, {need} credits, {have} available")
    if have < need:
        print(f"  only {have // 8} scene(s) affordable; trimming the batch", file=sys.stderr)
        todo = todo[: have // 8]
        if not todo:
            print("  no credits left — the bank keeps what it has", file=sys.stderr)
            return 1

    made = 0
    start = sum(1 for r in doc["images"] if r["genre"] == genre)
    for beat in todo:
        ident = f"{genre}-{start + made + 1:03d}"
        out = LIB / genre / f"{ident}.png"
        prompt = f"{base}. {beat}"
        if dry_run:
            print(f"  would make {ident}: {prompt}")
            made += 1
            continue
        if out.exists():
            print(f"  {ident} already on disk")
            continue
        try:
            generate(prompt, out, project, RATIOS[ratio_key], ceiling)
        except Exception as exc:  # noqa: BLE001 - one bad scene must not lose the batch
            print(f"  {ident} FAILED: {exc}", file=sys.stderr)
            continue
        doc["images"].append({
            "id": ident, "genre": genre, "beat": beat, "prompt": prompt,
            "file": str(out.relative_to(LIB)), "ratio": RATIOS[ratio_key],
            "model": "seedream_4.0", "credits": 8, "at": _now(),
            "sha256": hashlib.sha256(out.read_bytes()).hexdigest()[:16],
            "uses": 0,
        })
        save(doc)
        made += 1
        print(f"  made {ident} ({out.stat().st_size // 1024} KB)")
    print(f"{genre}: {made} new image(s), bank now {len(doc['images'])}")
    return 0


def pick(genre: str | None, count: int, shuffle: bool, mark: bool) -> list[Path]:
    """Paths for `count` images, least-used first. Costs nothing.

    Falls back to the stock bank (`image_bank`) when the AI lanes are empty, so
    a render never fails just because credits ran out.
    """
    doc = load()
    rows = [r for r in doc["images"] if not genre or r["genre"] == genre]
    rows = [r for r in rows if (LIB / r["file"]).exists()]
    if not rows:
        return pick_stock(count, shuffle, mark)
    if shuffle:
        chosen = random.sample(rows, min(count, len(rows)))
    else:
        chosen = sorted(rows, key=lambda r: (r.get("uses", 0), r["id"]))[:count]
    if mark:
        for r in chosen:
            r["uses"] = r.get("uses", 0) + 1
        save(doc)
    return [LIB / r["file"] for r in chosen]


def pick_stock(count: int, shuffle: bool, mark: bool, query: str | None = None) -> list[Path]:
    """The stock bank (`ops/image_bank.py`) — free, unlimited, licence-clean."""
    import image_bank  # noqa: PLC0415 - avoids a circular import at module load

    doc = image_bank.load()
    rows = [r for r in doc["images"]
            if (query is None or query.lower() in (r.get("query") or "").lower()
                or query.lower() in (r.get("title") or "").lower())
            and (image_bank.LIB / r["file"]).exists()]
    if not rows:
        return []
    if shuffle:
        chosen = random.sample(rows, min(count, len(rows)))
    else:
        chosen = sorted(rows, key=lambda r: (r.get("uses", 0), r["id"]))[:count]
    if mark:
        for r in chosen:
            r["uses"] = r.get("uses", 0) + 1
        image_bank.save(doc)
    return [image_bank.LIB / r["file"] for r in chosen]


REPO = "aerismusic8-alt/aeris-drive-automation"
API = "https://api.github.com"
SCENES_TAG = "scenes-938"


def _token() -> str:
    tok = os.environ.get("AX_GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not tok:
        f = Path("/workspace/ax-tools/ar-identity/gh-token")
        if f.exists():
            tok = f.read_text().strip()
    if not tok:
        raise SystemExit("no AX_GH_TOKEN / GITHUB_TOKEN")
    return tok


def _api(path: str, tok: str, method="GET", data=None, raw=None,
         ctype="application/json"):
    import urllib.error  # noqa: PLC0415
    import urllib.request  # noqa: PLC0415

    url = path if path.startswith("http") else API + path
    body = raw if raw is not None else (
        json.dumps(data).encode() if data is not None else None)
    req = urllib.request.Request(url, data=body, method=method, headers={
        "Authorization": f"token {tok}", "Accept": "application/vnd.github+json",
        "User-Agent": "ax-image-library", "Content-Type": ctype})
    try:
        with urllib.request.urlopen(req, timeout=900) as r:
            txt = r.read().decode()
            return r.status, (json.loads(txt) if txt else {})
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:300]}


def publish(log=print) -> int:
    """Pack each genre's frames into one tar and attach it to `scenes-938`.

    The frames are gitignored, so without this a runner has the manifest and none
    of the pictures and every mix silently falls back to photographs. One tarball
    per genre is a single download per lane instead of 42 separate ones.

    The release is created on first use, so a fresh account needs no manual step.
    """
    import io  # noqa: PLC0415
    import tarfile  # noqa: PLC0415

    doc = load()
    rows = doc.get("images", [])
    if not rows:
        log("publish: the bank is empty")
        return 1

    tok = _token()
    st, rel = _api(f"/repos/{REPO}/releases/tags/{SCENES_TAG}", tok)
    if st == 404:
        st, rel = _api(f"/repos/{REPO}/releases", tok, "POST", {
            "tag_name": SCENES_TAG, "name": "AERIS — generated scene bank",
            "body": "AI-generated scene frames for the clip lanes. Free to "
                    "re-pull; see ops/image_library.py.",
            "draft": False, "prerelease": False})
    if st not in (200, 201):
        log(f"publish: cannot reach release {SCENES_TAG}: {st} {rel}")
        return 1
    rid = rel["id"]
    existing = {a["name"] for a in rel.get("assets", [])}

    by_genre: dict[str, list[dict]] = {}
    for r in rows:
        if (LIB / r["file"]).exists():
            by_genre.setdefault(r.get("genre") or "misc", []).append(r)
    if not by_genre:
        log("publish: no frames on disk to publish")
        return 1

    rc = 0
    for genre, group in sorted(by_genre.items()):
        name = f"scenes-{genre}.tar"
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w") as tf:
            for r in group:
                p = LIB / r["file"]
                tf.addfile(tf.gettarinfo(str(p), arcname=f"{genre}/{p.name}"),
                           p.open("rb"))
        data = buf.getvalue()
        if name in existing:
            # A re-publish replaces the asset, or the runner keeps the old tar
            # and a newly generated frame never reaches a clip.
            aid = next(a["id"] for a in rel["assets"] if a["name"] == name)
            _api(f"/repos/{REPO}/releases/assets/{aid}", tok, "DELETE")
        st, res = _api(
            f"https://uploads.github.com/repos/{REPO}/releases/{rid}/assets"
            f"?name={name}", tok, "POST", raw=data,
            ctype="application/octet-stream")
        if st not in (200, 201):
            log(f"publish: FAIL {name}: {st} {res}")
            rc = 1
            continue
        log(f"publish: {name} -> {len(group)} frame(s), "
            f"{len(data) / 1e6:.1f} MB, {res.get('browser_download_url', '')[-40:]}")
    return rc


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    f = sub.add_parser("fill", help="generate new images into the bank")
    f.add_argument("--genre", required=True)
    f.add_argument("--count", type=int, default=6)
    f.add_argument("--theme", help="override the lane's default visual language")
    f.add_argument("--ratio", choices=sorted(RATIOS), default="land")
    f.add_argument("--project-id", default=os.environ.get("DREAMINA_PROJECT_ID", ""))
    f.add_argument("--ceiling", type=int, default=12)
    f.add_argument("--dry-run", action="store_true")

    p = sub.add_parser("pick", help="print paths for reuse (free)")
    p.add_argument("--genre", help="AI lane; falls back to the stock bank when empty")
    p.add_argument("--query", help="match a stock query or title instead of a lane")
    p.add_argument("--stock", action="store_true", help="force the stock bank")
    p.add_argument("--count", type=int, default=3)
    p.add_argument("--shuffle", action="store_true")
    p.add_argument("--no-mark", action="store_true", help="do not advance the use counter")

    fa = sub.add_parser("fill-all", help="top up every lane, stopping when credits run out")
    fa.add_argument("--per-lane", type=int, default=4)
    fa.add_argument("--project-id", default=os.environ.get("DREAMINA_PROJECT_ID", ""))
    fa.add_argument("--ratio", choices=sorted(RATIOS), default="land")
    fa.add_argument("--ceiling", type=int, default=12)
    fa.add_argument("--dry-run", action="store_true")

    sub.add_parser("publish", help="attach the frames to the scenes release")
    sub.add_parser("list", help="show the bank")
    sub.add_parser("stats", help="counts per lane and credit balance")

    a = ap.parse_args()

    if a.cmd == "fill":
        if not a.dry_run and not a.project_id:
            raise SystemExit("--project-id or DREAMINA_PROJECT_ID is required")
        return fill(a.genre, a.count, a.project_id, a.ratio, a.theme,
                    a.ceiling, a.dry_run)

    if a.cmd == "fill-all":
        if not a.dry_run and not a.project_id:
            raise SystemExit("--project-id or DREAMINA_PROJECT_ID is required")
        rc = 0
        for lane in GENRE_PROMPTS:
            if credits() < a.per_lane * 8 and not a.dry_run:
                print(f"{lane}: skipping, {credits()} credits left")
                continue
            rc |= fill(lane, a.per_lane, a.project_id, a.ratio, None,
                       a.ceiling, a.dry_run)
        return rc

    if a.cmd == "publish":
        return publish()

    if a.cmd == "pick":
        if a.stock or (a.query and not a.genre):
            paths = pick_stock(a.count, a.shuffle, not a.no_mark, a.query)
        else:
            paths = pick(a.genre, a.count, a.shuffle, not a.no_mark)
        if not paths:
            print("bank empty for that lane — run `fill` first", file=sys.stderr)
            return 1
        for q in paths:
            print(q)
        return 0

    doc = load()
    if a.cmd == "list":
        for r in doc["images"]:
            print(f"{r['id']:16} {r['genre']:12} uses={r.get('uses', 0):2} {r['beat'][:34]}")
        print(f"{len(doc['images'])} image(s)")
        return 0

    lanes: dict[str, int] = {}
    for r in doc["images"]:
        lanes[r["genre"]] = lanes.get(r["genre"], 0) + 1
    for k in sorted(lanes):
        print(f"  {k:12} {lanes[k]:3}")
    print(f"total {len(doc['images'])} image(s), {credits()} credits available")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
