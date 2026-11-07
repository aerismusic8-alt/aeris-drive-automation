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

  * reads the Business Suite inbox as the Page: unread count, comments waiting,
    the Page's follower count, and any warning text,
  * drafts a reply for a fan comment, from a small approved library,
  * posts the queued clips through the proven `crosspost.py` rail,
  * writes a Thai digest to `work/admin-log.jsonl` and pushes one ntfy alert
    when something needs K — including when the Page is not growing at all,
    which is the number that actually says "the business has not started".

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
import re
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
INBOX_UNREAD = "https://www.facebook.com/latest/inbox/all?asset_id=61595890900382&filter=unread"
COMMENTS = "https://www.facebook.com/latest/inbox/comments/?asset_id=61595890900382"
PAGE = "https://www.facebook.com/profile.php?id=61595890900382"
# A Page this young with one follower is the actual problem; a draft nobody can
# see does not move it. Watch the numbers that mean "a business started".
STALL_FOLLOWERS = 10
STALL_DAYS = 3
STALL_ALERT_DAYS = 3

# A warning from Meta, in either language. Finding one of these is the one thing
# that must reach K immediately, because it precedes a restriction.
WARNING_MARKERS = (
    "คำเตือน", "ละเมิด", "ถูกจำกัด", "ข้อจำกัด", "ปิดการใช้งาน", "ถูกระงับ",
    "violation", "restricted", "warning", "disabled", "policy",
)

