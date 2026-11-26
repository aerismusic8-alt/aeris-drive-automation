#!/usr/bin/env python3
"""Add the long-form volume link to the descriptions of the clips that already work.

New clips carry the volume pointer (`bank_publish.long_form_line`). The clips
that already have views do not, and they are the ones that can move a viewer
today: the audit of 2026-11-26 found one compilation holding 55.5% of the
channel's watch time while the twenty most-viewed clips pointed at nothing.

The edit is description-only and additive. `videos.update` replaces the whole
`snippet`, so every field it can overwrite (title, tags, category, language) is
read back and sent unchanged; only the description gains a paragraph. A video
whose description already carries the link is skipped, so re-running is safe.

    python3 ops/yt_crosslink.py --ch ch3 --top 20            # show the plan
    python3 ops/yt_crosslink.py --ch ch3 --top 20 --apply    # write it
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "music938-1" / "scripts"))
import yt_auth  # noqa: E402

STATE = Path(__file__).resolve().parents[1] / "music938-1" / "work" / "yt-crosslink.json"


def volume_line() -> str:
    import bank_publish  # noqa: PLC0415

    return bank_publish.long_form_line()


def short_enough(item: dict, max_seconds: int) -> bool:
    import yt_audit  # noqa: PLC0415

    return yt_audit.iso_duration(item.get("contentDetails", {}).get("duration", "")) <= max_seconds


def plan(items: list[dict], line: str, top: int) -> list[dict]:
    """Pick the most-viewed public clips that do not yet carry the link."""
    picked = []
    for it in sorted(items, key=lambda i: int(i.get("statistics", {}).get("viewCount", 0)),
                      reverse=True):
        if it.get("status", {}).get("privacyStatus") != "public":
            continue
        desc = it.get("snippet", {}).get("description", "")
        if line and line in desc:
            continue
        picked.append(it)
        if len(picked) >= top:
            break
    return picked


def new_description(desc: str, line: str) -> str:
    body = desc.rstrip()
    return (body + "\n\n" + line).strip() if body else line


def snippet_payload(item: dict, line: str) -> dict:
    """The full `snippet` for a PUT, with only the description changed.

    `videos.update` replaces the resource it is given, so a payload carrying only
    the description would drop the title, the tags and the language.
    """
    sn = item["snippet"]
    body = {
        "title": sn["title"],
        "description": new_description(sn.get("description", ""), line),
        "categoryId": sn.get("categoryId", "10"),
    }
    for key in ("tags", "defaultLanguage", "defaultAudioLanguage"):
        if sn.get(key):
            body[key] = sn[key]
    return {"id": item["id"], "snippet": body}


def update(token: str, item: dict, line: str) -> tuple[int, dict]:
    return yt_auth.api_request("videos", token, snippet_payload(item, line),
                               method="PUT", part="snippet")


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--ch", default="ch3")
    ap.add_argument("--top", type=int, default=20)
    ap.add_argument("--max-seconds", type=int, default=600,
                    help="only clips at or under this length (default 10 min)")
    ap.add_argument("--apply", action="store_true")
    a = ap.parse_args(argv)

    line = volume_line()
    if not line:
        print("no volume state; nothing to link")
        return 2

    tok = yt_auth.access_token(a.ch)
    ids = yt_auth.all_upload_ids(tok)
    st, items = yt_auth.get_videos(tok, ids, part="snippet,statistics,status,contentDetails")
    if st != 200:
        raise SystemExit(f"videos.list {st}")
    clips = [i for i in items if short_enough(i, a.max_seconds)]
    todo = plan(clips, line, a.top)
    print(f"{len(items)} uploads, {len(clips)} clips <= {a.max_seconds}s, "
          f"{len(todo)} to link")
    for it in todo:
        print(f"  {it['statistics'].get('viewCount', '0'):>5} views  {it['snippet']['title'][:60]}")

    if not a.apply:
        print("\ndry run; pass --apply to write")
        return 0

    done, failed = [], []
    for it in todo:
        st, body = update(tok, it, line)
        ok = st == 200
        (done if ok else failed).append({
            "id": it["id"], "title": it["snippet"]["title"], "status": st,
            **({} if ok else {"error": str(body)[:200]}),
        })
        print(f"  {'ok  ' if ok else 'FAIL'} {it['id']} {it['snippet']['title'][:50]}")

    record = {
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "line": line, "channel": a.ch,
        "updated": done, "failed": failed,
    }
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(record, ensure_ascii=False, indent=1) + "\n", encoding="utf-8")
    print(f"\nupdated {len(done)}, failed {len(failed)} -> {STATE}")
    return 0 if not failed else 1


if __name__ == "__main__":
    raise SystemExit(main())
