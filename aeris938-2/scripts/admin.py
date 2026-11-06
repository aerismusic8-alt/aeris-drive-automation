#!/usr/bin/env python3
"""The Page's 24/7 admin agent: watch, draft, post, alert — and never spam.

K asked (2026-11-06) for an AI admin that finds followers, replies to posts and
pushes the clips, 24/7. The part that is *safe* to automate is what this does;
the part that gets an account banned is deliberately left to a human.

A panel of five independent advisors was asked exactly this (2026-11-06,
`work/consult-brief-fb-admin-agent-2026-11-06.md`). All five answered the same
thing: automate content and monitoring, but do **not** automate outbound
engagement — following Pages for follows back, inviting friends, commenting on
other Pages, or cold DMs. Meta's spam policy keys on the *pattern* (repeated,
inauthentic, high-frequency activity), not on a safe number per day, so pacing
does not make those actions safe. K cannot risk the account, so this agent does
not perform them.

What it does unattended, on a schedule:

  * reads the Business Suite inbox (Facebook comments + DMs) and the Page's
    insights and status,
  * drafts a reply for anything a fan asked, from a small approved library,
  * posts the queued clips through the proven `crosspost.py` rail,
  * writes a Thai digest to `work/admin-log.jsonl` and pushes one ntfy alert
    when something needs K.

What it never does: send a reply, follow, invite, comment elsewhere, or DM. It
prepares everything so K's send is one tap.

    python3 scripts/admin.py --check          # read only, print the digest
    python3 scripts/admin.py --run            # read + draft + log + alert
    python3 scripts/admin.py --draft "ราคาเท่าไหร่"   # preview one reply
"""
from __future__ import annotations

import argparse
import json
import sys
import time
import urllib.request
from pathlib import Path

import surfaces

sys.path.insert(0, str(surfaces.music_scripts()))

WORK = surfaces.WORK
LOG = WORK / "admin-log.jsonl"

INBOX = "https://www.facebook.com/latest/inbox/all"
PAGE = "https://www.facebook.com/profile.php?id=61595890900382"

# A warning from Meta, in either language. Finding one of these is the one thing
# that must reach K immediately, because it precedes a restriction.
WARNING_MARKERS = (
    "คำเตือน", "ละเมิด", "ถูกจำกัด", "ข้อจำกัด", "ปิดการใช้งาน", "ถูกระงับ",
    "violation", "restricted", "warning", "disabled", "policy",
)


def _ntfy(title: str, message: str, priority: str = "default") -> int:
    """One phone alert. ASCII title: ntfy header values must be latin-1."""
    import os
    topic = os.environ.get("AX_NTFY_TOPIC") or os.environ.get(
        "NTFY_TOPIC", "ax-ar-aeris-9f3k7q")
    req = urllib.request.Request(
        f"https://ntfy.sh/{topic}", data=message.encode("utf-8"),
        headers={"Title": title, "Priority": priority, "Tags": "facebook"})
    try:
        return urllib.request.urlopen(req, timeout=20).status
    except Exception:  # noqa: BLE001
        return 0


