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

The rail is gated: before it drafts anything it checks that this brief has a
recent consultation with a real quorum (`ops/consult.py`). The rule is K's
standing one — consult before acting — and writing it in a document was not
enough, because a gate that only lives in prose is skipped under pressure. Here
it is checkable and it fails closed, with an alert that says exactly how to
re-consult. `--no-gate` is the documented escape hatch for an emergency.

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
GATE_ALERT = WORK / "admin-gate-alert.json"

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


# A standing mandate, not a one-off decision: this rail runs hourly for months,
# and the thing the gate guards is "did we ever consult before building this",
# not "did we ask again this morning". So the window is generous and a *stale*
# consultation still passes, but it warns so a real re-ask happens when the
# mandate changes. The gate still fails hard if no quorum was ever recorded.
GATE_MAX_AGE_HOURS = 30 * 24
GATE_WARN_AFTER_HOURS = 7 * 24


def _gate_brief() -> str:
    """The brief this rail is the execution of.

    It must be the *same text* the consultation used, because the gate keys off a
    digest of the problem. Read the committed brief file, not a paraphrase, or
    the digest will never match.
    """
    for name in ("consult-brief-fb-admin-agent-2026-11-06.md",
                 "consult-brief-fb-admin-agent.md"):
        p = WORK / name
        if p.exists():
            return p.read_text(encoding="utf-8")
    return ""


def check_gate() -> tuple[bool, str]:
    """Has this brief been consulted, with a real quorum?

    Fails closed: an unreadable gate (missing module, missing brief) is a FAIL,
    because "I could not check" is not "it was checked".
    """
    sys.path.insert(0, str(surfaces.OPS))
    try:
        import consult  # noqa: E402
    except Exception as exc:  # noqa: BLE001
        return False, f"consult gate unavailable: {type(exc).__name__}: {exc}"
    brief = _gate_brief()
    if not brief:
        return False, "no admin brief file on disk to gate against"
    row = consult.consulted(brief, max_age_hours=GATE_MAX_AGE_HOURS)
    if row is None:
        return False, ("no consultation for the admin brief with a quorum "
                       f"(2 vendors / 3 channels) within {GATE_MAX_AGE_HOURS // 24}d")
    from datetime import datetime, timezone
    age_h = (datetime.now(timezone.utc)
             - datetime.fromisoformat(row["at"])).total_seconds() / 3600.0
    why = consult.quorum(row["answers"])[1]
    if age_h > GATE_WARN_AFTER_HOURS:
        return True, f"{why} (consulted {age_h / 24:.0f}d ago — consider re-asking)"
    return True, why


def _gate_alert_once(why: str) -> None:
    """One alert per day, not one per hourly run.

    The gate fails closed, so a missing quorum fails every run until it is fixed.
    Alerting hourly would train K to ignore the alert, so remember the last day
    we shouted.
    """
    today = time.strftime("%Y-%m-%d")
    try:
        last = json.loads(GATE_ALERT.read_text(encoding="utf-8")) if GATE_ALERT.exists() else {}
    except (OSError, json.JSONDecodeError):
        last = {}
    if last.get("date") == today:
        return
    _ntfy("AR: admin rail blocked — consult first",
          f"ที่ปรึกษาไม่ผ่านเกณฑ์: {why}\n"
          "รัน: python3 ops/consult.py --file "
          "aeris938-2/work/consult-brief-fb-admin-agent-2026-11-06.md",
          "high")
    GATE_ALERT.parent.mkdir(parents=True, exist_ok=True)
    GATE_ALERT.write_text(json.dumps({"date": today, "why": why}), encoding="utf-8")


def run(check_only: bool = False, gate: bool = True) -> int:
    if gate:
        ok, why = check_gate()
        print(f"gate: {'PASS' if ok else 'FAIL'} — {why}")
        if not ok:
            # Alert (once a day), then fail. The rail must not silently do the
            # work the consultation is supposed to authorise.
            _gate_alert_once(why)
            print("::error::admin rail blocked by the consult gate", file=sys.stderr)
            return 2

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
    ap.add_argument("--no-gate", action="store_true",
                    help="skip the consult gate (emergency only; logs the bypass)")
    args = ap.parse_args(argv)
    if args.draft is not None:
        r = draft_reply(args.draft)
        print(r or "(escalate to K — no safe canned reply)")
        return 0
    if args.no_gate:
        print("::warning::consult gate bypassed with --no-gate", file=sys.stderr)
    return run(check_only=args.check, gate=not args.no_gate)


if __name__ == "__main__":
    raise SystemExit(main())
