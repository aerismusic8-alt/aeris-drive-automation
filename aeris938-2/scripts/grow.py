#!/usr/bin/env python3
"""One driver for the four aeris938-2 surfaces.

    python3 grow.py status                     # what is queued / posted / live
    python3 grow.py facebook --profile         # fill the Page profile
    python3 grow.py facebook --post --limit 3  # post pending Reels
    python3 grow.py tiktok   --profile
    python3 grow.py tiktok   --post --limit 3
    python3 grow.py youtube  --brand           # banner + channel description
    python3 grow.py youtube  --community --limit 2
    python3 grow.py shopee   --check           # affiliate link + dashboard read

The posting mechanics live in `music938-1/scripts/` and are driven, not copied:
those tools already post to Facebook/TikTok, fill profiles and read dashboards
through the signed-in cloud desktop, which is the only free route (Rule #1).
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
from collections import Counter
from pathlib import Path

import surfaces

MUSIC = surfaces.MUSIC


def _run(tool: str, *args: str) -> int:
    """Run a proven music938-1 tool with its own working directory."""
    cmd = [sys.executable, str(surfaces.tool(tool)), *args]
    print(f"$ {' '.join(cmd[len(cmd) - len(args) - 1:])}", flush=True)
    return subprocess.call(cmd, cwd=str(MUSIC))


def _read_json(path: Path, default):
    try:
        return json.loads(path.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return default


# Which crosspost state key holds the posts for each surface. Facebook is
# "facebook-page", not "facebook": the 60 pre-Page posts went to the personal
# profile and must not count as Page posts.
STATE_KEY = {"tiktok": "tiktok", "facebook": "facebook-page"}


def _posted_counts() -> Counter:
    state = _read_json(MUSIC / "work" / "crosspost-state.json", {})
    return Counter(k.split(":", 1)[0] for k in state.get("posted", {}))


def _pending_counts() -> Counter:
    """Queue items that have not been posted yet (the real backlog)."""
    queue = _read_json(MUSIC / "work" / "crosspost-queue.json", [])
    posted = _read_json(MUSIC / "work" / "crosspost-state.json", {}).get("posted", {})
    return Counter(i.get("platform", "?") for i in queue if i.get("id") not in posted)


def cmd_status(args) -> int:
    cfg = surfaces.config()
    posted, pending = _posted_counts(), _pending_counts()
    print("aeris938-2 — 4 surfaces\n")
    print(f"{'surface':16} {'account':28} {'posted':>7} {'pending':>7}")
    print("-" * 62)
    rows = [
        ("facebook", cfg["facebook"]["page_id"]),
        ("tiktok", cfg["tiktok"]["handle"]),
        ("youtube", cfg["youtube"]["handle"]),
        ("shopee_affiliate", cfg["shopee_affiliate"]["short"]),
    ]
    for key, acct in rows:
        # crosspost is FB/TikTok only; YouTube/Shopee have no queue file.
        # `posted` is keyed by state key (facebook-page), `pending` by platform.
        fb = key in ("facebook", "tiktok")
        print(f"{key:16} {acct:28} "
              f"{(str(posted.get(STATE_KEY.get(key, key), 0)) if fb else '-'):>7} "
              f"{(str(pending.get(key, 0)) if fb else '-'):>7}")

    yt = _read_json(MUSIC / "work" / "market-snapshot.json", {})
    cs = yt.get("channel_stats") or {}
    if cs:
        print(f"\nYouTube @aerismusicth: {cs.get('subs', 'UNKNOWN')} subs, "
              f"{cs.get('videos', 'UNKNOWN')} videos, "
              f"{cs.get('views', 'UNKNOWN')} views")
    else:
        print("\nYouTube @aerismusicth: UNKNOWN (no market-snapshot.json yet)")
    print("\nงานค้าง: Facebook มี Reels ค้าง (TikTok ไม่มี) — "
          "`grow.py facebook --post`; Shopee onboarded แล้ว (ดู report)")
    return 0


def cmd_facebook(args) -> int:
    if args.queue:
        return _run("crosspost.py", "--rebuild-queue")
    if args.profile:
        return _run("profile_setup.py", "facebook")
    if args.welcome:
        return _run("profile_setup.py", "welcome")
    if args.post:
        return _run("crosspost.py", "--post", "--platform", "facebook",
                    "--limit", str(args.limit))
    if args.follow:
        return _run("outreach.py", "--follow", "--limit", str(args.limit))
    if args.invite:
        return _run("outreach.py", "--invite")
    print("nothing to do: pass --queue, --profile, --welcome, --post, --follow "
          "or --invite", file=sys.stderr)
    return 2


def cmd_tiktok(args) -> int:
    if args.queue:
        return _run("crosspost.py", "--rebuild-queue")
    if args.profile:
        return _run("profile_setup.py", "tiktok")
    if args.post:
        return _run("crosspost.py", "--post", "--platform", "tiktok",
                    "--limit", str(args.limit))
    print("nothing to do: pass --queue, --profile or --post", file=sys.stderr)
    return 2


def cmd_youtube(args) -> int:
    if args.brand:
        return _run("apply_brand.py")
    if args.community:
        return _run("post_community.py", "--post", "--limit", str(args.limit))
    print("nothing to do: pass --brand or --community", file=sys.stderr)
    return 2


def cmd_shopee(args) -> int:
    if args.check:
        # social_stats.py already reads the affiliate dashboard through the
        # desktop; --json gives the machine form without writing a report.
        rc = _run("social_stats.py", "--json")
        return rc
    print("nothing to do: pass --check", file=sys.stderr)
    return 2


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = ap.add_subparsers(dest="surface", required=True)

    def add(name, profile=False, post=False, queue=False, brand=False,
            community=False, check=False, follow=False, invite=False,
            welcome=False):
        p = sub.add_parser(name)
        if queue:
            p.add_argument("--queue", action="store_true",
                           help="rebuild the Shorts queue from disk")
        if profile:
            p.add_argument("--profile", action="store_true", help="fill the profile")
        if post:
            p.add_argument("--post", action="store_true", help="post pending items")
        if follow:
            p.add_argument("--follow", action="store_true",
                           help="follow suggested pages (grow the Page)")
        if post or follow:
            p.add_argument("--limit", type=int, default=5)
        if invite:
            p.add_argument("--invite", action="store_true",
                           help="invite friends to like the Page")
        if welcome:
            p.add_argument("--welcome", action="store_true",
                           help="post + pin the front-door welcome post")
        if brand:
            p.add_argument("--brand", action="store_true", help="banner + description")
        if community:
            p.add_argument("--community", action="store_true", help="community post")
            p.add_argument("--limit", type=int, default=2)
        if check:
            p.add_argument("--check", action="store_true", help="read the dashboard")
        return p

    sub.add_parser("status")
    add("facebook", profile=True, post=True, queue=True, follow=True, invite=True,
        welcome=True)
    add("tiktok", profile=True, post=True, queue=True)
    add("youtube", brand=True, community=True)
    add("shopee", check=True)

    args = ap.parse_args(argv)
    return {
        "status": cmd_status,
        "facebook": cmd_facebook,
        "tiktok": cmd_tiktok,
        "youtube": cmd_youtube,
        "shopee": cmd_shopee,
    }[args.surface](args)


if __name__ == "__main__":
    raise SystemExit(main())