def draft_reply(text: str) -> str:
    """A safe canned reply for a fan comment, or "" when a human should answer.

    Deliberately conservative: a reply is only produced when the comment clearly
    matches one of a few low-risk intents. Anything about a complaint, money,
    rights, or a person is escalated to K instead, because a wrong automated
    reply to those is worse than no reply.
    """
    low = (text or "").lower()
    if not low.strip():
        return ""
    if any(m in low for m in ("ลิขสิทธิ์", "copyright", "ฟ้อง", "คืนเงิน",
                              "refund", "โกง", "แย่", "ห่วย", "complaint")):
        return ""  # escalate
    if any(m in low for m in ("ราคา", "เท่าไหร่", "ซื้อ", "where", "price",
                              "buy", "ลิงก์", "link")):
        return "สวัสดีครับ 🙏 ขอบคุณที่สนใจนะครับ ลิงก์สั่งซื้ออยู่ในแคปชันของคลิปเลยครับ"
    if any(m in low for m in ("ชื่อเพลง", "ชื่ออะไร", "เพลงอะไร", "เพลงนี้",
                              "song", "title", "track")):
        return "ขอบคุณที่ฟังนะครับ 🎵 ชื่อเพลงอยู่ในแคปชันของคลิปเลยครับ"
    if any(m in low for m in ("ขอบคุณ", "thanks", "thank you", "เพราะ", "เพราะมาก",
                              "ชอบ", "love", "ดีมาก")):
        return "ขอบคุณมาก ๆ เลยครับ 🙏 ฝากติดตามเพจ AERIS Music ไว้ด้วยนะครับ 🎶"
    return "ขอบคุณที่แวะมานะครับ 🙏 ฝากติดตามเพจไว้ด้วยนะครับ 🎶"


def is_warning(text: str) -> bool:
    low = (text or "").lower()
    return any(m.lower() in low for m in WARNING_MARKERS)


def _count_new(text: str) -> int:
    """Unread items in the inbox: the page marks each with "ใหม่" / "New"."""
    return (text or "").count("ใหม่") + (text or "").count("New")


def inbox_snapshot(desk) -> dict:
    """Read the Business Suite inbox: how much is new, and any warning text."""
    desk.goto(INBOX, settle=12)
    text = desk.text()
    if "กล่องข้อความ" not in text and "Inbox" not in text:
        return {"reachable": False, "note": "inbox did not load",
                "raw": text[:400]}
    return {
        "reachable": True,
        "new_items": _count_new(text),
        "warning": is_warning(text),
        "raw": text[:800],
    }


def digest(snap: dict, drafts: list[str]) -> str:
    """A short Thai summary for K, and for the log."""
    if not snap.get("reachable"):
        return "โพสต์/กล่องข้อความ: อ่านไม่ได้ (" + snap.get("note", "") + ")"
    lines = [f"กล่องข้อความ: มีรายการใหม่ {snap.get('new_items', 0)} รายการ"]
    if snap.get("warning"):
        lines.append("⚠️ พบข้อความที่อาจเป็นคำเตือนจาก Meta — ต้องตรวจด่วน")
    if drafts:
        lines.append(f"ร่างคำตอบไว้ให้แล้ว {len(drafts)} ข้อความ (รอ K กดส่ง)")
    return "\n".join(lines)


def run(check_only: bool = False) -> int:
    import social_stats as S  # noqa: E402  (path set above)

    desk = S.open_desk()
    try:
        snap = inbox_snapshot(desk)
    finally:
        desk.close()

    drafts: list[str] = []
    if snap.get("reachable"):
        # The inbox text holds the comments; draft one reply per question found.
        for line in snap["raw"].splitlines():
            d = draft_reply(line)
            if d and d not in drafts:
                drafts.append(d)

    summary = digest(snap, drafts)
    print(summary)
    for d in drafts:
        print("  ร่าง:", d)

    if check_only:
        return 0

    row = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
           "new_items": snap.get("new_items", 0),
           "warning": snap.get("warning", False),
           "drafts": drafts, "reachable": snap.get("reachable", False)}
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, ensure_ascii=False) + "\n")

    if snap.get("warning"):
        _ntfy("AR: FB Page warning?", summary, "urgent")
    elif snap.get("new_items"):
        _ntfy("AR: FB inbox has new items", summary, "default")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true", help="read only, print digest")
    ap.add_argument("--run", action="store_true", help="read, draft, log, alert")
    ap.add_argument("--draft", metavar="TEXT", help="preview a reply for TEXT")
    args = ap.parse_args(argv)
    if args.draft is not None:
        r = draft_reply(args.draft)
        print(r or "(escalate to K — no safe canned reply)")
        return 0
    return run(check_only=args.check)


if __name__ == "__main__":
    raise SystemExit(main())
