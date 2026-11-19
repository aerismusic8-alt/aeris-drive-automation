#!/usr/bin/env python3
"""Accumulate high-resolution 9:16 artwork from Dreamina, a little every run.

K (2026-11-19): the art must come from a real AI image app on an account AR can
hold, at a resolution the clips can actually use, and it should pile up in the
library over time. This is that pipeline.

Dreamina is the app: AR registered its own account (`user8583484188414`, no K
Google login involved), the CLI is signed in to 2027-01-18, and it serves
Seedream 4.7 / Nano Banana Pro / GPT Image 2.5 at 9:16. The free tier is 2K —
4K is VIP-only — and 2K measures **1440x2560**, which is above the 1080x1920 a
vertical Short needs, so there is headroom to crop or pan.

Credits are the constraint, not the code: 2K costs 8 credits an image and the
free grant is small, so this script asks for a quote before it spends anything,
stops cleanly at zero, and records what it actually paid. A run that cannot
afford an image is a normal end, not an error.

    python3 ops/art_bank.py --status
    python3 ops/art_bank.py --fill 6          # bank up to 6 new works
    python3 ops/art_bank.py --fill 3 --dry-run
"""
from __future__ import annotations

import argparse
import hashlib
import json
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LIB = ROOT / "music938-1" / "library" / "aiart"
MANIFEST = LIB / "manifest.json"
CLI = "/workspace/ax-tools/bin/dreamina"

MODEL = "seedream_4.7"
RATIO = "9:16"
RESOLUTION = "2K"
MIN_W, MIN_H = 1080, 1920

# Scenes for a Thai rock/punk channel: night streets, stages, rain, rooms. Each
# entry is (key, prompt). The key is what makes a run idempotent, so it must not
# change once a work is banked.
SCENES = [
    ("night-street-rain", "cinematic Thai night street after rain, warm neon reflections on wet asphalt, lone figure walking away, soft haze, 35mm film look, high detail"),
    ("club-stage-scream", "singer screaming into a microphone on a small dark club stage, harsh stage light, sweat, motion blur, gritty concert photograph"),
    ("rooftop-blue-hour", "Bangkok rooftop at blue hour, glowing windows, distant skyline, a small still silhouette, cool cyan and warm sodium lights"),
    ("alley-bare-bulb", "rain-soaked alley lit by one bare bulb, graffiti on concrete walls, deep shadows, raw documentary flash photography"),
    ("train-window-rain", "night train carriage window with rain running down the glass, blurred city lights outside, empty seat, quiet melancholy"),
    ("amps-dark-room", "wall of stacked guitar amplifiers in a dark rehearsal room, one harsh spotlight, dust in the air, cables on a dirty floor"),
    ("market-lanterns", "Thai night market with hanging lanterns and food stalls, warm bokeh, steam and smoke, crowded and alive, shallow depth of field"),
    ("pier-dawn-mist", "small figure at the end of a long wooden pier at dawn, soft mist over calm water, pale pink sky, very quiet"),
    ("broken-sign-corner", "night street corner under a broken flickering neon sign, wet asphalt reflections, torn posters, high contrast grain"),
    ("room-3am-lamp", "quiet room at 3am, a single warm lamp, an unmade bed and a guitar leaning on the wall, dust drifting in the light"),
    ("muay-thai-ring", "Muay Thai boxing ring under harsh overhead lights, ropes and empty seats, chalk dust in the air, dramatic side light"),
    ("skytrain-platform", "Bangkok skytrain platform at night, long exposure light trails, commuters as blurred silhouettes, steel and glass"),
]


def _now() -> str:
    return datetime.now(timezone.utc).replace(microsecond=0).isoformat()


def load() -> dict:
    if MANIFEST.exists():
        return json.loads(MANIFEST.read_text())
    return {"version": 1, "works": [], "credits_spent": 0}


def save(doc: dict) -> None:
    MANIFEST.parent.mkdir(parents=True, exist_ok=True)
    MANIFEST.write_text(json.dumps(doc, indent=1, ensure_ascii=False) + "\n")


def _run(args: list[str], *, timeout: float = 300.0) -> dict:
    """One CLI call, parsed. The CLI always answers JSON with --format json."""
    p = subprocess.run([CLI, "--format", "json", *args], capture_output=True,
                       text=True, timeout=timeout)
    out = p.stdout.strip() or p.stderr.strip()
    try:
        doc = json.loads(out)
    except json.JSONDecodeError:
        raise RuntimeError(f"{' '.join(args[:3])}: unparseable output {out[:200]!r}")
    if not doc.get("ok"):
        err = doc.get("error", {})
        detail = "; ".join(d.get("detail", "") for d in err.get("diagnostics", []))
        raise RuntimeError(f"{' '.join(args[:3])}: {err.get('message', 'failed')} {detail}")
    return doc.get("data", {})


def credits() -> int:
    d = _run(["auth", "account"])
    return int(d.get("availableCredits", 0))


