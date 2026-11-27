"""The Facebook Page's week: what it has, what it should post, what is wrong.

K's rule is Graph API only (2026-11-15), so this reads and writes through
`ops/fb_graph.py` and never opens a browser. The Page's own numbers are the only
honest starting point: a page with 2 followers and no reach does not need a
content calendar, it needs to know whether anything it posts is seen at all.

Three verbs, each safe to re-run:

- `--report`  writes `work/fb-page-report.json` and prints the diagnosis.
- `--plan`    proposes the week's posts from the **unpublished** choruses, one
              per day, with copy taken from `release.py` and `branding.py`.
- `--about`   sets the Page description from `branding.DESCRIPTION`
              (`--apply` to write; the default is a dry run).

A missing token is reported as `reachable: false`, never as zeros.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPTS = ROOT / "music938-1" / "scripts"
sys.path.insert(0, str(ROOT / "ops"))
sys.path.insert(0, str(SCRIPTS))

WORK = ROOT / "music938-1" / "work"
REPORT = WORK / "fb-page-report.json"
PLAN = WORK / "fb-page-plan.json"
CHORUS_LEDGER = WORK / "published-choruses.json"
BANK = ROOT / "music938-1" / "library" / "bank"

POSTS_PER_WEEK = 7
ABOUT_MAX = 255


def load_choruses() -> dict:
    try:
        return json.loads(CHORUS_LEDGER.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def bank_choruses() -> list[tuple[str, int, Path]]:
    """(slug, hook, clip) for every rendered clip in the bank."""
    import bank_publish  # noqa: PLC0415

    out = []
    for clip in sorted(BANK.glob("*.mp4")):
        key = bank_publish.chorus_key(clip)
        if not key:
            continue
        slug, _, hook = key.partition("#h")
        out.append((slug, int(hook), clip))
    return out


def unused(bank: list[tuple[str, int, Path]], ledger: dict) -> list[tuple[str, int, Path]]:
    """The clips whose audio the Page has not published yet."""
    return [row for row in bank if f"{row[0]}#h{row[1]}" not in ledger]


def post_copy(slug: str, hook: int) -> str:
    """The caption for one chorus: the song, the hook prompt, the follow ask.

    Read from the same two modules the uploads use, so the Page cannot drift into
    a second brand voice (`branding.py` is the only place the name lives).
    """
    import release  # noqa: PLC0415
    from branding import FOLLOW_ASK, FOLLOW_PROMISE, HASHTAGS  # noqa: PLC0415

    title = release.parse_lyrics(slug).get("TITLE", slug)
    return (
        f"🎵 {title} — {release.hook_title(hook)}\n\n"
        f"ร้องตามได้เลย 👇\n\n"
        f"{FOLLOW_ASK} · {FOLLOW_PROMISE}\n"
        f"{HASHTAGS}"
    )


def plan_week(limit: int = POSTS_PER_WEEK) -> dict:
    """The week's posts: one unpublished chorus a day, never a repeat."""
    rows = unused(bank_choruses(), load_choruses())[:limit]
    posts = []
    for slug, hook, clip in rows:
        posts.append({
            "slug": slug,
            "hook": hook,
            "clip": clip.name,
            "caption": post_copy(slug, hook),
        })
    return {
        "generated": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%MZ"),
        "bank_clips": len(bank_choruses()),
        "already_published": len(load_choruses()),
        "unused": len(unused(bank_choruses(), load_choruses())),
        "posts": posts,
        "short": max(0, limit - len(posts)),
    }


def diagnose(report: dict, plan: dict) -> list[str]:
    """What is wrong, in the order it should be fixed."""
    notes: list[str] = []
    if not report.get("reachable"):
        notes.append(
            "Page numbers unavailable (no FB_PAGE_TOKEN here) — this run can plan "
            "but must not claim a number it did not read.")
    followers = report.get("followers")
    if isinstance(followers, int) and followers < 100:
        notes.append(
            f"{followers} followers: at this size reach is the whole problem, not "
            f"variety. Post the same shape every day and let one format win.")
    views = report.get("views_28d")
    if isinstance(views, int) and views == 0:
        notes.append(
            "0 page views in 28 days: the Page is invisible. A post that nobody "
            "sees is a draft — put the link in front of the YouTube audience too.")
    if plan["unused"] == 0:
        notes.append(
            "no unpublished chorus left in the bank: the Page needs new renders, "
            "not a new calendar.")
    elif plan["short"] > 0:
        notes.append(
            f"{plan['short']} of {POSTS_PER_WEEK} days have no fresh chorus; "
            f"re-running a chorus is a repeat and the ledger refuses it.")
    if not notes:
        notes.append("Page numbers are readable and the bank has fresh choruses.")
    return notes


def about_text() -> str:
    from branding import DESCRIPTION, FOLLOW_ASK, FOLLOW_PROMISE  # noqa: PLC0415

    text = f"{DESCRIPTION}\n{FOLLOW_ASK} · {FOLLOW_PROMISE}"
    return text[:ABOUT_MAX]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--report", action="store_true", help="read the Page and diagnose")
    ap.add_argument("--plan", action="store_true", help="propose the week's posts")
    ap.add_argument("--about", action="store_true", help="set the Page description")
    ap.add_argument("--apply", action="store_true", help="with --about: actually write")
    ap.add_argument("--limit", type=int, default=POSTS_PER_WEEK)
    a = ap.parse_args(argv)
    if not (a.report or a.plan or a.about):
        ap.error("nothing to do: pass --report, --plan or --about")

    import fb_graph  # noqa: PLC0415

    if a.report or a.plan:
        report = fb_graph.page_insights()
        fields = fb_graph.page_fields() or {}
        report["page"] = {k: fields.get(k) for k in ("name", "about")}
        plan = plan_week(a.limit)
        for note in diagnose(report, plan):
            print(f"- {note}")
        if a.report:
            WORK.mkdir(parents=True, exist_ok=True)
            REPORT.write_text(json.dumps(report, ensure_ascii=False, indent=1) + "\n",
                              encoding="utf-8")
            print(f"wrote {REPORT.relative_to(ROOT)}")
        if a.plan:
            PLAN.write_text(json.dumps(plan, ensure_ascii=False, indent=1) + "\n",
                            encoding="utf-8")
            print(f"wrote {PLAN.relative_to(ROOT)}  ({len(plan['posts'])} posts)")
            for p in plan["posts"]:
                print(f"  {p['slug']}#h{p['hook']}  {p['clip']}")

    if a.about:
        text = about_text()
        if not a.apply:
            print("about (dry run; --apply to write):")
            print(text)
            return 0
        ok = fb_graph.set_page_about(text)
        print(f"about set: {ok}")
        return 0 if ok else 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
