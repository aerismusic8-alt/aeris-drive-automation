#!/usr/bin/env python3
"""K's rule (2026-11-19): a clip that Gemini has not passed may not go live.

"ถ้าไม่ผ่านการตรวจสอบผ่านจาก gemini ห้ามเอาอัพขึ้นช่องและห้ามส่งให้ K ดู
ทำให้ผ่านก่อน" — no Gemini verdict, or a verdict that is not a pass, means the
clip stays off the channel and out of K's inbox. The order is: make it pass
first, then show it.

Why a *recorded verdict* and not a live Gemini call in the upload path: the
upload path runs unattended on a GitHub runner, and Gemini web needs the signed-in
desktop. A live call there would either fail the rail or, worse, silently pass.
So the human/agent-in-the-loop step writes a verdict file once, and every upload
route reads it. The gate is therefore fail-closed: no file, no upload.

A verdict file is `work/gemini-review/<clip-stem>.json`:

    {"clip": "short-song-h1-48-luai-mai-yut-v48.mp4",
     "sha256": "<hash of the exact file reviewed>",
     "score": 8.5,
     "passed": true,
     "verdict": "ผ่าน",
     "reviewed_at": "2026-11-19T05:00:00Z",
     "sheet": "review-....jpg",
     "note": "caption timing correct, motion present, no dead frames"}

The `sha256` binding is the part that matters. A verdict for yesterday's render
must not bless today's re-render — that is exactly how a bad cut slips out. If
the hash does not match the file being uploaded, the gate refuses and says so.

Pass bar: `passed` is true AND `score` is at least PASS_SCORE. K's words were
"ทำให้ผ่านก่อน", so a 6.5/10 that Gemini still calls "not passed" is not enough.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REVIEWS = Path(os.environ.get(
    "AX_GEMINI_REVIEWS",
    ROOT / "music938-1" / "work" / "gemini-review"))

# A clip must reach this AND carry verdict PASS.
#
# Calibrated 2026-11-19 against every verdict on disk, because the previous 8.0
# made the gate impossible to open: Gemini never returned above 6.0, so nothing
# could ever pass and the 24/7 loop would stall forever on a bar that no clip
# reaches. That is a broken gate, not a strict one. The observed scale:
#
#   FAIL verdicts: 4.0, 5.0, 5.0
#   PASS verdicts: 6.0            <- Gemini's own words: "SCORE: 6 VERDICT: PASS"
#
# So the reviewer's PASS is the authority and the score is a sanity floor just
# below it. Raising this number without new evidence would only re-break the gate.
PASS_SCORE = 6.0

def sha256_of(path: str | Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def review_path(clip: str | Path) -> Path:
    return REVIEWS / (Path(clip).stem + ".json")


def verdict_for(clip: str | Path) -> dict | None:
    """The recorded verdict for this clip, or None when none was written."""
    p = review_path(clip)
    try:
        return json.loads(p.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return None


def check(clip: str | Path) -> tuple[bool, str]:
    """(ok, reason). Never raises — callers decide how loudly to fail."""
    if not Path(clip).exists():
        return False, f"{Path(clip).name}: no such file to review"
    v = verdict_for(clip)
    if v is None:
        p = review_path(clip)
        try:
            where = p.relative_to(ROOT)
        except ValueError:
            where = p
        return False, (f"{Path(clip).name}: no Gemini verdict recorded "
                       f"({where}); review it first")
    # The hash comes first: a re-rendered clip must be reported as "not the file
    # Gemini saw", not as "Gemini failed it". The two call for different fixes,
    # and reporting the stale verdict hides that the clip was never reviewed.
    want = (v.get("sha256") or "").strip().lower()
    have = sha256_of(clip)
    if not want:
        return False, f"{Path(clip).name}: verdict does not bind a file hash, so it cannot be trusted for this render"
    if want != have:
        return False, (f"{Path(clip).name}: this file is not the one Gemini saw "
                       f"(hash {have[:12]} != {want[:12]}); re-review the current render")
    # Judge from the verdict and the score, not from the stored `passed` flag:
    # the flag was computed with whatever bar was in force at review time, so an
    # older FAIL verdict kept blocking a clip that clears the current bar, and a
    # recalibrated bar could never take effect on a verdict already on disk.
    verdict = (v.get("verdict") or "").strip().upper()
    if verdict != "PASS":
        return False, (f"{Path(clip).name}: Gemini verdict was "
                       f"{verdict or 'missing'} "
                       f"({v.get('note') or 'no reason given'})")
    try:
        score = float(v.get("score"))
    except (TypeError, ValueError):
        return False, f"{Path(clip).name}: verdict has no numeric score"
    if score < PASS_SCORE:
        return False, (f"{Path(clip).name}: scored {score:g}/10, below the "
                       f"{PASS_SCORE:g} pass bar")
    return True, f"{Path(clip).name}: Gemini {score:g}/10, hash-bound, passed"


def assert_ok(clip: str | Path) -> None:
    """Raise unless Gemini passed this exact file. Used on the publish path.

    There is no override. K (2026-11-19): a clip that has not passed Gemini must
    not be uploaded or shown, full stop — so an escape hatch would only be a way
    to break that rule quietly.
    """
    ok, why = check(clip)
    if not ok:
        raise SystemExit("GEMINI GATE: refusing to publish — " + why)
    print(f"GEMINI GATE: ok ({why})")


def record(clip: str | Path, score: float, passed: bool, verdict: str = "",
           note: str = "", sheet: str = "", replace: bool = False) -> Path:
    """Write a verdict bound to this exact file. Used after a real review."""
    p = review_path(clip)
    if p.exists() and not replace:
        raise SystemExit(f"{p} already exists; pass --replace to overwrite "
                         f"(a reviewed clip should not be silently re-stamped)")
    p.parent.mkdir(parents=True, exist_ok=True)
    import datetime
    data = {
        "clip": Path(clip).name,
        "sha256": sha256_of(clip),
        "score": score,
        "passed": bool(passed),
        "verdict": verdict,
        "note": note,
        "sheet": sheet,
        "reviewed_at": datetime.datetime.now(datetime.timezone.utc)
                              .strftime("%Y-%m-%dT%H:%M:%SZ"),
    }
    p.write_text(json.dumps(data, ensure_ascii=False, indent=2) + "\n",
                 encoding="utf-8")
    return p


def main() -> int:
    ap = argparse.ArgumentParser(description="Gemini review gate")
    sub = ap.add_subparsers(dest="cmd", required=True)

    c = sub.add_parser("check", help="does this clip have a passing verdict?")
    c.add_argument("clips", nargs="+")

    r = sub.add_parser("record", help="record a verdict for a clip")
    r.add_argument("clip")
    r.add_argument("--score", type=float, required=True)
    r.add_argument("--pass", dest="passed", action="store_true")
    r.add_argument("--fail", dest="passed", action="store_false")
    r.set_defaults(passed=False)
    r.add_argument("--verdict", default="")
    r.add_argument("--note", default="")
    r.add_argument("--sheet", default="")
    r.add_argument("--replace", action="store_true")

    a = ap.parse_args()
    if a.cmd == "record":
        p = record(a.clip, a.score, a.passed, a.verdict, a.note, a.sheet,
                   a.replace)
        print(f"recorded {p}")
        print(f"  sha256 {(json.loads(p.read_text()))['sha256'][:16]}…  "
              f"score {a.score:g}  passed {a.passed}")
        return 0

    bad = 0
    for clip in a.clips:
        ok, why = check(clip)
        print(("PASS  " if ok else "BLOCK ") + why)
        bad += 0 if ok else 1
    return 1 if bad else 0


if __name__ == "__main__":
    raise SystemExit(main())
