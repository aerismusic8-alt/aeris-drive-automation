#!/usr/bin/env python3
"""Keep the image bank on PC1's D: drive, and get stills back out for a clip.

K (2026-11-19): "เอาลงไปคลัง pc1 แล้วต้องดึงเอามาใช้เป็นวัตถุดิบสร้างคลิปได้ด้วยนะ"
— put the library on PC1, and it must still be usable as clip material.

Why a second home. The `media-938` release is durable and free, but it is one
HTTP GET per file: fine for a cover, wrong for a clip that wants 40 stills. PC1
has the disk (and K asked for it), so it becomes the working copy. The release
stays the off-site backup and the committed manifest stays the index.

D: is not reachable from the sandbox, so the two directions use the two channels
that do exist — Actions (into PC1) and artifacts (out of PC1):

    # sandbox: place the bank's shards on D: — the `ax-pc1-bank-sync` rail does this
    python3 ops/pc1_bank.py push --from-release

    # PC1 runner: pick stills for a clip and hand them out as an artifact
    python3 ops/pc1_bank.py pull --query "bangkok night" --want 12 --out out

    # sandbox: take that artifact and use it as clip material
    python3 ops/pc1_bank.py fetch --out work/stills

`push` is resumable: a shard whose `.done` marker records the release size is
skipped, so a 20 GB bank does not re-download on every tick. `pull` writes a
`selection.json` beside the files because a clip must carry attribution, and
`fetch` names the run it read instead of guessing.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import random
import shutil
import sys
import tarfile
import urllib.request
import zipfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MANIFEST = ROOT / "music938-1" / "library" / "stock" / "manifest.json"
REPO = "aerismusic8-alt/aeris-drive-automation"
RELEASE_TAG = "media-938"
API = "https://api.github.com"
PULL_WORKFLOW = "ax-pc1-bank-pull.yml"

DEFAULT_BANK = Path(os.environ.get("AX_PC1_BANK", r"D:\AX-bank"))


def token() -> str:
    tok = os.environ.get("AX_GH_TOKEN") or ""
    if tok:
        return tok
    sys.path.insert(0, str(ROOT / "ops"))
    import ax_vault  # noqa: PLC0415

    return ax_vault.kv_get(ax_vault.ensure_anchor(), "axsecrets:gh-workflow-token")["token"]


def api(path: str, tok: str):
    req = urllib.request.Request(f"{API}/{path}",
                                 headers={"Authorization": f"Bearer {tok}",
                                          "Accept": "application/vnd.github+json"})
    with urllib.request.urlopen(req, timeout=90) as r:
        return json.load(r)


def cmd_push(args) -> int:
    bank = Path(args.bank)
    manifest = json.loads(MANIFEST.read_text(encoding="utf-8"))
    shards = sorted({r["shard"] for r in manifest.get("images", []) if r.get("shard")})
    if not shards:
        print("push: the manifest names no shards; run `image_bank.py shard` first")
        return 1

    tok = token()
    assets = {}
    if args.from_release:
        assets = {a["name"]: a for a in api(
            f"repos/{REPO}/releases/tags/{RELEASE_TAG}", tok).get("assets", [])}

    bank.mkdir(parents=True, exist_ok=True)
    marks = bank / ".shards"
    marks.mkdir(exist_ok=True)

    placed = 0
    for name in shards:
        if placed >= args.limit:
            break
        mark = marks / f"{name}.done"
        asset = assets.get(name)
        if mark.exists() and (not asset or int(mark.read_text().strip()) == asset["size"]):
            print(f"  {name}: already on D:, skipping")
            continue
        if not asset:
            print(f"  {name}: NOT in the release — cannot place it on D:")
            return 1

        buf = io.BytesIO()
        req = urllib.request.Request(asset["url"],
                                     headers={"Authorization": f"Bearer {tok}",
                                              "Accept": "application/octet-stream"})
        with urllib.request.urlopen(req, timeout=900) as r:
            shutil.copyfileobj(r, buf, 1 << 20)
        buf.seek(0)
        with tarfile.open(fileobj=buf, mode="r") as tf:
            tf.extractall(bank, filter="data")
        mark.write_text(str(asset["size"]))
        placed += 1
        print(f"  {name}: extracted to {bank} ({asset['size'] // 2**20} MB)")

    shutil.copyfile(MANIFEST, bank / "manifest.json")
    print(f"push: {placed} shard(s) placed under {bank}; manifest copied")
    return 0


def cmd_pull(args) -> int:
    bank = Path(args.bank)
    manifest = json.loads((bank / "manifest.json").read_text(encoding="utf-8"))
    terms = [t for t in args.query.lower().split() if t]
    rows = [r for r in manifest.get("images", [])
            if all(t in json.dumps(r, ensure_ascii=False).lower() for t in terms)]
    if not rows:
        print(f"pull: nothing in the bank matches {args.query!r}")
        return 1

    random.Random(args.seed).shuffle(rows)
    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)

    picked = []
    for row in rows[:args.want]:
        src = bank / row["file"]
        if not src.exists():
            print(f"pull: {row['file']} is not on D: — run `push` first")
            return 1
        shutil.copy2(src, out / Path(row["file"]).name)
        picked.append({"file": Path(row["file"]).name, "title": row.get("title"),
                       "licence": row.get("licence"), "credit": row.get("credit"),
                       "origin": row.get("origin"), "source": row.get("source")})

    (out / "selection.json").write_text(json.dumps(
        {"query": args.query, "count": len(picked), "items": picked},
        ensure_ascii=False, indent=1), encoding="utf-8")
    print(f"pull: {len(picked)} still(s) into {out} + selection.json (licence carried)")
    return 0


def cmd_fetch(args) -> int:
    tok = token()
    runs = api(f"repos/{REPO}/actions/workflows/{PULL_WORKFLOW}/runs"
               f"?status=success&per_page=1", tok).get("workflow_runs", [])
    if not runs:
        print(f"fetch: no completed {PULL_WORKFLOW} run — dispatch one with a query")
        return 1
    run = runs[0]
    arts = api(f"repos/{REPO}/actions/runs/{run['id']}/artifacts", tok).get("artifacts", [])
    art = next((a for a in arts if a["name"] == "bank-stills"), None)
    if not art:
        print(f"fetch: run {run['id']} produced no bank-stills artifact")
        return 1

    out = Path(args.out)
    out.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(art["archive_download_url"],
                                 headers={"Authorization": f"Bearer {tok}"})
    with urllib.request.urlopen(req, timeout=600) as r:
        data = r.read()
    with zipfile.ZipFile(io.BytesIO(data)) as z:
        z.extractall(out)

    sel = out / "selection.json"
    count = json.loads(sel.read_text(encoding="utf-8"))["count"] if sel.exists() else "?"
    print(f"fetch: {count} still(s) from run {run['id']} ({run['head_sha'][:8]}) -> {out}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--bank", default=str(DEFAULT_BANK),
                    help=f"the bank root on PC1 (default {DEFAULT_BANK})")
    sub = ap.add_subparsers(dest="cmd", required=True)

    p = sub.add_parser("push", help="place the bank's shards on PC1's D:")
    p.add_argument("--from-release", action="store_true")
    p.add_argument("--limit", type=int, default=100)
    p.set_defaults(func=cmd_push)

    q = sub.add_parser("pull", help="pick stills off D: for a clip")
    q.add_argument("--query", required=True)
    q.add_argument("--want", type=int, default=12)
    q.add_argument("--out", default="out")
    q.add_argument("--seed", type=int, default=7)
    q.set_defaults(func=cmd_pull)

    f = sub.add_parser("fetch", help="take the newest PC1 pull artifact")
    f.add_argument("--out", default="work/stills")
    f.set_defaults(func=cmd_fetch)

    args = ap.parse_args(argv)
    return args.func(args)


if __name__ == "__main__":
    raise SystemExit(main())
