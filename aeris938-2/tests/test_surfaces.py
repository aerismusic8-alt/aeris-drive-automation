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


if __name__ == "__main__":
    fns = [v for k, v in sorted(globals().items()) if k.startswith("test_")]
    for fn in fns:
        fn()
        print(f"ok  {fn.__name__}")
    print(f"\n{len(fns)} passed")
