#!/usr/bin/env python3
"""Announce newly-released songs on AR's own Nostr account.

Nostr is the one social surface AR can hold entirely on its own: the identity is
a self-generated keypair (`ops/ar_nostr.py`), so there is no signup, captcha or
phone gate to block a fresh pod. That makes it the free distribution lane that
never waits on an operator.

This reads `music938-1/work/release-state.json` (the release ledger, tracked in
git) and posts one note per song that has gone public but has not been announced
yet. It is idempotent: the announced video ids live in
`music938-1/work/nostr-announced.json`, so a re-run after a partial failure only
sends what is still missing.

    python3 ops/announce_releases.py --dry-run     # what would be posted
    python3 ops/announce_releases.py               # post it
    python3 ops/announce_releases.py --limit 3     # cap this run

The YouTube id is in the ledger, so the note links straight to the video. No
value is invented: a record with no `video_id` is skipped, never guessed.
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
import ar_nostr  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
STATE = ROOT / "music938-1" / "work" / "release-state.json"
ANNOUNCED = ROOT / "music938-1" / "work" / "nostr-announced.json"
CATALOG = ROOT / "share" / "aeris-music" / "catalog.json"
REPO = "aerismusic8-alt/aeris-drive-automation"
LEDGER_REL = "music938-1/work/nostr-announced.json"

WATCH = "https://www.youtube.com/watch?v="
CHANNEL = "https://www.youtube.com/@aerismusicth"
FOLLOW_ASK = "กดติดตาม AERIS Music"
FOLLOW_PROMISE = "เพลงใหม่ทุกวัน"


def write_remote(payload: dict, tok: str) -> bool:
    """Persist the announced ledger to `main` through the Contents API.

    A CI runner has no git transport, so the ledger travels the same way the
    release ledger does. Without this, the next run reads an empty ledger and
    re-announces the whole catalogue. Best-effort: a failed write costs a
    duplicate note, never a failed release.
    """
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
    body = {"message": "nostr: record announced releases (automated)",
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


def load_released(tok: str = "") -> list[dict]:
    """The release ledger, fresh from `main` when a token is available.

    In CI the checkout is taken before the release step runs, and that step
    writes the ledger through the Contents API rather than into the working
    tree. Reading the checked-out file would therefore announce yesterday's
    batch. Pull the current file first and fall back to disk.
    """
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


def title_of(slug: str) -> str:
    """Thai title for a slug, from the share catalog; the slug if unknown."""
    try:
        data = json.loads(CATALOG.read_text(encoding="utf-8"))
    except Exception:
        return slug
    for row in data.get("songs", []):
        if row.get("id", "").endswith(slug):
            return row.get("title") or slug
    return slug


def note_text(slug: str, video_id: str) -> str:
    """One note: the song, its link, and the standing follow ask."""
    title = title_of(slug)
    return (f"🎵 {title}\n"
            f"{WATCH}{video_id}\n\n"
            f"{FOLLOW_ASK} — {FOLLOW_PROMISE}\n{CHANNEL}")


def pending(released: list[dict], announced: dict, limit: int | None = None) -> list[tuple]:
    """Newly-public songs not yet announced: [(video_id, slug, text)].

    Newest first, so a run that finds a backlog announces the current work before
    older catalogue entries.
    """
    out = []
    for r in reversed(released):
        if not r.get("public") or r.get("kind") != "song":
            continue
        vid = r.get("video_id")
        slug = r.get("slug")
        if not vid or not slug or vid in announced:
            continue
        out.append((vid, slug, note_text(slug, vid)))
        if limit and len(out) >= limit:
            break
    return out


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--dry-run", action="store_true", help="print, do not post")
    ap.add_argument("--limit", type=int, default=None, help="cap notes this run")
    args = ap.parse_args()

    released = load_released(os.environ.get("AX_GH_TOKEN", ""))
    announced = json.loads(ANNOUNCED.read_text(encoding="utf-8")) if ANNOUNCED.exists() else {}
    todo = pending(released, announced, args.limit)
    print(f"{len(todo)} new release(s) to announce")

    posted = 0
    for vid, slug, text in todo:
        if args.dry_run:
            print(f"\n--- {slug} ({vid}) ---\n{text}")
            continue
        ok = ar_nostr.post(text)
        if not ok:
            print(f"  {slug}: no relay accepted, leaving unannounced", file=sys.stderr)
            continue
        announced[vid] = {"slug": slug, "relays": len(ok)}
        posted += 1

    if not args.dry_run and posted:
        ANNOUNCED.parent.mkdir(parents=True, exist_ok=True)
        ANNOUNCED.write_text(json.dumps(announced, ensure_ascii=False, indent=1), encoding="utf-8")
        pushed = write_remote(announced, os.environ.get("AX_GH_TOKEN", ""))
        print(f"posted {posted} note(s); recorded in {ANNOUNCED}"
              f"{' (pushed)' if pushed else ' (local only)'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
