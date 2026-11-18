#!/usr/bin/env python3
"""Apply the Page *description* to the Facebook Page through the Graph API.

The description is the one Page-info field the Graph API can write (`about`,
which maps to the Edit Page Info "Description"). Doing it here — not by driving
a signed-in browser — is what keeps the change inside Meta's rules: their terms
forbid automated access to the Products "regardless of whether such automated
access ... is undertaken while logged-in", and the Graph API is the access they
granted in advance. So this is the sanctioned route; the browser route is not.

What this does **not** do: the Page *name*. The Graph API exposes no update for
it, so a rename is a manual Page Settings action only the account owner can make.

Copy source: `music938-1/scripts/surreal.BIO`, the same string the FB profile
setup uses, so the Page has one description, not two.

    python3 ops/apply_fb_brand.py --dry-run     # show the diff, write nothing
    python3 ops/apply_fb_brand.py               # apply (idempotent)

Exit codes: 0 applied/already-current, 3 no token configured (park, not a
failure), 1 a real API error (the token was rejected — an outage, not a park).
"""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import fb_graph  # noqa: E402

sys.path.insert(0, str(Path(__file__).resolve().parent.parent / "music938-1" / "scripts"))
import surreal  # noqa: E402

DESIRED_ABOUT = surreal.BIO


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args(argv)

    if not fb_graph.available():
        print("fb page: no token configured (parked)")
        return 3

    try:
        cur = fb_graph.page_fields()
    except RuntimeError as e:
        print(f"fb page read failed: {e}")
        return 1

    live = (cur.get("about") or "").strip()
    if live == DESIRED_ABOUT.strip():
        print("fb page: description already current — nothing to write")
        return 0

    print("fb page:", cur.get("name", "?"))
    print("live description :", repr(live[:80]))
    print("desired          :", repr(DESIRED_ABOUT[:80]))

    if a.dry_run:
        print("dry-run: would PUT the about field")
        return 0

    try:
        fb_graph.set_page_about(DESIRED_ABOUT)
    except RuntimeError as e:
        print(f"fb page description write failed: {e}")
        return 1
    print("fb page: description updated")
    return 0


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
