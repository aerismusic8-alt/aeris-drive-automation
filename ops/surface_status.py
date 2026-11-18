#!/usr/bin/env python3
"""Which surfaces are off, and how, from the single source of truth.

`aeris938-2/channel.json` names the surfaces AR grows and carries each one's
`status`. Two statuses mean "the browser must never drive this surface", and the
difference is what the API-only Facebook route needs:

  * `paused`   — a deliberate halt (K, 2026-11-15). Not posted, not measured, not
                 browser-touched. A surface K has switched off entirely.
  * `api-only` — post through the surface's own API, but **never** touch it in a
                 browser. This is Facebook after the Meta System User token made
                 the Graph route live (K, 2026-11-17: "ไปปั้นเพจต่อ"): a browser
                 session on a cron cadence is the automation signature Meta
                 caught, so posting goes through the API and the browser stays
                 away. It is not `active`, because `active` would re-open the
                 browser paths.

One truth, read by everything that could otherwise touch the surface:

  * `crosspost.py` never posts a `paused` surface; an `api-only` surface posts via
    its API and never falls back to the browser (see `crosspost.API_ONLY`);
  * `session_guard.py` / `admin.py` never browser-touch a surface in either set;
  * `token_heartbeat.py` still checks an `api-only` surface's token (posting
    depends on it) but skips a `paused` one.

That is what keeps an off Facebook from taking a live TikTok down with it.
"""
from __future__ import annotations

import json
from pathlib import Path

CONFIG = Path(__file__).resolve().parent.parent / "aeris938-2" / "channel.json"


def _status() -> dict[str, str]:
    """surface key -> its `status` string ("" when unset). {} if unreadable."""
    try:
        data = json.loads(CONFIG.read_text(encoding="utf-8"))
    except Exception:  # noqa: BLE001
        return {}
    return {name: (cfg.get("status") or "")
            for name, cfg in data.items() if isinstance(cfg, dict)}


def paused() -> set[str]:
    """Surfaces halted entirely: not posted, not measured, not browser-touched."""
    return {n for n, s in _status().items() if s == "paused"}


def api_only() -> set[str]:
    """Surfaces that post through their API only; a browser must not drive them."""
    return {n for n, s in _status().items() if s == "api-only"}


def no_browser() -> set[str]:
    """Surfaces a browser must never drive: `paused` or `api-only`."""
    return paused() | api_only()
