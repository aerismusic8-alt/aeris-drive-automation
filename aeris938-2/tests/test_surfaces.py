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
import goal_watch  # noqa: E402
import evidence  # noqa: E402


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
    # The route line must name the real 2026 blockers instead of promising ad
    # money, and must not hide TikTok: Creator Rewards is closed to Thailand but
    # TikTok Shop Affiliate is open at 1,000 followers.
    assert "ไม่มีในไทย" in blocked and "invite-only" in blocked
    assert "TikTok Shop Affiliate" in blocked and "1,000 ผู้ติดตาม" in blocked


def test_gate_block_counts_the_gap_to_each_gate():
    """The channel's own money is behind a follower gate (YT 1,000 subs, TikTok
    Shop Affiliate 1,000 followers). The gap must be a number in the report, not
    an implied one — a channel that is not growing toward its gate is failing."""
    assert report.YT_GATE_SUBS == 1000 and report.TT_GATE_FOLLOWERS == 1000
    yt = {"handle": "@aerismusicth", "subs": 7}
    fb = {"followers": 1}
    tk = {"followers_total": 0}
    text = "\n".join(report.gate_block(yt, fb, tk))
    assert "7 / 1,000 ซับ = 0.7%" in text
    assert "993 ซับ" in text
    assert "0 / 1,000 ผู้ติดตาม" in text
    assert "TikTok Shop Affiliate" in text
    # Unreadable input must read UNKNOWN, never a fabricated zero.
    assert "UNKNOWN" in "\n".join(report.gate_block({}, {}, {}))


def test_goal_watch_names_the_blocking_constraint():
    """The daily monitor must name the one constraint that is blocking revenue,
    in priority order: data > income > reach > conversion > offer. It is a
    monitor, not a gate, so it must never raise on bad news.

    `now` is passed explicitly: the reading must be fresh for a constraint to be
    named, so a fixed historical window would be (correctly) read as stale.
    """
    NOW = "2026-11-07T00:00:00Z"

    def row(at, **kw):
        return {"at": at, **kw}

    base = dict(yt_subs=7, yt_views=2042, tk_followers=0, sp_commission=0,
                sp_clicks=0)
    # Views flat → reach is the blocker, even though clicks are also zero.
    flat = [row("2026-11-01T00:00:00Z", **base),
            row("2026-11-07T00:00:00Z", **base)]
    assert goal_watch.diagnose(flat, now=NOW)["constraint"] == "reach"
    # Views growing but subs flat → conversion.
    conv = [row("2026-11-01T00:00:00Z", **base),
            row("2026-11-07T00:00:00Z", **dict(base, yt_views=5000))]
    assert goal_watch.diagnose(conv, now=NOW)["constraint"] == "conversion"
    # A commission beats everything.
    paid = [row("2026-11-01T00:00:00Z", **base),
            row("2026-11-07T00:00:00Z", **dict(base, sp_commission=120))]
    assert goal_watch.diagnose(paid, now=NOW)["constraint"] == "income"
    # And the digest always renders, with no history at all.
    assert "คอขวด" in goal_watch.render(goal_watch.diagnose([]))


def test_goal_watch_refuses_a_constraint_without_fresh_data():
    """A blind day must not produce a confident 'reach' verdict.

    `history.jsonl` gets a row even when the cloud desktop was down and every
    dashboard field is null. Before 2026-11-12 the monitor read those as "flat"
    and named 'reach' — a guess dressed as a finding. Now the constraint is
    'data' until a fresh, valid reading exists.
    """
    NOW = "2026-11-12T12:00:00Z"
    # Newest reading is missing the reach number → unknown → 'data'.
    blind = [{"at": "2026-11-12T11:00:00Z", "yt_subs": 8, "yt_views": None},
             {"at": "2026-11-12T11:30:00Z", "yt_subs": 8, "yt_views": None}]
    d = goal_watch.diagnose(blind, now=NOW)
    assert d["constraint"] == "data", d
    assert d["data_health"]["status"] == "unknown"
    # Newest reading is real but hours old → stale → 'data'.
    stale = [{"at": "2026-11-12T06:00:00Z", "yt_subs": 8, "yt_views": 100},
             {"at": "2026-11-12T06:05:00Z", "yt_subs": 8, "yt_views": 100}]
    assert goal_watch.diagnose(stale, now=NOW)["constraint"] == "data"
    # A fresh, valid reading names a real constraint again.
    fresh = [{"at": "2026-11-12T06:00:00Z", "yt_subs": 8, "yt_views": 100},
             {"at": "2026-11-12T11:58:00Z", "yt_subs": 8, "yt_views": 100}]
    assert goal_watch.diagnose(fresh, now=NOW)["constraint"] == "reach"


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