def project_id() -> str:
    """The selected canvas. Two shapes exist: `currentCanvas.canvas` and `project`."""
    d = _run(["canvas", "current"])
    pid = ((d.get("currentCanvas") or {}).get("canvas") or {}).get("projectId")
    pid = pid or (d.get("project") or {}).get("projectId")
    if not pid:
        raise RuntimeError("no canvas selected; run: dreamina canvas use <projectId>")
    return pid


def make_one(key: str, prompt: str, pid: str, *, dry_run: bool, log=print) -> dict | None:
    """One image: create, quote, run, wait, download, describe. None if unaffordable."""
    title = f"art {key}"
    node = _run(["node", "create", "image", "--mode", "t2i", "--model", MODEL,
                 "--prompt", prompt, "--ratio", RATIO, "--resolution", RESOLUTION,
                 "--title", title])
    nid = (node.get("node") or {}).get("nodeId") or node.get("nodeId")
    if not nid:
        raise RuntimeError(f"{key}: no node id in {json.dumps(node)[:200]}")

    quote = _run(["node", "quote", "--node-id", nid])
    cost = int(quote.get("totalMaxCredits", 0))
    have = credits()
    log(f"  {key}: quote {cost} credits, {have} available")
    if cost > have:
        log(f"  {key}: cannot afford, stopping")
        return None
    if dry_run:
        log(f"  {key}: dry run, would spend {cost}")
        return None

    run = _run(["node", "run", "--node-id", nid])
    item = (run.get("items") or [{}])[0]
    submit = item.get("submitId")
    if not submit:
        raise RuntimeError(f"{key}: no submit id in {json.dumps(run)[:200]}")

    op = _run(["operation", "wait", submit, "--project-id", pid], timeout=900.0)
    res = (op.get("resources") or [{}])[0]
    if op.get("state") != "succeeded" or not res.get("resourceId"):
        raise RuntimeError(f"{key}: generation ended {op.get('state')}")

    LIB.mkdir(parents=True, exist_ok=True)
    dest = LIB / f"{key}.jpg"
    _run(["resource", "download", res["resourceId"], "-o", str(dest)])

    return {"id": key, "file": str(dest.relative_to(LIB)), "prompt": prompt,
            "model": MODEL, "ratio": RATIO, "resolution": RESOLUTION,
            "w": res.get("width"), "h": res.get("height"),
            "bytes": dest.stat().st_size,
            "sha": hashlib.sha256(dest.read_bytes()).hexdigest()[:20],
            "credits": cost, "at": _now(), "uses": 0}


def _usable(w: int, h: int) -> tuple[bool, str]:
    if not w or not h:
        return False, "unknown size"
    if w < MIN_W or h < MIN_H:
        return False, f"{w}x{h} is below {MIN_W}x{MIN_H}"
    return True, f"{w}x{h}"


def fill(want: int, *, dry_run: bool, log=print) -> int:
    doc = load()
    have = {w["id"] for w in doc["works"]}
    todo = [(k, p) for k, p in SCENES if k not in have][:want]
    if not todo:
        log(f"bank already holds all {len(SCENES)} scenes; add to SCENES to grow")
        return 0
    pid = project_id()
    made = 0
    for key, prompt in todo:
        try:
            rec = make_one(key, prompt, pid, dry_run=dry_run, log=log)
        except Exception as exc:
            log(f"  {key}: FAILED {exc}")
            continue
        if not rec:
            break
        ok, why = _usable(rec["w"] or 0, rec["h"] or 0)
        if not ok:
            log(f"  {key}: rejected {why}")
            Path(LIB / rec["file"]).unlink(missing_ok=True)
            continue
        doc["works"].append(rec)
        doc["credits_spent"] = doc.get("credits_spent", 0) + rec["credits"]
        save(doc)
        made += 1
        log(f"  {key}: banked {why}, {rec['bytes'] // 1024} KB, {rec['credits']} credits")
    log(f"fill: {made} new, bank {len(doc['works'])} works, "
        f"{doc.get('credits_spent', 0)} credits spent all-time")
    return made


def status(log=print) -> None:
    doc = load()
    works = doc["works"]
    log(f"bank: {len(works)} works, {doc.get('credits_spent', 0)} credits spent")
    for w in works:
        log(f"  {w['id']:22s} {w['w']}x{w['h']} {w['bytes'] // 1024:5d} KB  {w['model']}")
    left = [k for k, _ in SCENES if k not in {w["id"] for w in works}]
    log(f"unbanked scenes: {len(left)}")
    for k in left:
        log(f"  {k}")
    try:
        log(f"credits available now: {credits()}")
    except Exception as exc:
        log(f"credits: unavailable ({exc})")


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--fill", type=int, metavar="N", help="bank up to N new works")
    ap.add_argument("--status", action="store_true")
    ap.add_argument("--dry-run", action="store_true")
    a = ap.parse_args()
    if a.status or not a.fill:
        status()
        return 0
    fill(a.fill, dry_run=a.dry_run)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