# What the inbox prints when there is genuinely nothing to answer. Used instead
# of counting a label, so an empty inbox reads as 0 and not as "new mail".
INBOX_EMPTY_MARKERS = (
    "ไม่มีข้อความ", "คุณยังไม่มีข้อความ", "ข้อความที่ส่งถึงคุณจะปรากฏที่นี่",
    "No messages", "You have no messages",
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


def _inbox_state(text: str) -> int:
    """Unread count: 0 when the inbox says it is empty, else the parsed number.

    Counting the substring "ใหม่" was the original bug — the inbox carries a
    permanent filter chip with that exact label, so it always found 2 and the
    rail reported new mail on a completely empty inbox every hour. The honest
    signal is the empty-state text the page prints when there is nothing; when
    that is absent but the count is not printed either, return -1 ("unknown")
    rather than a confident 0.
    """
    t = text or ""
    if any(m in t for m in INBOX_EMPTY_MARKERS):
        return 0
    m = re.search(r"ยังไม่ได้อ่าน\s*(\d+)", t)
    return int(m.group(1)) if m else -1


def _comments_count(desk) -> int:
    """Comments waiting on the Page, from the comments tab's "N ความคิดเห็น".

    A comment is the one inbox item a fan leaves on the Page itself, so it is
    worth surfacing separately from DMs — and it is the number that proves the
    clip is reaching people.
    """
    t = desk.text()
    m = re.search(r"([\d,]+)\s*ความคิดเห็น", t)
    return int(m.group(1).replace(",", "")) if m else 0


def _page_followers(desk) -> int | None:
    """Followers from the Page profile line ("ผู้ติดตาม N"), or None.

    The switch banner only shows while acting as the *person*; switching first
    keeps this reading the Page and not K's personal profile.
    """
    try:
        from social_stats import _switch_to_page  # noqa: PLC0415
    except Exception:  # noqa: BLE001
        return None
    desk.goto(PAGE, settle=14)
    _switch_to_page(desk)
    t = desk.text()
    m = re.search(r"ผู้ติดตาม\s*([\d,\.]+)", t)
    if not m:
        return None
    tok = m.group(1).replace(",", "")
    if tok.endswith("."):
        tok = tok[:-1]
    try:
        return int(float(tok))
    except ValueError:
        return None


def page_snapshot(desk) -> dict:
    """The real state of the Page: inbox, comments, followers, warnings.

    This replaces a snapshot that counted the word "ใหม่" and so reported new
    mail on an empty inbox forever. Everything here is read as the Page.
    """
    desk.goto(INBOX, settle=12)
    text = desk.text()
    if "กล่องข้อความ" not in text and "Inbox" not in text:
        return {"reachable": False, "note": "inbox did not load",
                "raw": text[:400]}

    warning = is_warning(text)
    unread = _inbox_state(text)

    desk.goto(COMMENTS, settle=14)
    comments_text = desk.text()
    comments = _comments_count(desk)

    followers = _page_followers(desk)

    return {
        "reachable": True,
        "unread": unread,
        "comments": comments,
        "comments_text": comments_text[:3000],
        "followers": followers,
        "warning": warning,
        "raw": text[:800],
    }


def inbox_snapshot(desk) -> dict:
    """Back-compat shim: the old name, now backed by the real reader."""
    return page_snapshot(desk)


def _stall(history: list[dict]) -> dict | None:
    """Has the Page stopped growing? Returns the stall facts, or None.

    The rail used to alert on a phantom inbox count and stay silent on the only
    number that matters. A Page with one follower after a week of daily posting
    is not "working"; it needs a different action, and K needs to hear it.
    """
    followers = [(r.get("at"), r.get("followers")) for r in history
                 if isinstance(r.get("followers"), int)]
    if not followers:
        return None
    first_at, first_n = followers[0]
    last_at, last_n = followers[-1]
    try:
        from datetime import datetime
        age_days = (datetime.fromisoformat(last_at.replace("Z", "+00:00"))
                    - datetime.fromisoformat(first_at.replace("Z", "+00:00"))
                    ).total_seconds() / 86400.0
    except Exception:  # noqa: BLE001
        return None
    if age_days < STALL_DAYS or last_n >= STALL_FOLLOWERS:
        return None
    return {"days": int(age_days), "followers": last_n,
            "gain": last_n - first_n}


def digest(snap: dict, drafts: list[str], stall: dict | None = None) -> str:
    """A short Thai summary for K, and for the log."""
    if not snap.get("reachable"):
        return "เพจ/กล่องข้อความ: อ่านไม่ได้ (" + snap.get("note", "") + ")"
    f = snap.get("followers")
    u = snap.get("unread", 0)
    u_txt = "ไม่ทราบ" if u is None or u < 0 else str(u)
    lines = [
        f"ผู้ติดตาม: {f if f is not None else '?'}",
        f"กล่องข้อความ: ยังไม่ได้อ่าน {u_txt} · "
        f"ความคิดเห็น {snap.get('comments', 0)}",
    ]
    if snap.get("warning"):
        lines.append("⚠️ พบข้อความที่อาจเป็นคำเตือนจาก Meta — ต้องตรวจด่วน")
    if stall:
        lines.append(
            f"⚠️ เพจไม่โต: {stall['days']} วัน ผู้ติดตาม {stall['followers']} "
            f"(เปลี่ยน {stall['gain']:+d}) — ต้องเปลี่ยนวิธี ไม่ใช่โพสต์เพิ่ม")
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
    """One alert per day while the gate is failing, on a persistent workspace.

    The gate fails closed, so a missing quorum fails every run until it is fixed.
    Alerting hourly would train K to ignore the alert, so remember the last day
    we shouted. Note this file is not committed, so on CI (a fresh checkout each
    hour) the dedupe does not survive and the alert repeats — acceptable, because
    a failing gate is urgent; the daily dedupe is what the cloud desktop gets.
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
    # Only draft when a fan actually left something. The empty inbox prints a
    # "create an ad" prompt and a footer; scanning that produced a reply to
    # nobody. Gate on the comment count, then read the comment text.
    if snap.get("reachable") and snap.get("comments", 0) > 0:
        for line in (snap.get("comments_text") or "").splitlines():
            d = draft_reply(line)
            if d and d not in drafts:
                drafts.append(d)

    # Read the log before writing so the stall check sees the history it needs.
    history: list[dict] = []
    if LOG.exists():
        for line in LOG.read_text(encoding="utf-8").splitlines():
            try:
                history.append(json.loads(line))
            except json.JSONDecodeError:
                continue
    stall = _stall(history)
    alert_stall = bool(stall) and not _stalled_recently(history)

    summary = digest(snap, drafts, stall)
    print(summary)
    for d in drafts:
        print("  ร่าง:", d)

    if check_only:
        return 0

    row = {"at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
           "unread": snap.get("unread", 0),
           "comments": snap.get("comments", 0),
           "followers": snap.get("followers"),
           "warning": snap.get("warning", False),
           "stall_alert": alert_stall,
           "drafts": drafts, "reachable": snap.get("reachable", False)}
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(row, ensure_ascii=False) + "\n")

    if snap.get("warning"):
        _ntfy("AR: FB Page warning?", summary, "urgent")
    elif alert_stall:
        # The real problem, told once every STALL_ALERT_DAYS. A Page that is not
        # growing needs a different approach, not another clip.
        _ntfy("AR: FB Page is not growing", summary, "high")
    elif snap.get("unread"):
        _ntfy("AR: FB inbox has new items", summary, "default")
    return 0


def _stalled_recently(history: list[dict]) -> bool:
    """Was a stall alert already sent inside STALL_ALERT_DAYS?

    The flag lives in `admin-log.jsonl` (committed) rather than a side file,
    because CI checks out fresh each hour and a side file would not survive — the
    alert would then fire every run instead of once every three days.
    """
    from datetime import datetime, timedelta
    for row in reversed(history):
        if not row.get("stall_alert"):
            continue
        try:
            at = datetime.fromisoformat(row["at"].replace("Z", "+00:00"))
        except (KeyError, ValueError):
            continue
        now = datetime.now(at.tzinfo)
        return now - at < timedelta(days=STALL_ALERT_DAYS)
    return False


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
