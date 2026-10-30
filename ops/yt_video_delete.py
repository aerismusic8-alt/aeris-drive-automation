#!/usr/bin/env python3
"""Delete YouTube videos — duplicates and low-quality output.

K's rule (2026-10-24): "อันไหนซ้ำ อันไหนไม่มีคุณภาพลบออกจากช่อง ... ไม่ต้องเก็บ
เดี๋ยวไดร์ฟเต็ม". Delete the duplicate and the worthless; keep the best copy.

A delete is irreversible, so this tool refuses to guess:
  * a bare id list is REQUIRED; it never scans and deletes on its own
  * `--dry-run` is the default; you must pass `--yes` to actually delete
  * every candidate's full metadata is written to a JSON backup first
  * an id with views above `--max-views` (default 5) is skipped unless `--force`

Usage
-----
    python3 ops/yt_video_delete.py plan  ch2 2hu2WRns5C0 hAGWEuLOGzQ
    python3 ops/yt_video_delete.py apply ch2 2hu2WRns5C0 hAGWEuLOGzQ --yes
"""
from __future__ import annotations

import argparse
import json
import os
import sys
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import yt_auth

BACKUP = Path("out/delete_backup")


def fetch(token, ids):
    rows = []
    for k in range(0, len(ids), 50):
        for attempt in range(4):
            st, body = yt_auth.api_get(
                "videos", token,
                part="snippet,status,contentDetails,statistics",
                id=",".join(ids[k:k + 50]))
            if "items" in body:
                break
            time.sleep(3)
        rows += body.get("items", [])
    return rows


def delete(token, vid):
    """DELETE with NO body.

    yt_auth.api_request serialises the payload, so passing None sends the literal
    `null` and Google answers 400 with 'Invalid JSON payload received. Unknown
    name, Root element must be a message'. A DELETE must carry no body at all.
    DELETE is not blocked by the sandbox proxy (unlike POST/PATCH), so this
    reaches the real API.
    """
    url = f"{yt_auth.API}/videos?id={vid}"
    req = urllib.request.Request(url, headers={
        "Authorization": f"Bearer {token}"}, method="DELETE")
    try:
        with urllib.request.urlopen(req, timeout=120) as f:
            return f.status, f.read().decode(errors="replace")
    except urllib.error.HTTPError as e:
        return e.code, e.read().decode(errors="replace")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("mode", choices=["plan", "apply"])
    ap.add_argument("channel", help="ch1 | ch2 | ch3 | ch4")
    ap.add_argument("ids", nargs="*")
    ap.add_argument("--ids-file", help="read ids from a file, one per line "
                                      "(needed for ids starting with '-')")
    ap.add_argument("--yes", action="store_true", help="actually delete")
    ap.add_argument("--force", action="store_true", help="allow deleting a video with views")
    ap.add_argument("--max-views", type=int, default=5)
    args = ap.parse_args()

    ids = list(args.ids)
    if args.ids_file:
        ids += [ln.strip() for ln in Path(args.ids_file).read_text().splitlines() if ln.strip()]
    if not ids:
        ap.error("no ids given (positional or --ids-file)")

    tok = yt_auth.access_token(args.channel)
    rows = fetch(tok, ids)
    found = {v["id"]: v for v in rows}

    missing = [i for i in ids if i not in found]
    if missing:
        print(f"NOT FOUND on {args.channel}: {missing}")

    BACKUP.mkdir(parents=True, exist_ok=True)
    stamp = time.strftime("%Y%m%d-%H%M%S")
    backup = BACKUP / f"{args.channel}-{stamp}.json"
    backup.write_text(json.dumps(rows, ensure_ascii=False, indent=1))
    print(f"backup -> {backup}  ({len(rows)} videos)")

    to_delete = []
    for v in rows:
        views = int(v["statistics"].get("viewCount", 0))
        dur = v["contentDetails"]["duration"]
        print(f"  {v['id']}  {v['status']['privacyStatus']:>8}  {dur:>8}  "
              f"views={views:>4}  {v['snippet']['title'][:52]}")
        if views > args.max_views and not args.force:
            print(f"    SKIP: {views} views > --max-views {args.max_views} "
                  f"(pass --force to override)")
            continue
        to_delete.append(v["id"])

    print(f"\nwill delete {len(to_delete)} of {len(ids)}: {to_delete}")
    if args.mode == "plan" or not args.yes:
        print("dry run — nothing deleted (pass `apply ... --yes`)")
        return

    ok = 0
    for vid in to_delete:
        st, body = delete(tok, vid)
        note = "" if st in (200, 204) else f"  <- {str(body)[:200]}"
        print(f"  DELETE {vid} -> HTTP {st}{note}")
        if st in (200, 204):
            ok += 1
        time.sleep(1)
    print(f"\ndeleted {ok}/{len(to_delete)}")


if __name__ == "__main__":
    main()
