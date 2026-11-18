#!/usr/bin/env python3
"""Upload the audio-reactive clip to ch3, retrying until YouTube accepts it.

K (2026-11-18): "เอาขึ้นยูทูป tk ด้วยนะ". The clip is built here and posted to
Facebook and TikTok, but YouTube was mid a per-account daily new-video cap
(`uploadLimitExceeded`, HTTP 400) at the time — a platform wall, not a defect.
A cap clears over hours, so the durable answer is not "wait and re-run by hand"
but a rail that tries again on a schedule until it lands.

The clip and its thumbnail live in the durable `media-938` release, so a fresh
pod or a GitHub runner fetches them by URL — no sandbox, no local state. Success
is recorded in `music938-1/work/reactive-state.json`, so a re-run after a
success is a no-op and the cap can never turn into a double post.

    python3 ops/reactive_publish.py            # upload if not yet done
    python3 ops/reactive_publish.py --dry-run  # show what it would do
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ops"))
sys.path.insert(0, str(ROOT / "music938-1" / "scripts"))

import branding  # noqa: E402

RELEASE = "media-938"
REPO = "aerismusic8-alt/aeris-drive-automation"
BASE = f"https://github.com/{REPO}/releases/download/{RELEASE}"
STATE = ROOT / "music938-1" / "work" / "reactive-state.json"

# One entry per clip this lane owns. `slug` is the ledger key; `full` is the
# landscape clip that goes to YouTube; `thumb` its 16:9 poster.
CLIPS = [
    {
        "slug": "maps-and-concrete",
        "full": "reactive-full-maps-and-concrete.mp4",
        "thumb": "thumb-full-maps-and-concrete.png",
        "title": "Maps and Concrete | ฮิปฮอปฟิวชัน เพลงสนุก ภาพขยับตามเสียง",
        "ch": "ch3",
    },
]


def load_state() -> dict:
    if STATE.exists():
        try:
            return json.loads(STATE.read_text(encoding="utf-8"))
        except Exception:
            pass
    return {"uploaded": {}}


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=1) + "\n",
                     encoding="utf-8")


def fetch(name: str, dest: Path) -> Path:
    if dest.exists() and dest.stat().st_size > 0:
        return dest
    dest.parent.mkdir(parents=True, exist_ok=True)
    with urllib.request.urlopen(f"{BASE}/{name}", timeout=600) as r, \
            open(dest, "wb") as f:
        f.write(r.read())
    return dest


def description(item: dict) -> str:
    return (
        f"🎵 Maps and Concrete — ฮิปฮอปฟิวชัน ไทย·อังกฤษ·ฮินดี\n"
        f"เพลงสนุกจังหวะแดนซ์ ผสมแรพและฮิปฮอปฟิวชัน เนื้อร้องไทย-อังกฤษ-ฮินดี\n"
        f"ภาพขยับตามเสียงจริง — อีควอไลเซอร์เต้นตามบีต มาสคอตหุ่นส้มกวนตีนเต้นตามจังหวะ\n\n"
        f"{branding.LABEL}\n"
        f"❤️ {branding.FOLLOW_ASK} · {branding.FOLLOW_PROMISE}\n"
        f"🎬 {branding.CHANNEL_URL}\n\n"
        f"{branding.HASHTAGS} #ฮิปฮอป #เพลงแรพ #เพลงสนุก"
    )


TAGS = ("เพลงไทย,ฮิปฮอป,แรพ,เพลงใหม่,เพลงสนุก,เพลงแดนซ์,hip hop,thai rap,"
        f"thai hiphop,AI music,{branding.HANDLE.lstrip('@')},audio reactive,equalizer")


def upload(item: dict, tmp: Path, dry: bool) -> bool:
    """True when the clip is on YouTube (or already was)."""
    state = load_state()
    if state["uploaded"].get(item["slug"]):
        print(f"{item['slug']}: already uploaded ({state['uploaded'][item['slug']]}), skipping")
        return True
    if dry:
        print(f"{item['slug']}: would upload {item['full']} to {item['ch']}")
        return True
    video = fetch(item["full"], tmp / item["full"])
    thumb = fetch(item["thumb"], tmp / item["thumb"])
    desc = tmp / f"{item['slug']}.desc.txt"
    desc.write_text(description(item), encoding="utf-8")
    tags = tmp / f"{item['slug']}.tags.txt"
    tags.write_text(TAGS, encoding="utf-8")
    proc = subprocess.run(
        [sys.executable, str(ROOT / "ops" / "yt_publish.py"),
         "--ch", item["ch"], "--video", str(video), "--thumb", str(thumb),
         "--title", item["title"], "--desc-file", str(desc),
         "--tags-file", str(tags), "--category", "10", "--now"],
        capture_output=True, text=True)
    out = proc.stdout + proc.stderr
    print(out.strip())
    if proc.returncode == 0 and "https://youtu.be/" in out:
        vid = out.split("https://youtu.be/")[-1].split()[0].strip()
        state["uploaded"][item["slug"]] = vid
        save_state(state)
        print(f"{item['slug']}: uploaded as {vid}")
        return True
    # A per-account daily cap is a normal, non-fatal outcome: nothing was
    # created, so the next tick simply tries again. Any other failure is real
    # and must fail the rail, so it is not mistaken for the cap.
    if "uploadLimitExceeded" in out:
        print(f"{item['slug']}: YouTube daily upload cap reached — retry on the next tick")
        return False
    raise SystemExit(f"{item['slug']}: upload failed\n{out}")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--tmp", default="/tmp/ax-reactive")
    a = ap.parse_args()
    tmp = Path(a.tmp)
    ok = True
    for item in CLIPS:
        ok = upload(item, tmp, a.dry_run) and ok
    return 0 if ok else 4


if __name__ == "__main__":
    raise SystemExit(main())
