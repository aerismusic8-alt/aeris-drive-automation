#!/usr/bin/env python3
"""Which surfaces are paused, from the single source of truth.

`aeris938-2/channel.json` names the surfaces AR grows and carries each one's
`status`. A surface whose status is `paused` is a deliberate halt (K, 2026-11-15:
Facebook). One truth, read by everything that could otherwise touch the surface:

  * `crosspost.py` never posts a paused surface and never probes it in a browser;
  * `session_guard.py` never watches or browser-revives it;
  * `token_heartbeat.py` never checks its token.

That is what makes a pause real, and what keeps a paused Facebook from taking a
live TikTok down with it: the rail skips the paused surface and posts the rest.
"""
from __future__ import annotations

import json
from pathlib import Path

CONFIG = Path(__file__).resolve().parent.parent / "aeris938-2" / "channel.json"


def paused() -> set[str]:
    """The surface keys whose `status` is `paused`. Empty if the file is unreadable."""
    try:
        data = json.loads(CONFIG.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return set()
    return {name for name, cfg in data.items()
            if isinstance(cfg, dict) and cfg.get("status") == "paused"}
