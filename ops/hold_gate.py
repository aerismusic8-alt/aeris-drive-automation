#!/usr/bin/env python3
"""One switch that stops every publish, enforced by code.

K (2026-11-20): "หยุดระบบโพสต์ไว้ทั้งหมดก่อน เรากำลังวางระบบผลิตคลิปอยู่" —
stop all posting while the clip production system is being rebuilt.

Disabling a workflow only stops its *schedule*. A manual dispatch, a re-run of an
old job, a local script and an agent session all keep working, so "the rail is
disabled" is not the same as "nothing can post". This module is the real switch:
the presence of `ops/PUBLISH-HOLD` raises `PublishHeld` inside every uploader.

Lifting the hold is deleting the marker (and committing the deletion). There is
no flag, no env var and no override argument on purpose — the same reason the
clip floor has none: an escape hatch on a safety gate gets used under pressure.
"""
from __future__ import annotations

import os
from pathlib import Path

MARKER = Path(os.path.dirname(os.path.abspath(__file__))) / "PUBLISH-HOLD"


class PublishHeld(RuntimeError):
    """Raised when a publish is attempted while the hold is on."""


def active() -> bool:
    return MARKER.exists()


def reason() -> str:
    """The first prose line of the marker, so the message says why and who."""
    try:
        for line in MARKER.read_text(encoding="utf-8").splitlines():
            line = line.strip().lstrip("#").strip()
            if line:
                return line
    except OSError:
        pass
    return "publishing is on hold"


def assert_open(surface: str) -> None:
    """Refuse a publish while the hold is on. `surface` names the caller."""
    if active():
        raise PublishHeld(
            f"{surface}: publishing is on hold ({MARKER.name}) — {reason()}. "
            f"Lift it by deleting ops/PUBLISH-HOLD.")


if __name__ == "__main__":
    state = "ACTIVE" if active() else "open"
    print(f"hold: {state}")
    if active():
        print(f"reason: {reason()}")
        print(f"marker: {MARKER}")
        raise SystemExit(1)
