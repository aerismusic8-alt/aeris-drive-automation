#!/usr/bin/env python3
"""Ship a rendered bank clip to every channel that is ready for it.

A bank clip is a song plus stills (see `clip_lane.py`). This is its publishing
half, and it is deliberately the *only* way a bank clip reaches an audience, so
the QC gate cannot be bypassed by picking a different script.

The order is fixed and it matters:

1. `genre_verdict` — the song must be in a publishable genre.
2. `clip_standard.assert_ok` — the technical floor (loudness, codec, motion).
3. `thumb_standard.assert_ok` — the thumbnail floor.
4. Upload.

Steps 2-4 are re-checked inside the uploaders themselves, so running this twice
is not what keeps the gate honest; the gate lives on the upload path.

Channels that have no credentials are reported as `skipped`, never as done. A
missing TikTok token must not read as "posted".
"""
from __future__ import annotations

import argparse
import json
import os
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ops"))
sys.path.insert(0, str(ROOT / "music938-1" / "scripts"))

BANK = ROOT / "music938-1" / "library" / "bank"
STATE = ROOT / "music938-1" / "work" / "bank-publish-state.json"


def _branding():
    import branding  # noqa: PLC0415  (music938-1/scripts)

    return branding


SONG_SLUGS = None


def _song_slug(clip: Path) -> str | None:
    """The song slug inside a bank file name, e.g. `19-lom-nao-...`.

    Longest match wins, because one slug can be a prefix of another. Matching the
    song library beats splitting the file name: the slug maps to a real Thai
    title and a calibrated set of tags, while a split only yields transliteration.
    """
    import release  # noqa: PLC0415

    global SONG_SLUGS
    if SONG_SLUGS is None:
        SONG_SLUGS = sorted(release.all_slugs(), key=len, reverse=True)
    body = clip.stem[5:] if clip.stem.startswith("bank-") else clip.stem
    # The file name puts the kind before the number ("song-19-...", "karaoke-06-...")
    # while the slug leads with it ("19-...", "06-..."), so compare on the song
    # words with the number moved to the front.
    for slug in SONG_SLUGS:
        number, _, words = slug.partition("-")
        if not words:
            continue
        for kind in ("song", "karaoke", "music", "short", "mv"):
            if body.startswith(f"{kind}-{number}-{words}"):
                return slug
        if body.startswith(slug):
            return slug
    return None


def clip_title(clip: Path) -> str:
    import release  # noqa: PLC0415

    slug = _song_slug(clip)
    if slug:
        return release.describe(slug, "short")[0]
    return clip.stem.replace("-", " ").title()


def clip_tags(clip: Path) -> list[str]:
    import release  # noqa: PLC0415

    slug = _song_slug(clip)
    return release.describe(slug, "short")[2] if slug else []


def build_caption(clip: Path) -> str:
    """Description for every channel: the calibrated text plus the follow ask.

    K's metric is followers, so the ask closes every post — a view without a
    follow is the failure case.
    """
    import release  # noqa: PLC0415

    b = _branding()
    slug = _song_slug(clip)
    body = release.describe(slug, "short")[1] if slug else b.DESCRIPTION
    return "\n".join([
        body,
        "",
        f"{b.FOLLOW_ASK} — {b.FOLLOW_PROMISE}",
        b.CHANNEL_URL,
        "",
        b.HASHTAGS,
        "",
        b.LABEL,
    ])


def make_thumb(clip: Path, out: Path) -> Path:
    """A 1280x720 cover from a frame of the clip itself.

    Picking a frame from the clip guarantees the thumbnail matches the video,
    and it avoids a second image source that could drift from what was reviewed.
    """
    subprocess.run(
        ["ffmpeg", "-y", "-hide_banner", "-loglevel", "error",
         "-ss", "1.5", "-i", str(clip), "-frames:v", "1",
         "-vf", "scale=1280:720:force_original_aspect_ratio=increase,crop=1280:720",
         str(out)],
        check=True)
    return out


