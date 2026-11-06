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


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"ok  {fn.__name__}")
    print(f"\n{len(fns)} passed")
