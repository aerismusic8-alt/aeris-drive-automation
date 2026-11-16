#!/usr/bin/env python3
"""Publish one Telegraph page per released song — a search-indexable surface.

Nostr gives a song a feed entry; Telegraph gives it a page a search engine can
rank, with the video linked. Both are surfaces AR holds alone, so this rail needs
no operator.

Reads the release ledger (`music938-1/work/release-state.json`) and publishes a
page for each public song not yet on Telegraph. Idempotent: the published slugs
live in `music938-1/work/telegraph-published.json`, so a re-run only sends what
is missing. No value is invented — a record with no `video_id` is skipped.

    python3 ops/publish_telegraph.py --dry-run     # what would be published
    python3 ops/publish_telegraph.py               # publish it
    python3 ops/publish_telegraph.py --limit 3     # cap this run

The access token comes from `AR_TELEGRAPH_TOKEN` (CI) or AR's identity dir (pod).
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ar_telegraph  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
STATE = ROOT / "music938-1" / "work" / "release-state.json"
PUBLISHED = ROOT / "music938-1" / "work" / "telegraph-published.json"
CATALOG = ROOT / "share" / "aeris-music" / "catalog.json"
REPO = "aerismusic8-alt/aeris-drive-automation"
LEDGER_REL = "music938-1/work/telegraph-published.json"

WATCH = "https://www.youtube.com/watch?v="
CHANNEL = "https://www.youtube.com/@aerismusicth"


def token() -> str:
    """The Telegraph access token: CI secret first, then AR's identity dir."""
    env = os.environ.get("AR_TELEGRAPH_TOKEN")
    if env:
        return env.strip()
    try:
        return ar_telegraph.load()["access_token"]
    except SystemExit:
        return ""


def title_of(slug: str) -> str:
    try:
        data = json.loads(CATALOG.read_text(encoding="utf-8"))
    except Exception:
        return slug
    for row in data.get("songs", []):
        if row.get("id", "").endswith(slug):
            return row.get("title") or slug
    return slug


def page_text(slug: str, video_id: str) -> str:
    """The page body: what the song is, and where to hear it, then the ask."""
    title = title_of(slug)
    return (
        f"เพลง “{title}”\n\n"
        f"ฟังเพลงเต็มได้ที่: {WATCH}{video_id}\n\n"
        f"ติดตามเพลงใหม่ทุกวันได้ที่ช่อง AERIS Music: {CHANNEL}"
    )


def load_released(tok: str = "") -> list[dict]:
    if tok:
        url = f"https://api.github.com/repos/{REPO}/contents/{STATE.relative_to(ROOT).as_posix()}"
        try:
            r = urllib.request.Request(
                url, headers={"Authorization": f"token {tok}",
                              "Accept": "application/vnd.github+json"})
            with urllib.request.urlopen(r, timeout=30) as resp:
                blob = json.loads(resp.read())
                return json.loads(base64.b64decode(blob["content"])).get("released", [])
        except Exception:
            pass
    return json.loads(STATE.read_text(encoding="utf-8")).get("released", [])


def load_published(tok: str = "") -> dict:
    """The published ledger, fresh from `main` when a token is available.

    In CI the checkout can predate the previous run's Contents-API write, so
    reading the checked-out file would re-publish yesterday's batch (it did, on
    2026-11-16: two songs got a duplicate `-2` page). Pull the current file
    first and fall back to disk.
    """
    if tok:
        url = f"https://api.github.com/repos/{REPO}/contents/{LEDGER_REL}"
        try:
            r = urllib.request.Request(
                url, headers={"Authorization": f"token {tok}",
                              "Accept": "application/vnd.github+json"})
            with urllib.request.urlopen(r, timeout=30) as resp:
                blob = json.loads(resp.read())
                return json.loads(base64.b64decode(blob["content"]))
        except Exception:
            pass
    try:
        return json.loads(PUBLISHED.read_text(encoding="utf-8"))
    except Exception:
        return {}


def pending(released: list[dict], published: dict, limit: int | None = None) -> list[dict]:
    out = []
    for r in reversed(released):
        if not r.get("public") or r.get("kind") != "song":
            continue
        if not r.get("video_id"):
            continue
        if r.get("slug") in published:
            continue
        out.append(r)
    return out[:limit] if limit else out


def write_remote(payload: dict, tok: str) -> bool:
    """Persist the published ledger to `main` via the Contents API (as the
    Nostr announcer does); a CI runner has no git transport. Best-effort."""
    if not tok:
        return False
    api = f"https://api.github.com/repos/{REPO}/contents/{LEDGER_REL}"

    def req(method, body=None):
        r = urllib.request.Request(api, method=method,
                                   headers={"Authorization": f"token {tok}",
                                            "Accept": "application/vnd.github+json"})
        with urllib.request.urlopen(
                r, data=json.dumps(body).encode() if body else None, timeout=30) as resp:
            return resp.status, json.loads(resp.read() or b"{}")

    try:
        st, cur = req("GET")
        sha = cur.get("sha") if st == 200 else None
    except Exception:
        sha = None
    body = {"message": "telegraph: record published pages (automated)",
            "content": base64.b64encode(
                json.dumps(payload, ensure_ascii=False, indent=1).encode()).decode(),
            "branch": "main"}
    if sha:
        body["sha"] = sha
    try:
        st, _ = req("PUT", body)
        return st in (200, 201)
    except Exception as exc:  # noqa: BLE001
        print(f"ledger push failed: {exc}", file=sys.stderr)
        return False


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--limit", type=int, default=None)
    args = ap.parse_args(argv)

    tok = token()
    gh = os.environ.get("AX_GH_TOKEN") or os.environ.get("GITHUB_TOKEN") or ""
    published = load_published(gh)
    todo = pending(load_released(gh), published, args.limit)
    print(f"{len(todo)} song(s) to publish on Telegraph")
    if args.dry_run:
        for r in todo:
            print(f"  would publish: {r['slug']} -> {WATCH}{r['video_id']}")
        return 0
    if not tok:
        print("no Telegraph token (set AR_TELEGRAPH_TOKEN or run ar_telegraph.py create)")
        return 1

    done = 0
    for r in todo:
        try:
            res = ar_telegraph.page(title_of(r["slug"]), page_text(r["slug"], r["video_id"]),
                                    author_url=CHANNEL, token=tok)
        except SystemExit as exc:
            print(f"  {r['slug']}: {exc}", file=sys.stderr)
            continue
        published[r["slug"]] = {"url": res["url"], "video_id": r["video_id"]}
        done += 1
        print(f"  published {r['slug']} -> {res['url']}")

    if done:
        if gh:
            write_remote(published, gh)
        else:
            PUBLISHED.parent.mkdir(parents=True, exist_ok=True)
            PUBLISHED.write_text(json.dumps(published, ensure_ascii=False, indent=1))
    print(f"published {done}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