def youtube(clip: Path, *, when: str | None, privacy: str | None) -> dict:
    """Upload through `yt_publish`, which enforces both gates itself."""
    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        thumb = make_thumb(clip, td / "thumb.jpg")
        desc = td / "desc.txt"
        desc.write_text(build_caption(clip), encoding="utf-8")
        tags = td / "tags.txt"
        tags.write_text(",".join(clip_tags(clip)), encoding="utf-8")
        cmd = [sys.executable, str(ROOT / "ops" / "yt_publish.py"),
               "--ch", "ch3", "--video", str(clip), "--thumb", str(thumb),
               "--title", clip_title(clip), "--desc-file", str(desc),
               "--tags-file", str(tags), "--category", "10"]  # 10 = Music
        if when:
            cmd += ["--schedule", when]
        elif privacy:
            cmd += ["--privacy", privacy]
        else:
            cmd += ["--now"]
        r = subprocess.run(cmd, capture_output=True, text=True)
        return {"ok": r.returncode == 0,
                "detail": (r.stdout or r.stderr).strip().splitlines()[-1:] or [""]}


def facebook(clip: Path) -> dict:
    """Post the reel to the Page through the Graph API.

    Browser posting is off (K, 2026-11-15: the automation is detectable), so the
    API is the only Facebook route and `available()` says whether it can run.
    """
    import fb_graph  # noqa: PLC0415

    if not fb_graph.available():
        return {"ok": False, "skipped": "no Page token"}
    vid = fb_graph.post_reel(clip, build_caption(clip))
    return {"ok": bool(vid), "id": vid}


def tiktok(clip: Path) -> dict:
    import tiktok_api  # noqa: PLC0415

    if not getattr(tiktok_api, "available", lambda: True)():
        return {"ok": False, "skipped": "no TikTok token"}
    res = tiktok_api.post_video(clip, build_caption(clip))
    return {"ok": bool(res), "id": res}


def genre_verdict(clip: Path) -> tuple[bool, str]:
    """May this clip's song be published at all? (K's genre direction.)

    Checked before the content and technical gates, because a clip in the wrong
    lane should never reach an audience no matter how good it looks. On
    2026-11-19 two เพื่อชีวิต clips were published here: the bank held only the
    original 20 songs, the gate below did not exist, and nothing else looked.
    """
    import genres  # noqa: PLC0415

    slug = _song_slug(clip)
    if not slug:
        return False, "no song slug in the file name — cannot check its genre"
    return genres.publishable(slug)


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("clip", nargs="?", help="clip to publish; default: every passed clip")
    ap.add_argument("--channels", default="youtube,facebook,tiktok")
    ap.add_argument("--schedule", help="ISO8601 UTC for YouTube")
    ap.add_argument("--privacy", help="explicit YouTube privacy instead of --now")
    ap.add_argument("--dry-run", action="store_true", help="gate and build, upload nothing")
    a = ap.parse_args()

    clips = [Path(a.clip)] if a.clip else sorted(BANK.glob("*.mp4"))
    if not clips:
        raise SystemExit("no clips in the bank")

    state = json.loads(STATE.read_text(encoding="utf-8")) if STATE.exists() else {}
    wanted = [c.strip() for c in a.channels.split(",") if c.strip()]
    rc = 0

    for clip in clips:
        if not clip.exists():
            print(f"missing: {clip}")
            rc = 1
            continue
        # The gate is checked here for a clear message, and again inside every
        # uploader. Belt and braces on purpose: the message differs, the rule not.
        ok, why = genre_verdict(clip)
        if not ok:
            print(f"BLOCKED  {clip.name}: {why}")
            rc = 1
            continue
        print(f"GENRE OK {clip.name}  ({why})")
        if a.dry_run:
            print(f"  title: {clip_title(clip)}")
            continue

        done = state.setdefault(clip.name, {})
        for ch in wanted:
            if done.get(ch, {}).get("ok"):
                print(f"  {ch:<9} already done ({done[ch].get('id')})")
                continue
            try:
                if ch == "youtube":
                    res = youtube(clip, when=a.schedule, privacy=a.privacy)
                elif ch == "facebook":
                    res = facebook(clip)
                elif ch == "tiktok":
                    res = tiktok(clip)
                else:
                    res = {"ok": False, "skipped": f"unknown channel {ch}"}
            except SystemExit as e:
                res = {"ok": False, "detail": str(e)}
            except Exception as e:  # noqa: BLE001 - report, never crash the batch
                res = {"ok": False, "detail": f"{type(e).__name__}: {e}"}
            done[ch] = res
            tag = "posted" if res.get("ok") else (
                f"skipped: {res['skipped']}" if res.get("skipped") else "FAILED")
            print(f"  {ch:<9} {tag} {res.get('id') or res.get('detail') or ''}")
            if not res.get("ok") and not res.get("skipped"):
                rc = 1
            STATE.parent.mkdir(parents=True, exist_ok=True)
            STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2),
                             encoding="utf-8")
    return rc


if __name__ == "__main__":
    raise SystemExit(main())
