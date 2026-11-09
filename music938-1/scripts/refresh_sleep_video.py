#!/usr/bin/env python3
"""Replace the live sleep/ambient video if it was rendered with the old synth.

K (2026-11-09): the ffmpeg tone synth that made "เพลงกล่อมนอน" "sounds fake —
stop using it." The renderer now uses real instruments (`soundfont`), but the
video already live was made by the old synth, and YouTube has no "swap the file"
call. So the fix is upload-then-delete, the same deliberate two-step
`replace_video.py` uses: upload and confirm the new id exists *before* deleting
the old one, so a failed upload never leaves the channel with nothing.

The state file is the guard, exactly like the "build once" step:

  * no state, or no `video_id`   -> nothing live yet; the once-step owns it
  * `instrument: soundfont`      -> already the real-instrument render; skip
  * anything else (the old synth)-> upload the corrected file, then delete the old

Idempotent: once the state carries `instrument: soundfont`, every later run
skips, so a retry never double-uploads.

    python3 scripts/refresh_sleep_video.py --plan        # what it would do
    python3 scripts/refresh_sleep_video.py --apply       # upload + delete
"""
from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OPS = ROOT.parent / "ops"
STATE = ROOT / "work" / "compilation-state-ambient-sleep.json"
STEM = "ambient-sleep"
CHANNEL = "ch3"
# The corrected render is the real-instrument one; this marker says so.
MARKER = "soundfont"
MIN_MINUTES = 4 * 60   # the sleep title promises length; a short file is a lie


def _paths() -> tuple[Path, Path, Path]:
    return (ROOT / "library" / "compilations" / f"{STEM}.mp4",
            ROOT / "library" / "compilations" / f"{STEM}.txt",
            ROOT / "library" / "compilations" / f"{STEM}.title")


def _duration(path: Path) -> float:
    res = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "csv=p=0", str(path)], capture_output=True, text=True)
    try:
        return float(res.stdout.strip())
    except ValueError:
        return 0.0


def decide(state: dict | None, minutes: float, has_mp4: bool) -> dict:
    """The whole decision, as pure data, so it is testable without a network.

    `state` is the parsed state file (None when absent), `minutes` is the
    corrected render's length (0 when missing), `has_mp4` says whether it exists.
    """
    if state is None:
        return {"action": "skip", "why": "no state file; the once-step owns it"}
    old = state.get("video_id")
    if not old:
        return {"action": "skip", "why": "no video_id in state"}
    if state.get("instrument") == MARKER:
        return {"action": "skip", "why": f"already {MARKER}", "old": old}
    if not has_mp4:
        return {"action": "skip", "why": "no corrected render on disk", "old": old}
    if minutes < MIN_MINUTES:
        return {"action": "skip", "old": old,
                "why": f"render is {minutes:.0f} min, under the "
                       f"{MIN_MINUTES // 60}h floor"}
    return {"action": "replace", "old": old, "minutes": minutes}


def plan() -> dict:
    """Decide what to do, without touching the network."""
    state = (json.loads(STATE.read_text(encoding="utf-8"))
             if STATE.exists() else None)
    mp4, txt, title_file = _paths()
    decision = decide(state, _duration(mp4) / 60 if mp4.exists() else 0.0,
                      mp4.exists())
    if decision["action"] == "replace":
        decision.update(mp4=mp4, txt=txt, title_file=title_file)
    return decision


def _upload(mp4: Path, txt: Path, title_file: Path) -> str | None:
    title = (title_file.read_text(encoding="utf-8").strip()
             if title_file.exists() else "เพลงกล่อมนอน 8 ชั่วโมง | AERIS Music")
    desc = txt.read_text(encoding="utf-8").rstrip() if txt.exists() else ""
    desc_file = ROOT / "work" / "refresh-sleep.desc"
    tags_file = ROOT / "work" / "refresh-sleep.tags"
    desc_file.write_text(desc, encoding="utf-8")
    tags_file.write_text("เพลงกล่อมนอน,เพลงผ่อนคลาย,นอนหลับสบาย,sleep music,"
                         "relaxing music,AERIS Music", encoding="utf-8")
    thumb = ROOT / "library" / "thumbs" / f"thumb-{STEM}.png"
    cmd = [sys.executable, str(OPS / "yt_publish.py"), "--ch", CHANNEL,
           "--video", str(mp4), "--title", title[:100],
           "--desc-file", str(desc_file), "--tags-file", str(tags_file),
           "--category", "10", "--privacy", "public"]
    if thumb.exists():
        cmd += ["--thumb", str(thumb)]
    proc = subprocess.run(cmd, text=True, capture_output=True)
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    if proc.returncode != 0:
        return None
    m = re.search(r"video id (\S+)", proc.stdout)
    return m.group(1) if m else None


def _delete(video_id: str) -> bool:
    """Delete the old id. --force because the fake render may already have views.

    The point is to remove a video whose audio K rejected; a handful of views on
    it does not outweigh that.
    """
    proc = subprocess.run(
        [sys.executable, str(OPS / "yt_video_delete.py"), "apply", CHANNEL,
         video_id, "--yes", "--force"], text=True, capture_output=True)
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    return proc.returncode == 0


def _ensure_render(state: dict) -> None:
    """Build the corrected render if it is not on disk.

    CI cannot rely on the once-step having left the file: that step is guarded by
    the same state file, so on the run that swaps the video it skips and the
    corrected mp4 was never built. Render it here instead. The bed caches by
    mood+key, so a re-run is cheap.
    """
    mp4, _, _ = _paths()
    if mp4.exists():
        return
    minutes = state.get("minutes", 480)
    print(f"refresh: no corrected render; building {minutes:g} min now")
    proc = subprocess.run(
        [sys.executable, str(Path(__file__).resolve().parent / "ambient_loop.py"),
         "--preset", "sleep", "--minutes", str(minutes), "--render"],
        cwd=str(ROOT), text=True)
    if proc.returncode != 0 or not mp4.exists():
        raise SystemExit("refresh: could not build the corrected render")


def apply() -> int:
    if not STATE.exists():
        print("refresh: skip — no state file; the once-step owns it")
        return 0
    state = json.loads(STATE.read_text(encoding="utf-8"))
    if not state.get("video_id"):
        print("refresh: skip — no video_id in state")
        return 0
    if state.get("instrument") == MARKER:
        print(f"refresh: skip — already {MARKER}")
        return 0
    # Only now pay for the render: everything above says the swap is wanted.
    _ensure_render(state)
    decision = plan()
    if decision["action"] == "skip":
        print(f"refresh: skip — {decision['why']}")
        return 0
    old = decision["old"]
    print(f"refresh: replacing {old} (old synth) with the real-instrument render")
    new = _upload(decision["mp4"], decision["txt"], decision["title_file"])
    if not new:
        print("refresh: upload failed; the old video is untouched", file=sys.stderr)
        return 1
    print(f"refresh: uploaded {new}; deleting the old render {old}")
    _delete(old)
    state.update({"video_id": new, "instrument": MARKER, "replaced": old,
                  "minutes": round(decision["minutes"], 1),
                  "at": datetime.now(timezone.utc).isoformat(timespec="seconds")})
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"refresh: done — {new} is live, state updated")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--plan", action="store_true")
    ap.add_argument("--apply", action="store_true")
    args = ap.parse_args()
    if args.apply:
        return apply()
    print(json.dumps(plan(), ensure_ascii=False, indent=2, default=str))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
