#!/usr/bin/env python3
"""Release music938-1 songs to the AERIS Music channel (ch3), on a plan.

Two hard limits decide the shape of this:

1. **YouTube Data API quota.** A project gets 10,000 units/day and every
   `videos.insert` costs 1,600, so at most **~6 uploads per day** from one
   project. This plans and paces releases around that, and `--plan` shows the
   schedule before anything is sent.
2. **K reviews a channel's first work.** The first upload of the pack is a
   private draft for K to approve. Nothing is made public by this script unless
   `--public` is passed explicitly.

Each song is released as two videos, which doubles the catalogue for one set of
songs:
  * the **song** (vocal + backing) — the main release
  * the **karaoke** (backing only) — the sing-along version

    python3 scripts/release.py --plan                 # what would be released, when
    python3 scripts/release.py --plan --days 4
    python3 scripts/release.py --next --ch ch3        # upload the next one, private
    python3 scripts/release.py --next --public        # ... and make it public
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OPS = ROOT.parent / "ops"
LYRICS = ROOT / "lyrics"
SONGS = ROOT / "library" / "songs"
KARAOKE = ROOT / "library" / "karaoke"
COVERS = ROOT / "library" / "covers"
STATE = ROOT / "work" / "release-state.json"

UPLOADS_PER_DAY = 6  # 10,000 units / 1,600 units per videos.insert

# A song's release blurb is written from its own header, so the 20 descriptions
# stay consistent without being hand-copied 20 times.
TAGLINE = {
    "sad": "เพลงเศร้า ที่เข้าใจความเสียใจ",
    "warm": "เพลงอบอุ่น ฟังแล้วใจนุ่ม",
    "hopeful": "เพลงให้กำลังใจ เริ่มวันใหม่อีกครั้ง",
    "calm": "เพลงผ่อนคลาย ฟังสบายทุกเวลา",
    "mystic": "เพลงลึกลับ ชวนคิด ชวนฝัน",
    "epic": "เพลงทรงพลัง ปลุกใจให้ลุกขึ้นสู้อีกครั้ง",
}
HASHTAGS = ("#AERISMusic #เพลงไทย #ศิลปินไทย #เพลงใหม่ #เพลงเพื่อชีวิต "
            "#คาราโอเกะ #เพลงเพราะ")


def parse_lyrics(slug: str) -> dict:
    """Read the `# KEY: value` header block off a lyric file."""
    hdr: dict[str, str] = {}
    text = (LYRICS / f"{slug}.txt").read_text(encoding="utf-8")
    for line in text.splitlines():
        m = re.match(r"#\s*(TITLE|SUBTITLE|KEY|MOOD|TEMPO|VOICE)\s*:\s*(.+)", line)
        if m:
            hdr[m.group(1)] = m.group(2).strip()
            continue
        if line.strip() and not line.startswith("#"):
            break
    return hdr


def all_slugs() -> list[str]:
    return sorted(f.stem for f in LYRICS.glob("*.txt"))


def has_song(slug: str) -> bool:
    return (SONGS / f"song-{slug}.mp3").exists()


def has_video(slug: str, mix: str) -> bool:
    return (KARAOKE / f"{mix}-{slug}.mp4").exists()


def load_state() -> dict:
    if STATE.exists():
        try:
            return json.loads(STATE.read_text(encoding="utf-8"))
        except ValueError:
            pass
    return {"released": [], "playlists": {}}


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=1), encoding="utf-8")


def describe(slug: str, kind: str) -> tuple[str, str, list[str]]:
    """Return (title, description, tags) for one release."""
    h = parse_lyrics(slug)
    title_th = h.get("TITLE", slug)
    mood = h.get("MOOD", "calm")
    tagline = TAGLINE.get(mood, TAGLINE["calm"])
    n = slug.split("-")[0]

    if kind == "karaoke":
        title = f"{title_th} (คาราโอเกะ) — ร้องตามได้ | AERIS Music"
        desc = (
            f"🎤 {title_th} — เวอร์ชันคาราโอเกะ (ไม่มีเสียงร้อง)\n\n"
            f"ร้องตามได้เลย! {tagline}\n\n"
            f"🎵 เพลงที่ {int(n)} จากชุด 20 เพลงไทย\n"
            f"🎧 ฟังเวอร์ชันเต็ม (มีเสียงร้อง) ได้ในช่อง\n"
            f"✨ สร้างจากความตั้งใจ ไม่ใช่ความเร็ว\n\n"
            f"{HASHTAGS}"
        )
    else:
        title = f"{title_th} — {tagline} | AERIS Music"
        desc = (
            f"🎵 {title_th}\n\n"
            f"{tagline}\n\n"
            f"เพลงที่ {int(n)} จากชุด 20 เพลงไทย — ร้องด้วยเสียงจริง "
            f"เนื้อร้องและทำนองใหม่\n\n"
            f"🎧 ฟังเพลิน ฟังได้ทุกวัน\n"
            f"🎤 คาราโอเกะมีให้ในช่อง (ไม่มีเสียงร้อง)\n"
            f"✨ สร้างจากความตั้งใจ ไม่ใช่ความเร็ว\n\n"
            f"{HASHTAGS}"
        )
    tags = ["เพลงไทย", "เพลงใหม่", "ศิลปินไทย", "AERIS", "เพลงเพราะ",
            "เพลงฟังสบาย", "คาราโอเกะ", title_th, tagline, "thai music", "thai song"]
    return title[:100], desc[:4900], tags[:30]


def playlist_for(kind: str) -> tuple[str, str]:
    """(title, description) of the playlist this kind of release belongs in."""
    if kind == "karaoke":
        return ("คาราโอเกะ — ร้องตามได้ทุกเพลง",
                "รวมทุกเพลงในชุดเป็นเวอร์ชันคาราโอเกะ ไม่มีเสียงร้อง ร้องตามได้เลย\n\n"
                "AERIS Music · เพลงไทยที่ตั้งใจทำ")
    return ("เพลงไทยเพื่อชีวิต — ชุด 20 เพลง",
            "รวมทุกเพลงในชุด 20 เพลงไทยเพื่อชีวิต ร้องด้วยเสียงจริง เนื้อร้องและทำนองใหม่\n\n"
            "AERIS Music · ฟังเพลิน ฟังได้ทุกวัน")


def ensure_playlist(state: dict, kind: str, ch: str) -> str | None:
    """Create the playlist once and remember its id in the state file."""
    title, desc = playlist_for(kind)
    key = f"{ch}:{kind}"
    if state.get("playlists", {}).get(key):
        return state["playlists"][key]

    sys.path.insert(0, str(OPS))
    import yt_auth  # noqa: E402
    import urllib.request  # noqa: E402
    import urllib.error  # noqa: E402
    tok = yt_auth.access_token(ch)
    body = json.dumps({
        "snippet": {"title": title[:150], "description": desc[:5000],
                    "defaultLanguage": "th"},
        "status": {"privacyStatus": "public"},
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://www.googleapis.com/youtube/v3/playlists?part=snippet,status",
        data=body, method="POST",
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            pid = json.loads(r.read())["id"]
    except urllib.error.HTTPError as e:
        print(f"playlist create failed: HTTP {e.code} {e.read()[:200]}", file=sys.stderr)
        return None
    state.setdefault("playlists", {})[key] = pid
    print(f"created playlist {pid}: {title}")
    return pid


def add_to_playlist(playlist_id: str, video_id: str, ch: str) -> bool:
    sys.path.insert(0, str(OPS))
    import yt_auth  # noqa: E402
    import urllib.request  # noqa: E402
    import urllib.error  # noqa: E402
    tok = yt_auth.access_token(ch)
    body = json.dumps({
        "snippet": {"playlistId": playlist_id,
                    "resourceId": {"kind": "youtube#video", "videoId": video_id}},
    }).encode("utf-8")
    req = urllib.request.Request(
        "https://www.googleapis.com/youtube/v3/playlistItems?part=snippet",
        data=body, method="POST",
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req) as r:
            r.read()
        return True
    except urllib.error.HTTPError as e:
        print(f"playlist insert failed: HTTP {e.code} {e.read()[:200]}", file=sys.stderr)
        return False


def plan(days: int) -> list[dict]:
    """Pair each built song with its karaoke into a dated release list."""
    state = load_state()
    done = {(r["slug"], r["kind"]) for r in state["released"]}
    items: list[dict] = []
    for slug in all_slugs():
        if not has_song(slug):
            continue
        # The main release first, then the sing-along version.
        if has_video(slug, "song"):
            items.append({"slug": slug, "kind": "song", "video": KARAOKE / f"song-{slug}.mp4"})
        if has_video(slug, "karaoke"):
            items.append({"slug": slug, "kind": "karaoke", "video": KARAOKE / f"karaoke-{slug}.mp4"})
    todo = [i for i in items if (i["slug"], i["kind"]) not in done]
    start = datetime.now(timezone.utc)
    for i, item in enumerate(todo):
        item["when"] = start + timedelta(days=i // UPLOADS_PER_DAY)
    return todo[: days * UPLOADS_PER_DAY] if days else todo


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--plan", action="store_true", help="show the schedule, send nothing")
    ap.add_argument("--days", type=int, default=0, help="limit the plan to N days")
    ap.add_argument("--next", action="store_true", help="release the first item in the plan")
    ap.add_argument("--ch", default="ch3")
    ap.add_argument("--public", action="store_true",
                    help="publish publicly; without it the upload stays private for K")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    todo = plan(args.days)
    if args.plan or not args.next:
        if not todo:
            print("nothing to release yet — no built songs found")
            print("(generation is window-gated; see scripts/watch.sh)")
            return 0
        print(f"{len(todo)} releases pending, {UPLOADS_PER_DAY}/day "
              f"(YouTube API quota: 10,000 units / 1,600 per upload):\n")
        for item in todo[:24]:
            kind = "KARAOKE" if item["kind"] == "karaoke" else "SONG   "
            print(f"  {item['when']:%Y-%m-%d}  {kind}  {item['slug']}")
        if len(todo) > 24:
            print(f"  ... and {len(todo) - 24} more")
        return 0

    item = todo[0]
    slug, kind = item["slug"], item["kind"]
    title, desc, tags = describe(slug, kind)
    video = item["video"]
    if not video or not video.exists():
        print(f"missing {kind} video for {slug}; render it with "
              f"make_karaoke.py {slug} --mix {kind}", file=sys.stderr)
        return 2

    desc_file = ROOT / "work" / f"release-{slug}-{kind}.txt"
    tags_file = ROOT / "work" / f"release-{slug}-{kind}.tags"
    desc_file.write_text(desc, encoding="utf-8")
    tags_file.write_text(",".join(tags), encoding="utf-8")
    # A 16:9 thumbnail, not the square cover: YouTube renders at 16:9 and would
    # pillarbox the cover.
    thumb = ROOT / "library" / "thumbs" / f"thumb-{kind}-{slug}.png"
    if not thumb.exists():
        thumb = COVERS / f"cover-{slug}.jpg"

    cmd = [sys.executable, str(OPS / "yt_publish.py"), "--ch", args.ch,
           "--video", str(video), "--title", title,
           "--desc-file", str(desc_file), "--tags-file", str(tags_file),
           "--category", "10", "--privacy", "public" if args.public else "private"]
    if thumb.exists():
        cmd += ["--thumb", str(thumb)]
    print(" ".join(cmd))
    if args.dry_run:
        return 0

    import subprocess
    proc = subprocess.run(cmd, text=True, capture_output=True)
    sys.stdout.write(proc.stdout)
    sys.stderr.write(proc.stderr)
    if proc.returncode != 0:
        return proc.returncode
    m = re.search(r"video id (\S+)", proc.stdout)
    vid = m.group(1) if m else None
    state = load_state()
    # A new release belongs in the right playlist, or the channel looks like a
    # pile of loose videos rather than a catalogue. Created lazily on first use.
    if vid:
        pid = ensure_playlist(state, kind, args.ch)
        if pid:
            add_to_playlist(pid, vid, args.ch)
    state["released"].append({
        "slug": slug, "kind": kind, "video_id": vid,
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "public": bool(args.public),
    })
    save_state(state)
    print(f"recorded in {STATE.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
