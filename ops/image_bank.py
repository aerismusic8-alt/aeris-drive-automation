#!/usr/bin/env python3
"""Accumulate a large, high-resolution, licence-clean image bank — for free.

K (2026-11-19): "เราต้องหาวิธีสร้างภาพความละเอียดสูงสะสมไว้ในคลังเราเยอะๆเลย
เป็นแสนรูปเลยก็ได้" and "เราทำสะสมไปเรื่อยๆ".

Why this is the right engine and a generator is not:

  * `ops/stills_rail.py` already reaches five sources that need no key, no
    account and no captcha, and every file carries a machine-readable licence.
    Measured on this pod: 19 images in 4.2 s, 1.8-4 K, ~555 KB each. A
    generator gives one 1024x576 JPEG per 45 s per IP (Pollinations) or 8
    expiring credits a picture (Dreamina). At 100k images the difference is a
    day versus never.
  * The bank must outlive the pod, so files are packed into shards and pushed
    to the durable `media-938` release, then deleted locally. The manifest is
    the index and is committed, so a fresh pod knows what it holds.

Storage arithmetic, measured not guessed: a 1920 px WebP q80 is 240 KB, so
100k images is ~24 GB of shards plus a ~30 MB manifest. Local disk is 12 GB, so
shards leave as soon as they are full — that is why `shard` exists.

    python3 ops/image_bank.py harvest --queries ops/bank-queries.txt --want 2000
    python3 ops/image_bank.py shard          # pack + upload + delete local
    python3 ops/image_bank.py stats
    python3 ops/image_bank.py verify         # every manifest row has a file
    python3 ops/image_bank.py pull --limit 50   # get files back from a shard

Queries live in a text file, one per line, so growing the bank is editing a
list, not editing code.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import os
import random
import sys
import tarfile
import time
import urllib.error
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "music938-1" / "library" / "stock"
MANIFEST = LIB / "manifest.json"
SHARDS = LIB / "shards"

REPO = "aerismusic8-alt/aeris-drive-automation"
API = "https://api.github.com"
RELEASE = "media-938"

# K (2026-11-20): the picture library is clip *material*, so it is kept at 4K.
# A 3840 long edge leaves room to crop, pan and push without ever upscaling the
# output, which is what makes a 720p/1080p render look sharp instead of soft.
TARGET_W = 3840          # long edge, 4K UHD
MIN_W = 3840             # below this the source is refused at ingest
WEBP_Q = 88              # a 4K still needs the extra bits; measured on this pod
SHARD_MAX = 400 * 1024 * 1024   # 400 MB keeps one upload under the 2 GB asset cap

# Museum APIs answer every query with paintings — measured on a 60-image run,
# 37 of 60 were artworks from the Art Institute of Chicago, useless as footage.
# The bank takes only sources that return photographs.
PHOTO_SOURCES = ("Wikimedia Commons", "Openverse", "NASA")


def photo_only(items: list[dict]) -> list[dict]:
    return [it for it in items if it.get("origin") in PHOTO_SOURCES]


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def load() -> dict:
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text())
    return {"version": 1, "images": [], "shards": []}


def save(doc: dict) -> None:
    LIB.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(doc, ensure_ascii=False, indent=0) + "\n")


def token() -> str:
    tok = os.environ.get("AX_GH_TOKEN") or os.environ.get("GITHUB_TOKEN")
    if not tok:
        f = Path("/workspace/ax-tools/ar-identity/gh-token")
        if f.exists():
            tok = f.read_text().strip()
    if not tok:
        raise SystemExit("no AX_GH_TOKEN / GITHUB_TOKEN")
    return tok


def api(path: str, tok: str, method="GET", data=None, raw=None,
        ctype="application/json"):
    url = path if path.startswith("http") else API + path
    body = raw if raw is not None else (json.dumps(data).encode() if data is not None else None)
    req = urllib.request.Request(url, data=body, method=method, headers={
        "Authorization": f"token {tok}", "Accept": "application/vnd.github+json",
        "User-Agent": "ax-image-bank", "Content-Type": ctype})
    try:
        with urllib.request.urlopen(req, timeout=600) as r:
            txt = r.read().decode()
            return r.status, (json.loads(txt) if txt else {})
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:300]}


def release_id(tok: str) -> int:
    st, rel = api(f"/repos/{REPO}/releases/tags/{RELEASE}", tok)
    if st != 200:
        raise SystemExit(f"release {RELEASE} missing: {st} {rel}")
    return rel["id"]


def encode(src: Path, dest: Path) -> tuple[int, int, int] | None:
    """Re-encode one still to a 4K WebP. Returns (w, h, bytes), or None if refused.

    A source smaller than MIN_W is refused rather than upscaled: stretching a
    1280 px photo to 3840 adds no detail and the softness shows on screen. The
    caller keeps the file out of the manifest, so the library stays honestly 4K.
    """
    from PIL import Image  # noqa: PLC0415 - only needed when actually encoding

    try:
        with Image.open(src) as im:
            im = im.convert("RGB")
            if max(im.size) < MIN_W:
                return None
            if max(im.size) > TARGET_W:
                im.thumbnail((TARGET_W, TARGET_W * 2), Image.LANCZOS)
            dest.parent.mkdir(parents=True, exist_ok=True)
            im.save(dest, "WEBP", quality=WEBP_Q, method=4)
            return im.size[0], im.size[1], dest.stat().st_size
    except Exception:  # noqa: BLE001 - one unreadable file must not stop the harvest
        return None


def commons_page(query: str, min_width: int, offset: int, limit: int = 500) -> tuple[list[dict], str | None]:
    """One page of Commons results, plus the token for the next page.

    Commons answers `gsrlimit=500` with 500 pages and a `continue` token, so a
    single query is worth far more than the 8 results `stills_rail.search`
    returns. That depth is what makes a 100k bank possible from ~100 queries.
    """
    import re as _re  # noqa: PLC0415

    import stills_rail  # noqa: PLC0415

    params = {
        "action": "query", "format": "json", "generator": "search",
        "gsrsearch": f"{query} filetype:bitmap", "gsrnamespace": "6",
        "gsrlimit": str(limit), "gsroffset": str(offset),
        "prop": "imageinfo", "iiprop": "url|size|extmetadata|mime",
        # Ask Commons for a 4K render rather than its 1920 thumbnail: the bank is
        # clip material and a 1920 source cannot fill a 4K pan without upscaling.
        "iiurlwidth": str(TARGET_W),
    }
    try:
        data = stills_rail._get_json(f"{stills_rail.API}?{urllib.parse.urlencode(params)}",
                                     timeout=90)
    except Exception:
        return [], None
    out = []
    for page in data.get("query", {}).get("pages", {}).values():
        ii = (page.get("imageinfo") or [{}])[0]
        if not ii or ii.get("mime", "").startswith("image/svg"):
            continue
        if ii.get("width", 0) < min_width:
            continue
        meta = ii.get("extmetadata", {})
        lic = meta.get("LicenseShortName", {}).get("value", "")
        if not stills_rail.OK_LICENCE.search(lic) or stills_rail.BAD_LICENCE.search(lic):
            continue
        out.append({
            "title": page["title"].replace("File:", ""),
            "url": ii.get("thumburl") or ii["url"],
            "source": ii["descriptionurl"],
            "licence": lic,
            "credit": _re.sub(r"<[^>]+>", "", meta.get("Artist", {}).get("value", "")).strip()[:90],
            "width": ii.get("thumbwidth", ii["width"]),
            "height": ii.get("thumbheight", ii["height"]),
            "origin": "Wikimedia Commons",
        })
    nxt = (data.get("continue") or {}).get("gsroffset")
    return out, nxt


def harvest(queries: list[str], want: int, per_query: int, min_width: int,
            sleep_s: float, log=print, budget_s: float = 0.0) -> int:
    """Walk each query's Commons pages, keep what is new, stop at `want`.

    Each query records the offset it reached, so the next run resumes there
    instead of re-fetching page 1 and finding every title already held.

    Three limits bound the walk, because an unbounded one is not a harvest: the
    `want` count, two consecutive "nothing new" pages per query, and a wall-clock
    `budget_s`. Without them, once page 1 of every query was already in the bank
    the loop kept advancing cursors that were never persisted — six runs in a row
    spent the full 120-minute cap and committed nothing.
    """
    import stills_rail  # noqa: PLC0415

    doc = load()
    cursors = doc.setdefault("cursors", {})
    seen_titles = {r["title"] for r in doc["images"]}
    seen_sha = {r["sha"] for r in doc["images"]}
    started = len(doc["images"])
    made = 0
    qi = 0
    exhausted = 0
    stale: dict[str, int] = {}
    deadline = time.monotonic() + budget_s if budget_s else None
    while made < want and exhausted < len(queries):
        if deadline and time.monotonic() >= deadline:
            log(f"  budget {budget_s:.0f}s reached — stopping at {made} new")
            break
        q = queries[qi % len(queries)]
        qi += 1
        offset = int(cursors.get(q, 0))
        items, nxt = commons_page(q, min_width, offset)
        if not items and nxt is None:
            exhausted += 1
            log(f"  {q}: exhausted at offset {offset}")
            continue
        cursors[q] = nxt if nxt is not None else offset
        # Persist the advance even when it finds nothing: a cursor saved only on
        # a successful batch is a cursor the next run throws away.
        save(doc)
        batch = [it for it in items if it["title"] not in seen_titles][:per_query]
        if not batch:
            stale[q] = stale.get(q, 0) + 1
            log(f"  {q}: offset {offset}, nothing new ({stale[q]})")
            if stale[q] >= 2:
                exhausted += 1
            continue
        stale[q] = 0
        exhausted = 0
        got = stills_rail.download(batch, "/tmp/bank-raw", log=lambda m: None)
        for it in got:
            if made >= want:
                break
            src = Path(it["path"])
            sha = hashlib.sha256(src.read_bytes()).hexdigest()[:20]
            if sha in seen_sha:
                src.unlink(missing_ok=True)
                continue
            ident = f"st-{len(doc['images']) + 1:06d}"
            dest = LIB / "img" / f"{ident}.webp"
            enc = encode(src, dest)
            src.unlink(missing_ok=True)
            if not enc:
                continue
            w, h, nbytes = enc
            doc["images"].append({
                "id": ident, "file": str(dest.relative_to(LIB)), "title": it["title"],
                "query": q, "licence": it.get("licence", ""), "origin": it.get("origin", ""),
                "credit": (it.get("credit") or "")[:120], "source": it.get("source", ""),
                "w": w, "h": h, "bytes": nbytes, "sha": sha, "at": _now(), "uses": 0,
            })
            seen_titles.add(it["title"])
            seen_sha.add(sha)
            made += 1
            if made % 25 == 0:
                save(doc)
                log(f"  {made}/{want} new ({len(doc['images'])} total)")
        save(doc)
        if sleep_s:
            time.sleep(sleep_s)
    save(doc)
    log(f"harvest: {made} new, bank {started} -> {len(doc['images'])}")
    return made


def shard(tok: str, dry_run: bool, log=print) -> int:
    """Pack local images into a tar, upload it, then delete what was packed."""
    doc = load()
    packed = {r["id"] for r in doc["images"] if r.get("shard")}
    local = [r for r in doc["images"] if r["id"] not in packed and (LIB / r["file"]).exists()]
    if not local:
        log("shard: nothing local to pack")
        return 0
    total = sum(r["bytes"] for r in local)
    log(f"shard: {len(local)} image(s), {total / 1e6:.1f} MB")

    groups, cur, cur_bytes = [], [], 0
    for r in local:
        if cur and cur_bytes + r["bytes"] > SHARD_MAX:
            groups.append(cur)
            cur, cur_bytes = [], 0
        cur.append(r)
        cur_bytes += r["bytes"]
    if cur:
        groups.append(cur)

    rid = None if dry_run else release_id(tok)
    n = len(doc.get("shards", []))
    for group in groups:
        n += 1
        name = f"bank-{n:04d}.tar"
        buf = io.BytesIO()
        with tarfile.open(fileobj=buf, mode="w") as tf:
            for r in group:
                p = LIB / r["file"]
                info = tf.gettarinfo(str(p), arcname=r["file"])
                with p.open("rb") as fh:
                    tf.addfile(info, fh)
        data = buf.getvalue()
        log(f"  {name}: {len(group)} image(s), {len(data) / 1e6:.1f} MB")
        if dry_run:
            continue
        st, res = api(f"https://uploads.github.com/repos/{REPO}/releases/{rid}/assets"
                      f"?name={name}", tok, "POST", raw=data,
                      ctype="application/octet-stream")
        if st not in (200, 201):
            log(f"  FAIL {name}: {st} {res}")
            return 1
        url = res.get("browser_download_url", "")
        doc.setdefault("shards", []).append({
            "name": name, "url": url, "images": len(group),
            "bytes": len(data), "at": _now(),
            "ids": [r["id"] for r in group]})
        for r in group:
            r["shard"] = name
        save(doc)
        log(f"  up {name} -> {url[-40:]}")
        if not dry_run:
            for r in group:
                (LIB / r["file"]).unlink(missing_ok=True)
    save(doc)
    return 0


def pull(tok: str, limit: int, log=print) -> int:
    """Bring packed files back so a clip can use them. Cached under img/."""
    doc = load()
    by_shard: dict[str, list[dict]] = {}
    for r in doc["images"]:
        if r.get("shard") and not (LIB / r["file"]).exists():
            by_shard.setdefault(r["shard"], []).append(r)
    if not by_shard:
        log("pull: every manifest row is already local")
        return 0
    urls = {s["name"]: s["url"] for s in doc.get("shards", [])}
    got = 0
    for name, rows in by_shard.items():
        if got >= limit:
            break
        url = urls.get(name)
        if not url:
            log(f"  {name}: no url in manifest")
            continue
        want = {r["file"] for r in rows[: limit - got]}
        log(f"  {name}: pulling {len(want)} of {len(rows)}")
        try:
            with urllib.request.urlopen(url, timeout=900) as resp:
                with tarfile.open(fileobj=io.BytesIO(resp.read()), mode="r") as tf:
                    for m in tf.getmembers():
                        if m.name in want:
                            tf.extract(m, LIB, filter="data")
                            got += 1
        except Exception as exc:  # noqa: BLE001
            log(f"  {name}: pull failed ({type(exc).__name__})")
    log(f"pull: {got} file(s) restored")
    return got


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="cmd", required=True)

    h = sub.add_parser("harvest", help="pull stills from the free rail into the bank")
    h.add_argument("--queries", required=True, help="text file, one query per line")
    h.add_argument("--want", type=int, default=500)
    h.add_argument("--per-query", type=int, default=6)
    h.add_argument("--min-width", type=int, default=MIN_W)
    h.add_argument("--sleep", type=float, default=0.0)
    h.add_argument("--budget-s", type=float, default=0.0,
                   help="wall-clock seconds for the walk (0 = no limit); the rail "
                        "must leave time to shard and commit before its job cap")

    s = sub.add_parser("shard", help="pack + upload + free local disk")
    s.add_argument("--dry-run", action="store_true")

    p = sub.add_parser("pull", help="restore packed files from a shard")
    p.add_argument("--limit", type=int, default=50)

    sub.add_parser("stats")
    sub.add_parser("verify")
    a = ap.parse_args()

    if a.cmd == "harvest":
        qs = [ln.strip() for ln in Path(a.queries).read_text().splitlines()
              if ln.strip() and not ln.startswith("#")]
        if not qs:
            raise SystemExit("no queries in that file")
        return 0 if harvest(qs, a.want, a.per_query, a.min_width, a.sleep,
                            log=lambda m: print(m, flush=True),
                            budget_s=a.budget_s) >= 0 else 1

    if a.cmd == "shard":
        return shard(token(), a.dry_run)
    if a.cmd == "pull":
        return 0 if pull(token(), a.limit) >= 0 else 1

    doc = load()
    rows = doc["images"]
    if a.cmd == "verify":
        bad = [r for r in rows if not r.get("shard") and not (LIB / r["file"]).exists()]
        # a row in a shard is reachable by `pull`, so it is not "missing"
        packed = sum(1 for r in rows if r.get("shard"))
        print(f"{len(rows)} row(s): {len(rows) - packed} local, {packed} in shards")
        print(f"{len(bad)} row(s) point at nothing")
        for r in bad[:10]:
            print("  missing", r["id"], r["file"])
        return 1 if bad else 0

    local = sum(1 for r in rows if (LIB / r["file"]).exists())
    packed = sum(1 for r in rows if r.get("shard"))
    disk = sum(r["bytes"] for r in rows if (LIB / r["file"]).exists())
    print(f"images   {len(rows):,}")
    print(f"local    {local:,} ({disk / 1e6:.1f} MB)")
    print(f"in shard {packed:,}")
    print(f"shards   {len(doc.get('shards', [])):,}")
    if rows:
        print(f"avg size {sum(r['bytes'] for r in rows) / len(rows) / 1024:.0f} KB")
        print(f"est 100k {(sum(r['bytes'] for r in rows) / len(rows)) * 100_000 / 1e9:.1f} GB")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