# --- The daily review loop (K, 2026-11-09) --------------------------------
# K: on a flat day, search for data, meet, and try a NEW way until one works.
# These pin the loop's brain: it must never repeat a loser, never churn a
# running test, and never call a test a loss before it had exposure.

import experiment_loop as loop  # noqa: E402


def test_experiment_library_covers_every_constraint():
    """A constraint with no hypothesis would silently stall the loop."""
    for c in ("reach", "conversion", "offer", "income"):
        assert loop.LIBRARY.get(c), f"no experiments for constraint {c}"
        for e in loop.LIBRARY[c]:
            for f in ("key", "title", "hypothesis", "variable", "peer",
                      "metric", "guardrail"):
                assert e.get(f), f"{c}/{e.get('key')} missing {f}"


def test_loop_starts_the_first_experiment_on_an_empty_ledger():
    d = loop.decide([], "reach")
    assert d["action"] == "start"
    assert d["experiment"]["key"] == loop.LIBRARY["reach"][0]["key"]


def test_loop_keeps_a_running_experiment_inside_its_window():
    """A flat day is a review, not permission to switch — tiny audiences need
    exposure before a verdict."""
    exp = loop.record(loop.LIBRARY["reach"][0], "reach", None)
    d = loop.decide([exp], "reach")
    assert d["action"] == "keep"
    assert d["experiment"]["key"] == exp["key"]


def test_loop_closes_and_moves_on_when_the_window_elapsed():
    exp = loop.record(loop.LIBRARY["reach"][0], "reach", None)
    exp["start"] = "2020-01-01T00:00:00Z"   # long past the window
    d = loop.decide([exp], "reach", [])
    assert d["action"] == "start"
    assert d["close"]["status"] in ("WIN", "FAILED", "INCONCLUSIVE")
    # It must pick a *different* experiment, not re-pick the one just closed.
    assert d["experiment"]["key"] != exp["key"]


def test_loop_never_repeats_a_key_or_a_reworded_hypothesis():
    first = loop.record(loop.LIBRARY["reach"][0], "reach", None)
    assert loop.is_duplicate(loop.LIBRARY["reach"][0], [first]) is not None
    # A reworded version of the same idea is still a duplicate.
    reword = {"key": "something-new",
              "hypothesis": loop.LIBRARY["reach"][0]["hypothesis"] + " (ลองใหม่)"}
    assert loop.is_duplicate(reword, [first]) is not None
    # A genuinely different experiment is not.
    other = loop.LIBRARY["reach"][1]
    assert loop.is_duplicate(other, [first]) is None


def test_loop_reports_exhaustion_rather_than_reusing_a_loser():
    tried = [loop.record(c, "reach", None) for c in loop.LIBRARY["reach"]]
    for t in tried:
        t["status"] = "FAILED"
    d = loop.decide(tried, "reach", [])
    assert d["action"] == "exhausted"


def test_loop_verdict_never_calls_a_low_exposure_test_a_loss():
    exp = loop.record(loop.LIBRARY["reach"][0], "reach", None)
    exp["start"] = "2026-11-01T00:00:00Z"
    NOW = "2026-11-10T00:00:00Z"
    # Plenty of views, subscribers flat -> a real loss.
    strong = [{"at": "2026-11-01T00:00:00Z", "yt_subs": 7, "yt_views": 1214},
              {"at": "2026-11-10T00:00:00Z", "yt_subs": 7, "yt_views": 1600}]
    assert loop.evaluate(exp, strong, now=NOW)[0] == "FAILED"
    # Too little exposure to read -> inconclusive, NOT a loss.
    weak = [{"at": "2026-11-01T00:00:00Z", "yt_subs": 7, "yt_views": 1214},
            {"at": "2026-11-10T00:00:00Z", "yt_subs": 7, "yt_views": 1250}]
    assert loop.evaluate(exp, weak, now=NOW)[0] == "INCONCLUSIVE"
    # A subscriber gain is a win whatever else is flat.
    win = [{"at": "2026-11-01T00:00:00Z", "yt_subs": 7, "yt_views": 1214},
           {"at": "2026-11-10T00:00:00Z", "yt_subs": 9, "yt_views": 1250}]
    assert loop.evaluate(exp, win, now=NOW)[0] == "WIN"


