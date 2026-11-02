#!/usr/bin/env python3
"""The four surfaces of aeris938-2, and the proven tools that drive them.

K scoped this project to exactly four things: grow Facebook, TikTok, one YouTube
channel (@aerismusicth), and Shopee Affiliate revenue. Everything else is out of
scope, so this module is the single place that knows which accounts exist.

The growth mechanics (drive the signed-in cloud desktop, post Shorts, fill a
profile, read a dashboard) were already built and verified in `music938-1`.
Rather than fork that code, this project imports it and adds only the identity,
config and reporting that the new scope needs.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent          # aeris938-2/
REPO = ROOT.parent                                     # repo root
MUSIC = REPO / "music938-1"
MUSIC_SCRIPTS = MUSIC / "scripts"
OPS = REPO / "ops"
WORK = ROOT / "work"
CONFIG = ROOT / "channel.json"

# The four surfaces, in K's order. The key is what `grow.py` accepts.
SURFACES = ("facebook", "tiktok", "youtube", "shopee_affiliate")


def config() -> dict:
    return json.loads(CONFIG.read_text(encoding="utf-8"))


def music_scripts() -> Path:
    """Put music938-1's scripts on sys.path so their modules import cleanly.

    `crosspost.py`, `social_stats.py`, `profile_setup.py` and `browser.py` all
    resolve `ROOT` from their own location, so importing them from here still
    points them at `music938-1/` — which is what we want: the queue, the state
    files and the media all live there.
    """
    p = str(MUSIC_SCRIPTS)
    if p not in sys.path:
        sys.path.insert(0, p)
    return MUSIC_SCRIPTS


def tool(name: str) -> Path:
    """Path to a proven music938-1 tool, verified to exist."""
    path = MUSIC_SCRIPTS / name
    if not path.exists():
        raise SystemExit(f"tool not found: {path}")
    return path
