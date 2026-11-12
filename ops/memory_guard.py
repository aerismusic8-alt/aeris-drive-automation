#!/usr/bin/env python3
"""Keep the injected memory index bounded so it never silently drops rules.

`.openhands/memory/MEMORY.md` is injected into every session's prompt. Its own
header says "small on purpose — a long one is truncated from the top", but by
2026-11-10 it had grown to 128 KB (1713 lines) against a stated ~6 KB budget, so
the *top* — the operating method and Rule #1 (free only) — was being dropped from
context. Growth was invisible because nothing measured it.

This is the automated check the advisors prescribed: an edit that pushes the index
past the cap is rejected loudly instead of being silently truncated. It is a pure
reader, so it is safe to run anywhere (CI, pre-commit, a session) and never blocks
the posting rails or revenue tracking.

    python3 ops/memory_guard.py            # human report, exit 1 if over cap
    python3 ops/memory_guard.py --check    # quiet: exit 1 if over cap (for CI)
    python3 ops/memory_guard.py --json     # machine-readable

Rules of the scheme (see MEMORY.md header):
  * MEMORY.md      — the operating card. HARD CAP `CAP_BYTES`.
  * MEMORY-ARCHIVE.md — every memory ever written; unbounded, moved-to not deleted.
  * YYYY-MM-DD.md  — session working notes; unbounded, never injected.

When over cap, do NOT delete: fold the oldest durable lines into the archive and
leave a one-line pointer, exactly as the header describes.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
MEMORY_DIR = HERE.parent / ".openhands" / "memory"
INDEX = MEMORY_DIR / "MEMORY.md"
ARCHIVE = MEMORY_DIR / "MEMORY-ARCHIVE.md"

# The injected index must stay small: every session pays for it, and past the
# limit the top (the rules) is what gets dropped. 6 KB is the budget the file
# header always stated; keep a little headroom above it so a small edit is fine.
CAP_BYTES = 6144
WARN_BYTES = int(CAP_BYTES * 0.9)


def measure() -> dict:
    idx = INDEX.read_bytes() if INDEX.exists() else b""
    arc = ARCHIVE.read_bytes() if ARCHIVE.exists() else b""
    logs = sorted(p for p in MEMORY_DIR.glob("*.md")
                  if p.name not in ("MEMORY.md", "MEMORY-ARCHIVE.md"))
    return {
        "index_bytes": len(idx),
        "index_lines": idx.count(b"\n") + (1 if idx and not idx.endswith(b"\n") else 0),
        "cap_bytes": CAP_BYTES,
        "archive_bytes": len(arc),
        "daily_logs": len(logs),
        "daily_bytes": sum(p.stat().st_size for p in logs),
        "over_cap": len(idx) > CAP_BYTES,
        "warn": WARN_BYTES < len(idx) <= CAP_BYTES,
    }


def report(m: dict) -> str:
    pct = 100 * m["index_bytes"] / m["cap_bytes"]
    state = "OVER CAP" if m["over_cap"] else ("near cap" if m["warn"] else "ok")
    return (
        f"MEMORY.md index : {m['index_bytes']:,} / {m['cap_bytes']:,} bytes "
        f"({pct:.0f}%) [{state}]\n"
        f"MEMORY-ARCHIVE  : {m['archive_bytes']:,} bytes (unbounded, moved-to)\n"
        f"daily logs      : {m['daily_logs']} files, {m['daily_bytes']:,} bytes "
        f"(unbounded, never injected)"
    )


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--check", action="store_true",
                    help="quiet; exit 1 only when the index is over cap")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args(argv)

    m = measure()
    if args.json:
        print(json.dumps(m))
    elif not args.check:
        print(report(m))

    if m["over_cap"]:
        if not args.json and not args.check:
            print(f"\n::error::MEMORY.md is {m['index_bytes']:,} bytes, over the "
                  f"{CAP_BYTES:,} cap. The top (the rules) is truncated from every "
                  f"prompt. Fold the oldest durable lines into MEMORY-ARCHIVE.md "
                  f"and leave a pointer — do not delete.")
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