def test_loop_verdict_is_inconclusive_on_missing_or_stale_evidence():
    """A verdict needs a fresh, valid reading of the goal metric.

    The panel's gate (2026-11-12): missing data must never become a WIN or a
    FAILED — a blind day is INCONCLUSIVE. Without this, an all-null history row
    would read as 'subs flat, views flat' and close a test as a loss.
    """
    exp = loop.record(loop.LIBRARY["reach"][0], "reach", None)
    exp["start"] = "2026-11-01T00:00:00Z"
    NOW = "2026-11-10T00:00:00Z"
    # Newest row is a blind day (subs missing) → inconclusive, not a loss.
    blind = [{"at": "2026-11-01T00:00:00Z", "yt_subs": 7, "yt_views": 1214},
             {"at": "2026-11-10T00:00:00Z", "yt_subs": None, "yt_views": None}]
    verdict, why = loop.evaluate(exp, blind, now=NOW)
    assert verdict == "INCONCLUSIVE", (verdict, why)
    # Newest row is real but stale → also inconclusive.
    stale = [{"at": "2026-11-01T00:00:00Z", "yt_subs": 7, "yt_views": 1214},
             {"at": "2026-11-09T00:00:00Z", "yt_subs": 7, "yt_views": 1600}]
    assert loop.evaluate(exp, stale, now=NOW)[0] == "INCONCLUSIVE"
    # An offer test needs Shopee data: with a fresh YouTube reading but a blind
    # Shopee click count it is still inconclusive, never a loss.
    off = loop.record(loop.LIBRARY["offer"][0], "offer", None)
    off["start"] = "2026-11-01T00:00:00Z"
    shopee_blind = [{"at": "2026-11-01T00:00:00Z", "yt_subs": 7, "yt_views": 1214,
                     "sp_clicks": 3},
                    {"at": "2026-11-10T00:00:00Z", "yt_subs": 7, "yt_views": 1600,
                     "sp_clicks": None}]
    assert loop.evaluate(off, shopee_blind, now=NOW)[0] == "INCONCLUSIVE"


def test_evidence_status_vocabulary():
    """The shared contract: fresh / stale / unknown, and usable only when fresh."""
    NOW = "2026-11-12T12:00:00Z"
    assert evidence.status(5, "2026-11-12T11:50:00Z", NOW) == "fresh"
    assert evidence.status(5, "2026-11-12T09:00:00Z", NOW) == "stale"
    assert evidence.status(None, "2026-11-12T11:50:00Z", NOW) == "unknown"
    assert evidence.status("UNKNOWN", "2026-11-12T11:50:00Z", NOW) == "unknown"
    assert evidence.status(5, None, NOW) == "stale"
    assert evidence.usable(5, "2026-11-12T11:50:00Z", NOW) is True
    assert evidence.usable(None, "2026-11-12T11:50:00Z", NOW) is False
    snap = evidence.snapshot({"a": 1, "b": None}, "2026-11-12T11:50:00Z", NOW)
    assert snap["summary"] == {"fresh": 1, "stale": 0, "unknown": 1}
    assert snap["keys"]["b"]["status"] == "unknown"


def test_assert_fresh_gate_fails_on_a_blind_reading():
    """The dashboard rail's freshness gate: a blind newest reading exits non-zero,
    so a lying-green run cannot pass for a healthy one."""
    import tempfile
    orig_load, orig_watch = goal_watch.load, goal_watch.WATCH
    with tempfile.TemporaryDirectory() as d:
        goal_watch.WATCH = Path(d) / "goal-watch.md"
        try:
            goal_watch.load = lambda *a, **k: [
                {"at": "2026-11-12T11:00:00Z", "yt_subs": 8, "yt_views": None}]
            assert goal_watch.main(["--no-push", "--assert-fresh"]) == 3
            goal_watch.load = lambda *a, **k: [
                {"at": "2099-01-01T00:00:00Z", "yt_subs": 8, "yt_views": 100}]
            assert goal_watch.main(["--no-push", "--assert-fresh"]) == 0
        finally:
            goal_watch.load, goal_watch.WATCH = orig_load, orig_watch


