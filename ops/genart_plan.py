#!/usr/bin/env python3
"""Plan one day's generative-art batch: pick algorithm, palette and seeds.

The rail calls this instead of choosing seeds itself, because the choice has to
be reproducible from the committed counter. `counter.json` holds the next seed
and the rotation position; every run reads it, renders, then writes it back, so
the same tick can be re-run without producing a duplicate work.

Rotation is deliberate, not random: it walks the algorithms and palettes in a
fixed order, so a week's output looks like a varied catalogue rather than five
copies of whatever the PRNG favoured.
"""
from __future__ import annotations

import argparse
import json
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
ART = ROOT / "music938-1" / "library" / "art"
COUNTER = ART / "counter.json"

ALGO_ORDER = ["warp", "flow", "react", "attr", "tiles"]
PALETTE_ORDER = ["ember", "tide", "dusk", "moss", "ink", "brass", "orchid", "ash"]
SIZE_ORDER = ["print", "print", "portrait", "print", "wide"]


def load_counter() -> dict:
    if COUNTER.exists():
        return json.loads(COUNTER.read_text())
    return {"seed": 10000, "step": 0}


def save_counter(c: dict) -> None:
    ART.mkdir(parents=True, exist_ok=True)
    COUNTER.write_text(json.dumps(c, indent=0) + "\n")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--count", type=int, default=4)
    ap.add_argument("--algo", default="mix", help="one algorithm name, or 'mix'")
    ap.add_argument("--series", default="", help="series name (default: the month)")
    a = ap.parse_args()

    import genart  # noqa: PLC0415

    c = load_counter()
    step = int(c.get("step", 0))
    seed = int(c.get("seed", 10000))
    series = a.series or f"Series {__import__('datetime').date.today():%Y-%m}"

    made = 0
    for i in range(a.count):
        algo = (a.algo if a.algo != "mix"
                else ALGO_ORDER[(step + i) % len(ALGO_ORDER)])
        palette = PALETTE_ORDER[(step * 3 + i * 5) % len(PALETTE_ORDER)]
        size = SIZE_ORDER[(step + i) % len(SIZE_ORDER)]
        this_seed = seed + i * 137
        try:
            genart.make(algo, size, palette, this_seed, series)
            made += 1
        except Exception as exc:  # noqa: BLE001
            # A draw that fails its own gate is not a reason to fail the day:
            # `make` already deleted the bad file and left the manifest clean.
            print(f"  skip {algo}/{palette}/{this_seed}: {exc}")

    c["seed"] = seed + a.count * 137
    c["step"] = step + a.count
    save_counter(c)
    print(f"planned {made}/{a.count} work(s) in {series!r}; next seed {c['seed']}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
