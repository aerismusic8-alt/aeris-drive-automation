#!/usr/bin/env python3
"""Render and publish a "เกร็ดความรู้" (Thai science-trivia) clip to the channel.

K (2026-11-17): build the trivia lane to the reference quality, make it the
standard, then **upload it to our channel**. `ops/trivia_reel.py` renders the
clip and enforces the clip floor; this is the half that turns a finished clip
into a channel upload — title, description, thumbnail, and a ledger so a re-run
never posts the same fact twice.

It is a deliberate sibling of `music938-1/scripts/release.py`: the same
`branding` name, the same `monetize` footer and subscribe ask, the same
`yt_publish` upload chokepoint (which measures the clip and the thumbnail before
any network call). Everything is free (Rule #1): edge-tts, Wikimedia Commons
footage, ffmpeg, the Data API.

    python3 ops/trivia_publish.py --script scripts_trivia/sky-blue.md --dry-run
    python3 ops/trivia_publish.py --next                 # one not-yet-posted script
    python3 ops/trivia_publish.py --script ... --now     # publish immediately

The ledger lives in `music938-1/work/trivia-state.json`; it is committed so a
fresh runner sees what is already live.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
import tempfile
from datetime import datetime, timezone
from pathlib import Path

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent
sys.path.insert(0, str(HERE))
sys.path.insert(0, str(ROOT / "music938-1" / "scripts"))

import branding  # noqa: E402
import monetize  # noqa: E402
import footage_rail as fr  # noqa: E402
import trivia_reel as tr  # noqa: E402

SCRIPTS = ROOT / "scripts_trivia"
LEDGER = ROOT / "music938-1" / "work" / "trivia-state.json"
THUMBS = ROOT / "music938-1" / "library" / "thumbs"
CH = "ch3"  # the one channel K is growing (@aerismusicth)


def load_state() -> dict:
    try:
        d = json.loads(LEDGER.read_text(encoding="utf-8"))
        return d if isinstance(d, dict) else {"posted": []}
    except (OSError, ValueError):
        return {"posted": []}


def save_state(state: dict) -> None:
    LEDGER.parent.mkdir(parents=True, exist_ok=True)
    LEDGER.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")


def posted_slugs(state: dict) -> set[str]:
    return {r.get("slug") for r in state.get("posted", []) if r.get("slug")}


def pick_scripts(state: dict, only: str | None = None) -> list[Path]:
    """Every trivia script not yet posted, oldest name first, or just one."""
    if only:
        return [Path(only) if os.path.sep in only else SCRIPTS / only]
    done = posted_slugs(state)
    out = []
    for p in sorted(SCRIPTS.glob("*.md")):
        if p.stem not in done:
            out.append(p)
    return out


def first_question(cards: list[str]) -> str:
    """The hook line: the first card, as a question if it reads like one."""
    q = cards[0].strip() if cards else ""
    return q


def make_title(series: str, cards: list[str]) -> str:
    """Search-shaped title: the question first, then the series and a hashtag.

    A zero-subscriber channel is found by search, so the question is the query a
    viewer types; the series name and `#เกร็ดความรู้` sit after it and survive
    YouTube's ~60-char truncation because they are short.
    """
    hook = first_question(cards)
    hook = re.sub(r"[?？]+$", "", hook).strip()
    hook = hook[:60]
    return f"{hook}? | {series} #เกร็ดความรู้"[:100]


def make_description(series: str, cards: list[str], credits: str) -> str:
    body = "\n\n".join(c.strip() for c in cards if c.strip())
    # The CTA already carries the Shopee product link, so the footer is the
    # socials only (`block("short")` keeps it tight and skips the duplicate
    # product line). A trivia clip is a Short-shaped upload, so a short footer
    # is the right shape.
    socials = monetize.block("short")
    parts = [
        f"🧠 {series}",
        "",
        body,
        "",
        branding.LABEL,
        monetize.cta("youtube"),
    ]
    desc = "\n".join(parts).rstrip()
    if socials:
        desc = desc + "\n" + socials
    creds = clean_credits(credits)
    if creds:
        desc = desc.rstrip() + "\n\n📷 ภาพ/ฟุตเทจ (Wikimedia Commons):\n" + creds
    desc = desc.rstrip() + f"\n\n{TRIVIA_HASHTAGS}"
    return desc[:4900]


def make_tags(series: str, cards: list[str]) -> list[str]:
    tags = ["เกร็ดความรู้", "ความรู้รอบตัว", "วิทยาศาสตร์", "สาระน่ารู้",
            series, branding.NAME, "thai facts", "วิทยาศาสตร์น่ารู้"]
    # A couple of salient nouns from the cards help search without stuffing.
    for c in cards[:2]:
        for w in re.split(r"[\s,]+", c):
            if 3 <= len(w) <= 12 and w not in tags:
                tags.append(w)
    return tags[:30]


# The trivia lane is not a song lane, so it gets its own hashtag set instead of
# `branding.HASHTAGS` (which promises "เพลงใหม่"/pop/dance/rock). The brand
# hashtag itself comes from the branding module, never hard-coded here.
TRIVIA_HASHTAGS = (f"{branding.HASHTAG} #เกร็ดความรู้ #ความรู้รอบตัว #วิทยาศาสตร์ "
                   "#สาระน่ารู้ #วิทยาศาสตร์น่ารู้ #เกร็ดวิทยาศาสตร์")


def clean_credits(items: list[dict]) -> str:
    """Plain-text attribution lines from the footage items the reel recorded.

    The reel stores the Commons title, licence, source page and origin for each
    clip it actually used. A CC BY / BY-SA clip requires attribution, and a
    description is plain text, so each item becomes one readable line with the
    licence and the source page (no HTML).
    """
    out = []
    for it in items or []:
        title = (it.get("title") or "").strip()
        lic = (it.get("licence") or "").strip()
        src = (it.get("source") or "").strip()
        origin = (it.get("origin") or "Wikimedia Commons").strip()
        line = f"• {title} — {lic}, via {origin}"
        if src:
            line += f" ({src})"
        out.append(line)
    return "\n".join(out)




def grab_thumb(clip: Path, out: Path) -> Path:
    """A faithful 1280x720 thumbnail: a frame where a card is fully shown.

    The trivia clip's text IS the content, so a mid-clip frame carries the fact
    on screen. Taken at 60 % of the runtime to land on a settled card, then held
    to the thumbnail floor by `yt_publish` like every other thumb.
    """
    dur = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=noprint_wrappers=1:nokey=1", str(clip)],
        capture_output=True, text=True).stdout.strip()
    secs = float(dur) if dur else 0.0
    at = max(1.0, secs * 0.6)
    out.parent.mkdir(parents=True, exist_ok=True)
    subprocess.run(
        ["ffmpeg", "-y", "-loglevel", "error", "-ss", f"{at:.2f}", "-i", str(clip),
         "-frames:v", "1", str(out)], check=True)
    return out


def upload(clip: Path, thumb: Path, title: str, desc: str, tags: list[str],
           schedule: str | None, now: bool, privacy: str) -> str:
    """Call the one upload chokepoint; it measures clip + thumbnail first."""
    with tempfile.TemporaryDirectory() as td:
        descf = Path(td) / "desc.txt"
        tagf = Path(td) / "tags.txt"
        descf.write_text(desc, encoding="utf-8")
        tagf.write_text(", ".join(tags), encoding="utf-8")
        cmd = [sys.executable, str(HERE / "yt_publish.py"), "--ch", CH,
               "--video", str(clip), "--thumb", str(thumb), "--title", title,
               "--desc-file", str(descf), "--tags-file", str(tagf),
               "--category", "27"]
        if now:
            cmd.append("--now")
        elif schedule:
            cmd += ["--schedule", schedule]
        else:
            cmd += ["--privacy", privacy]
        res = subprocess.run(cmd, capture_output=True, text=True)
        sys.stdout.write(res.stdout)
        sys.stderr.write(res.stderr)
        if res.returncode != 0:
            raise SystemExit(f"upload failed (rc {res.returncode})")
        m = re.search(r"video id (\S+)", res.stdout)
        return m.group(1) if m else ""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--script", help="one scripts_trivia/*.md")
    ap.add_argument("--next", action="store_true",
                    help="the first script not yet posted")
    ap.add_argument("--all", action="store_true", help="every unposted script")
    ap.add_argument("--out", default="/tmp/trivia-reel")
    ap.add_argument("--dry-run", action="store_true",
                    help="render + build metadata, do not upload")
    ap.add_argument("--now", action="store_true", help="publish immediately")
    ap.add_argument("--schedule", help="ISO8601 UTC publishAt")
    ap.add_argument("--privacy", default="private")
    a = ap.parse_args()

    state = load_state()
    if a.script:
        scripts = [Path(a.script) if os.path.sep in a.script else SCRIPTS / a.script]
    elif a.next or a.all:
        scripts = pick_scripts(state)
        if not scripts:
            print("every trivia script is already posted")
            return 0
        if a.next:
            scripts = scripts[:1]
    else:
        ap.error("pass --script, --next, or --all")

    for sp in scripts:
        sp = Path(sp)
        if not sp.is_absolute() and not sp.exists():
            sp = SCRIPTS / sp
        slug = sp.stem
        print(f"=== trivia {slug} ===")
        title_h, theme, cards = tr.read_script(str(sp))
        series = title_h

        # Render (the clip floor is enforced inside trivia_reel: a fail removes
        # the file and raises, so a below-floor clip never reaches this code).
        rc = subprocess.run([sys.executable, str(HERE / "trivia_reel.py"),
                             "--script", str(sp), "--out", a.out]).returncode
        if rc != 0:
            raise SystemExit(f"render failed for {slug} (rc {rc})")
        meta = json.loads((Path(a.out) / "trivia.json").read_text(encoding="utf-8"))
        clip = Path(meta["out"])

        title = make_title(series, cards)
        desc = make_description(series, cards, meta.get("credits", []))
        tags = make_tags(series, cards)
        thumb = grab_thumb(clip, THUMBS / f"thumb-trivia-{slug}.png")

        print(f"title: {title}")
        print(f"desc : {len(desc)} chars, {len(tags)} tags, thumb {thumb.name}")

        if a.dry_run:
            print(desc)
            print("dry-run: not uploading")
            continue

        vid = upload(clip, thumb, title, desc, tags, a.schedule, a.now, a.privacy)
        state.setdefault("posted", []).append({
            "slug": slug, "title": title, "video_id": vid, "theme": theme,
            "seconds": meta.get("seconds"), "channel": CH,
            "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        })
        save_state(state)
        print(f"posted {slug} -> https://youtu.be/{vid}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
