#!/usr/bin/env python3
"""Search all persistent memory — the card, the archive and the daily logs.

`MEMORY.md` is a deliberately tiny operating card (capped at 6 KB by
`ops/memory_guard.py`), so almost everything AR has learned lives in
`MEMORY-ARCHIVE.md` and the daily logs, which are never injected. The scheme says
that detail is "reachable by grep" — this is that grep, over all three tiers at
once, so a folded lesson is never more than one command away:

    python3 ops/memory_search.py "shopee cta"
    python3 ops/memory_search.py --titles            # list every section title
    python3 ops/memory_search.py "quota" --context 2 # wider excerpts

Output is grouped by section and shows file + line, so the next step is a plain
`sed -n 'A,Bp' <file>`. Stdlib only (no `rg` assumed), offline, free.
"""
from __future__ import annotations

import argparse
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
MEMDIR = ROOT / ".openhands" / "memory"


def _files() -> list[Path]:
    """Card first (the curated view), then the archive, then logs newest-first."""
    files: list[Path] = []
    for name in ("MEMORY.md", "MEMORY-ARCHIVE.md"):
        p = MEMDIR / name
        if p.exists():
            files.append(p)
    files.extend(sorted(MEMDIR.glob("20??-??-??.md"), reverse=True))
    return files


def _sections(path: Path) -> list[tuple[str, int, int]]:
    """Return [(title, start_line, end_line)] (1-based, inclusive)."""
    lines = path.read_text(errors="replace").splitlines()
    heads = [i for i, ln in enumerate(lines) if ln.startswith("#")]
    out: list[tuple[str, int, int]] = []
    for n, i in enumerate(heads):
        end = (heads[n + 1] - 1) if n + 1 < len(heads) else len(lines) - 1
        out.append((lines[i].strip(), i + 1, end + 1))
    if not out and lines:
        out.append((path.name, 1, len(lines)))
    return out


def titles() -> None:
    for path in _files():
        print(f"\n{path.relative_to(ROOT)}")
        for title, start, _end in _sections(path):
            print(f"  {start:>5}  {title[:96]}")


def search(term: str, context: int, limit: int) -> int:
    rx = re.compile(re.escape(term), re.IGNORECASE)
    shown = 0
    for path in _files():
        lines = path.read_text(errors="replace").splitlines()
        matched: dict[int, tuple[str, int, int]] = {}
        for idx, ln in enumerate(lines):
            if rx.search(ln):
                for title, start, end in _sections(path):
                    if start - 1 <= idx <= end - 1:
                        matched[start] = (title, start, end)
                        break
        if not matched:
            continue
        print(f"\n=== {path.relative_to(ROOT)} ===")
        for title, start, end in sorted(matched.values()):
            print(f"\n{title}   [lines {start}-{end}]")
            for idx in range(start - 1, end):
                if rx.search(lines[idx]):
                    lo = max(start - 1, idx - context)
                    hi = min(end, idx + context + 1)
                    for j in range(lo, hi):
                        mark = ">>" if rx.search(lines[j]) else "  "
                        print(f"{mark} {j + 1:>5} {lines[j][:160]}")
                    print("   ...")
            shown += 1
            if shown >= limit:
                print(f"\n(limit {limit} reached; narrow the query)")
                return 0
    if shown == 0:
        print(f"no match for {term!r} in the memory files")
        return 1
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("term", nargs="?", help="text to find (case-insensitive)")
    ap.add_argument("--titles", action="store_true", help="list every section title")
    ap.add_argument("--context", type=int, default=1, help="lines of context (default 1)")
    ap.add_argument("--limit", type=int, default=20, help="max sections to show (default 20)")
    args = ap.parse_args()

    if args.titles:
        titles()
        return 0
    if not args.term:
        ap.print_help()
        return 2
    return search(args.term, args.context, args.limit)


if __name__ == "__main__":
    sys.exit(main())