# --- The live-artifact audit (K, 2026-11-09) ------------------------------
# The bug that survived 1555 green tests: the published video carried no
# revenue ask. These pin the check that looks at the *product*, not the code.

import live_audit as audit  # noqa: E402


def test_audit_expectation_comes_from_config_not_the_generator():
    exp = audit.expected()
    assert exp["affiliate"] and exp["affiliate"].startswith("https://s.shopee.co.th/")
    assert exp["youtube"].startswith("https://www.youtube.com/@aerismusicth")


def test_audit_flags_the_exact_bug_that_survived_the_tests():
    """A live video with no affiliate link and no subscribe ask must fail, even
    though every unit test passed — that is the whole point of the audit."""
    exp = audit.expected()
    bad = {"id": "X", "snippet": {"title": "เพลงเศร้า", "description": "เพลงเศร้า"}}
    fails = audit.check_video(bad, exp, {})
    assert "revenue_ask_missing" in fails
    assert "subscribe_ask_missing" in fails


def test_audit_passes_a_video_that_carries_the_ask():
    exp = audit.expected()
    good = {"id": "X", "snippet": {
        "title": "รวมเพลงไทย 15 เพลง",
        "description": audit.monetize.cta("youtube") + "\n\n0:00 a\n1:00 b"}}
    assert audit.check_video(good, exp, {}) == []


def test_audit_flags_an_empty_description_and_a_losing_title():
    exp = audit.expected()
    empty = {"id": "X", "snippet": {"title": "x", "description": ""}}
    assert "description_empty" in audit.check_video(empty, exp, {})
    losing = {"id": "X", "snippet": {
        "title": "เพลงเศร้า | AERIS Music",
        "description": audit.monetize.cta("youtube")}}
    assert "losing_title_shape" in audit.check_video(losing, exp, {})


def test_audit_requires_chapters_on_a_compilation():
    exp = audit.expected()
    comp = {"id": "C", "snippet": {
        "title": "รวมเพลงไทย",
        "description": audit.monetize.cta("youtube") + "\n\n0:00 a\n1:00 b"}}
    fails = audit.check_video(comp, exp, {"C": 15})
    assert any(f.startswith("chapters_missing") for f in fails)


def test_videos_list_chunks_past_fifty_ids():
    """videos.list takes at most 50 ids; a 62-video channel broke the daily audit
    because every id was joined into one call and the API answered 400, which the
    audit misread as 'quota'. get_videos must chunk, and a real non-200 must NOT
    be swallowed as a quota state."""
    import yt_auth
    calls = []

    def fake_api_get(path, token, **params):
        ids = params["id"].split(",")
        calls.append(len(ids))
        assert len(ids) <= 50, f"a chunk of {len(ids)} ids exceeds the API limit"
        return 200, {"items": [{"id": i} for i in ids]}

    orig = yt_auth.api_get
    yt_auth.api_get = fake_api_get
    try:
        st, items = yt_auth.get_videos("tok", [f"v{i}" for i in range(62)])
    finally:
        yt_auth.api_get = orig
    assert st == 200 and len(items) == 62
    assert calls == [50, 12], f"expected chunks [50, 12], got {calls}"


def test_read_live_distinguishes_a_bug_from_a_quota():
    """A 400 (a bug, e.g. a >50-id call) must raise RuntimeError; only a 403 is a
    quota state. Mislabeling the bug is what hid this failure for days."""
    import yt_auth
    orig_ids, orig_get = yt_auth.all_upload_ids, yt_auth.get_videos
    yt_auth.all_upload_ids = lambda tok: ["v1"]
    try:
        yt_auth.get_videos = lambda tok, ids, part="x": (400, [])
        try:
            audit.read_live()
            assert False, "a 400 must not be reported as a quota state"
        except audit.QuotaError:
            assert False, "400 is a bug, not quota"
        except RuntimeError:
            pass
        yt_auth.get_videos = lambda tok, ids, part="x": (403, [])
        try:
            audit.read_live()
            assert False, "403 must raise QuotaError"
        except audit.QuotaError:
            pass
    finally:
        yt_auth.all_upload_ids, yt_auth.get_videos = orig_ids, orig_get


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"ok  {fn.__name__}")
    print(f"\n{len(fns)} passed")
