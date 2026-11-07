#!/usr/bin/env python3
"""Guards the scope K set: exactly four surfaces, one YouTube channel only.

A scope that lives only in a README drifts. This pins it in code so a later
change that adds a fifth surface, or starts growing a second YouTube channel,
fails loudly instead of quietly re-expanding the project.

    python3 tests/test_surfaces.py
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "scripts"))

import surfaces  # noqa: E402
import report  # noqa: E402
import admin  # noqa: E402


def test_exactly_four_surfaces():
    cfg = surfaces.config()
    keys = {k for k in cfg if not k.startswith("_")}
    assert keys == set(surfaces.SURFACES), keys
    assert surfaces.SURFACES == ("facebook", "tiktok", "youtube", "shopee_affiliate")


def test_youtube_is_single_channel():
    yt = surfaces.config()["youtube"]
    assert yt["only_channel"] is True
    assert yt["handle"] == "@aerismusicth"
    assert yt["token"] == "ch3"


def test_every_surface_has_a_target():
    cfg = surfaces.config()
    assert cfg["facebook"]["page_id"] == "61595890900382"
    assert cfg["tiktok"]["handle"] == "@aeris.music4"
    assert cfg["shopee_affiliate"]["short"].startswith("https://th.shp.ee/")


def test_shopee_is_onboarded_with_per_surface_links():
    sp = surfaces.config()["shopee_affiliate"]
    assert sp["onboarded"] is True
    links = sp["links"]
    assert set(links) == {"youtube", "tiktok", "facebook"}
    for url in links.values():
        assert url.startswith("https://s.shopee.co.th/")


def test_tools_that_grow_exists():
    for name in ("crosspost.py", "profile_setup.py", "social_stats.py",
                 "apply_brand.py", "post_community.py"):
        assert surfaces.tool(name).exists(), name


def test_report_never_guesses():
    yt = {"handle": "@aerismusicth", "subs": 5, "videos": 28, "views": 100}
    dash = {"facebook": {"reachable": False},
            "tiktok": {"reachable": True, "followers_total": 1, "views_7d": 0},
            "shopee": {"reachable": False}}
    text = report.render(yt, dash)
    assert "| 1 | Facebook | ผู้ติดตาม | UNKNOWN |" in text
    assert "| 2 | TikTok | ผู้ติดตาม | 1 |" in text
    assert "| 3 | YouTube @aerismusicth | ผู้ติดตาม | 5 |" in text
    assert "1,000 ซับ" in text  # goal line present


def test_report_shows_change():
    """A reading against the previous one must state the movement, and show a
    dash — not a blank — when a number is unchanged."""
    yt = {"handle": "@aerismusicth", "subs": 6, "videos": 28, "views": 150}
    dash = {"facebook": {"reachable": True, "followers": 2, "views_28d": 5},
            "tiktok": {"reachable": True, "followers_total": 1, "views_7d": 0},
            "shopee": {"reachable": True, "orders": 1, "commission": 2.5}}
    prev = {"yt_subs": 5, "yt_views": 100, "fb_followers": 2, "sp_orders": 0}
    text = report.render(yt, dash, prev)
    assert "| 6 | +1 |" in text      # subs rose by 1
    assert "| 150 | +50 |" in text   # views rose by 50
    assert "| 2 | — |" in text       # followers unchanged
    assert "| 1 | +1 |" in text      # first Shopee order


def test_flatten_and_delta():
    yt = {"subs": 6, "views": 150, "videos": 28}
    dash = {"facebook": {"reachable": True, "followers": 2, "views_28d": 5},
            "tiktok": {"reachable": True, "followers_total": 1, "views_7d": 0},
            "shopee": {"reachable": True, "orders": 0, "commission": 0}}
    flat = report.flatten(yt, dash)
    assert flat["yt_subs"] == 6 and flat["fb_followers"] == 2
    assert report._delta(6, 5) == "+1"
    assert report._delta(5, 5) == "—"
    assert report._delta(None, 5) == ""


def test_history_roundtrip():
    import tempfile
    old = report.HISTORY
    try:
        with tempfile.TemporaryDirectory() as d:
            report.HISTORY = Path(d) / "history.jsonl"
            report.append_history({"at": "t1", "yt_subs": 1})
            report.append_history({"at": "t2", "yt_subs": 2})
            hist = report.load_history()
            assert len(hist) == 2 and hist[-1]["yt_subs"] == 2
    finally:
        report.HISTORY = old


def test_shopee_clicks_and_fallback():
    """Shopee must report clicks (the leading indicator) and, when the live read
    fails, fall back to the last real reading rather than print UNKNOWN."""
    yt = {"handle": "@aerismusicth", "subs": 5, "videos": 28, "views": 100}
    live = {"facebook": {"reachable": True, "followers": 1, "views_28d": 1},
            "tiktok": {"reachable": True, "followers_total": 1, "views_7d": 0},
            "shopee": {"reachable": True, "clicks": 7, "orders": 1, "commission": 2.5}}
    text = report.render(yt, live)
    assert "| 4 | Shopee | คลิก | 7 |" in text

    # Live read blocked (captcha) → last real reading, labelled with its date.
    blocked = dict(live, shopee={"reachable": False, "note": "captcha"})
    hist = [{"at": "2026-11-03T01:00:00Z", "sp_clicks": 7, "sp_orders": 1,
             "sp_commission": 2.5}]
    text2 = report.render(yt, blocked, None, hist)
    assert "| 4 | Shopee | คลิก | 7 |" in text2
    assert "2026-11-03T01:00:00Z" in text2  # labelled, not silently stale


def test_revenue_goal_is_measured_and_never_guessed():
    """K set a $500 goal (2026-11-07). It must be counted from the real Shopee
    commission — the only route that can pay in Thailand — converted to THB, and
    read UNKNOWN when the dashboard is unreachable, never a guessed figure."""
    assert report.GOAL_USD == 500
    text = "\n".join(report.goal_block({"commission": "5,000", "orders": "120",
                                        "clicks": "9,000"}))
    assert "29.80%" in text                      # 5000 / 16780
    assert "คำสั่งซื้อสะสม: 120" in text
    blocked = "\n".join(report.goal_block({"commission": "UNKNOWN"}))
    assert "UNKNOWN" in blocked and "ไม่เดา" in blocked
    # The route line must name the real 2026 blocker instead of promising ad money.
    assert "ไม่มีในไทย" in blocked and "invite-only" in blocked


def test_follow_guard_requires_the_page_identity():
    """The follow loop must never click Follow while the personal profile acts.

    `_acting_as_page` once tested `"จัดการเพจ" in body`, which is also the
    personal profile's own left-rail entry, so it returned True while the page
    was still browsing as the person and every follow was misattributed. The
    guard must reject the "สลับไปใช้เพจ" switch banner and require a Page-only
    anchor, and the switch must click through all three steps.
    """
    src = (ROOT / "scripts" / "outreach.py").read_text(encoding="utf-8")
    assert 'if "สลับไปใช้เพจ" in head:' in src
    assert 'return "แก้ไขรูปภาพหน้าปก" in head' in src
    assert '"จัดการเพจ" in head' not in src
    assert "'ใช้เพจ'" in src and "'สลับ'" in src


def test_admin_never_automates_outbound():
    """The admin agent must not send anything on its own.

    A five-advisor panel (2026-11-06) said automating outbound engagement —
    follows, friend-invites, comments on other Pages, cold DMs — is an
    artificial-growth signal Meta acts on, with no safe per-day rate. The agent
    therefore drafts replies but never sends them, and the follow/invite verbs in
    outreach.py refuse to run without an explicit risk acknowledgement.
    """
    src = (ROOT / "scripts" / "admin.py").read_text(encoding="utf-8")
    assert "def draft_reply" in src
    for banned in ("_js_click_text", "send_message", "submit_reply",
                   "click(", "follow_page"):
        assert banned not in src, f"admin.py must not send: found {banned!r}"

    outreach = (ROOT / "scripts" / "outreach.py").read_text(encoding="utf-8")
    assert "--i-understand-the-risk" in outreach
    assert "is on hold" in outreach


def test_admin_drafts_are_safe():
    """A canned reply is produced for a clear, low-risk question, and withheld
    for anything a human must handle (complaint, refund, rights)."""
    assert admin.draft_reply("ราคาเท่าไหร่ครับ")           # price -> shop link
    assert admin.draft_reply("เพลงนี้ชื่ออะไร")            # title -> caption
    assert admin.draft_reply("ขอบคุณมากครับ")             # thanks -> follow ask
    assert admin.draft_reply("มีปัญหา ขอคืนเงิน") == ""     # refund -> escalate
    assert admin.draft_reply("เรื่องลิขสิทธิ์") == ""       # rights -> escalate
    assert admin.draft_reply("") == ""                      # empty -> nothing


def test_admin_warning_detection():
    """A Meta warning must be recognised in either language, because finding one
    is the single event that has to reach K immediately."""
    assert admin.is_warning("พบคำเตือนจาก Meta")
    assert admin.is_warning("Your Page has been restricted")
    assert not admin.is_warning("ขอบคุณมากครับ เพราะมาก")


def test_admin_is_gated_on_the_consultation():
    """The rail must not run the work the consultation is supposed to authorise.

    The rule "consult before acting" was prose, so it got skipped — the failure
    the advisors themselves warned about. `run()` now calls the gate and fails
    closed (return 2) when the brief has no quorum, with `--no-gate` as the only
    escape hatch. Pin both halves: the gate exists and it is wired into run().
    """
    src = (ROOT / "scripts" / "admin.py").read_text(encoding="utf-8")
    assert "def check_gate" in src
    assert "consult.consulted(" in src, "admin must ask the gate, not remember it"
    assert "--no-gate" in src, "the escape hatch must be explicit"
    # Fails closed: no brief on disk, or no quorum, is a FAIL not a pass.
    assert "no admin brief file on disk" in src
    assert "return 2" in src

    # The gate reads the committed brief, so the digest can match the consultation.
    saved = admin.WORK
    try:
        import tempfile
        with tempfile.TemporaryDirectory() as tmp:
            admin.WORK = Path(tmp)
            assert admin._gate_brief() == ""          # missing -> empty -> FAIL
            p = Path(tmp) / "consult-brief-fb-admin-agent-2026-11-06.md"
            p.write_text("hello brief", encoding="utf-8")
            assert admin._gate_brief() == "hello brief"
    finally:
        admin.WORK = saved


def test_inbox_count_does_not_count_the_filter_label():
    """The rail used to report "มีรายการใหม่ 2 รายการ" on an empty inbox forever.

    It counted the substring "ใหม่" anywhere on the page, and the inbox carries a
    permanent filter chip with that exact label. Pin the fix: an empty inbox is
    0, a label alone is unknown, and a printed number is that number.
    """
    empty = "กล่องข้อความ\nใหม่\nยังไม่ได้อ่าน\nไม่มีข้อความ\nคุณยังไม่มีข้อความใดๆ"
    assert admin._inbox_state(empty) == 0
    # A filter label on its own is not evidence of unread mail: unknown, not 2.
    assert admin._inbox_state("ใหม่\nNew\nกล่องข้อความ") == -1
    assert admin._inbox_state("กล่องข้อความ\nยังไม่ได้อ่าน 3\n") == 3
    # Unreadable is "unknown" (-1), not a confident 0.
    assert admin._inbox_state("กล่องข้อความ") == -1


def test_page_snapshot_shape_and_no_phantom_drafts():
    """A snapshot with no comments must not produce a reply to nobody.

    The empty inbox prints a "create an ad" prompt; scanning it drafted a reply
    anyway. `run()` now gates drafting on `comments > 0`, and the digest shows
    the real numbers. These are the pure parts, so they need no browser.
    """
    snap = {"reachable": True, "unread": 0, "comments": 0, "followers": 1,
            "warning": False, "comments_text": ""}
    assert admin.digest(snap, [], None).splitlines()[0] == "ผู้ติดตาม: 1"
    assert "ความคิดเห็น 0" in admin.digest(snap, [], None)


def test_stall_detection_fires_on_a_page_that_never_grew():
    """One follower after a week of posting is the real problem, and it must be
    visible — not buried under a phantom inbox count."""
    hist = [{"at": "2026-11-01T00:00:00Z", "followers": 1},
            {"at": "2026-11-07T00:00:00Z", "followers": 1}]
    stall = admin._stall(hist)
    assert stall and stall["followers"] == 1 and stall["days"] == 6
    # Growing past the floor, or too short a window, is not a stall.
    assert admin._stall([{"at": "2026-11-01T00:00:00Z", "followers": 1},
                         {"at": "2026-11-07T00:00:00Z", "followers": 25}]) is None
    assert admin._stall([{"at": "2026-11-06T00:00:00Z", "followers": 1},
                         {"at": "2026-11-07T00:00:00Z", "followers": 1}]) is None
    assert admin._stall([]) is None


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"ok  {fn.__name__}")
    print(f"\n{len(fns)} passed")
