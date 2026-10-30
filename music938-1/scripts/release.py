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


SHORTS = ROOT / "library" / "shorts"


def short_files(slug: str, mix: str = "song") -> list[Path]:
    """Every Short for a song, plain name first, then the -h1/-h2 hook cuts."""
    out = []
    plain = SHORTS / f"short-{mix}-{slug}.mp4"
    if plain.exists():
        out.append(plain)
    out += sorted(SHORTS.glob(f"short-{mix}-h*-{slug}.mp4"))
    return out


def has_short(slug: str, mix: str = "song") -> bool:
    return bool(short_files(slug, mix))


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


# The Data API quota resets at midnight Pacific, not midnight UTC. A day that
# starts at UTC midnight would overcount by 7 hours and refuse a legal upload.
QUOTA_TZ_OFFSET_HOURS = -7


def _quota_day(ts: datetime) -> str:
    return (ts.astimezone(timezone.utc)
            + timedelta(hours=QUOTA_TZ_OFFSET_HOURS)).strftime("%Y-%m-%d")


def uploads_today(state: dict) -> int:
    """Uploads already spent in the current Pacific quota day."""
    day = _quota_day(datetime.now(timezone.utc))
    used = 0
    for r in state.get("released", []):
        try:
            if _quota_day(datetime.fromisoformat(r["at"])) == day:
                used += 1
        except (KeyError, ValueError):
            continue
    return used


def describe(slug: str, kind: str, variant: str = "") -> tuple[str, str, list[str]]:
    """Return (title, description, tags) for one release.

    `variant` distinguishes the hook cuts of one song, so three Shorts from the
    same song are three different uploads rather than a duplicate.

    Title shape is set from the competitor scan (2026-10-30, `work/competitors.json`):
    of 1,546 videos, the ones past 100k views averaged 47.9 characters and used
    `|` in only 8% of titles, while the sub-1k videos averaged 60.7 characters and
    used `|` in 38.9%. YouTube truncates past ~60 characters, so the tail is what
    gets cut first. The old titles appended `| AERIS Music` to every single
    release, which is the losing shape; the brand is already the channel name, so
    it is dropped from the Shorts and karaoke titles and the words are spent on
    searchable Thai instead.
    """
    h = parse_lyrics(slug)
    title_th = h.get("TITLE", slug)
    mood = h.get("MOOD", "calm")
    tagline = TAGLINE.get(mood, TAGLINE["calm"])
    n = slug.split("-")[0]
    hook = ""
    m = re.search(r"-h(\d+)-", variant)
    if m:
        hook = f" (ท่อนที่ {m.group(1)})"

    if kind == "short":
        title = f"{title_th}{hook} #เพลงไทย #Shorts"
        desc = (
            f"🎵 {title_th} (ท่อนฮุก)\n\n"
            f"{tagline}\n\n"
            f"เพลงที่ {int(n)} จากชุด 20 เพลงไทย — ร้องด้วยเสียงจริง\n"
            f"🎧 ฟังเวอร์ชันเต็มได้ในช่อง\n\n"
            f"{HASHTAGS} #Shorts"
        )
    elif kind == "karaoke":
        title = f"{title_th} (คาราโอเกะ) ร้องตามได้"
        desc = (
            f"🎤 {title_th} — เวอร์ชันคาราโอเกะ (ไม่มีเสียงร้อง)\n\n"
            f"ร้องตามได้เลย! {tagline}\n\n"
            f"🎵 เพลงที่ {int(n)} จากชุด 20 เพลงไทย\n"
            f"🎧 ฟังเวอร์ชันเต็ม (มีเสียงร้อง) ได้ในช่อง\n"
            f"✨ สร้างจากความตั้งใจ ไม่ใช่ความเร็ว\n\n"
            f"{HASHTAGS}"
        )
    else:
        title = f"{title_th} — {tagline}"
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
    if kind == "short":
        return ("ท่อนฮุก — เพลงไทยสั้น ๆ",
                "รวมท่อนฮุกของทุกเพลงในชุด ฟังสั้น ๆ ได้ใจความ\n\n"
                "AERIS Music · เพลงไทยที่ตั้งใจทำ")
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


def plan(days: int, shorts: bool = False) -> list[dict]:
    """Pair each built song with its karaoke into a dated release list.

    Shorts are discovery, not catalogue: a zero-subscriber channel gets no
    long-form impressions (AERIS Music's own numbers: 382 of 449 lifetime views
    came from Shorts, ~33 from long-form). They are planned first, so the
    audience exists before the watch-hour videos need one.
    """
    state = load_state()
    done = {(r["slug"], r["kind"], r.get("variant", "")) for r in state["released"]}
    items: list[dict] = []
    for slug in all_slugs():
        if not has_song(slug):
            continue
        for v in short_files(slug, "song"):
            items.append({"slug": slug, "kind": "short", "video": v,
                          "variant": v.stem})
        if shorts:
            continue
        # The main release first, then the sing-along version.
        if has_video(slug, "song"):
            items.append({"slug": slug, "kind": "song",
                          "video": KARAOKE / f"song-{slug}.mp4", "variant": ""})
        if has_video(slug, "karaoke"):
            items.append({"slug": slug, "kind": "karaoke",
                          "video": KARAOKE / f"karaoke-{slug}.mp4", "variant": ""})
    todo = [i for i in items if (i["slug"], i["kind"], i.get("variant", "")) not in done]
    start = datetime.now(timezone.utc)
    for i, item in enumerate(todo):
        item["when"] = start + timedelta(days=i // UPLOADS_PER_DAY)
    return todo[: days * UPLOADS_PER_DAY] if days else todo


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--plan", action="store_true", help="show the schedule, send nothing")
    ap.add_argument("--days", type=int, default=0, help="limit the plan to N days")
    ap.add_argument("--next", action="store_true", help="release the first item in the plan")
    ap.add_argument("--shorts", action="store_true",
                    help="plan Shorts only (the discovery-first queue)")
    ap.add_argument("--ch", default="ch3")
    ap.add_argument("--public", action="store_true",
                    help="publish publicly; without it the upload stays private for K")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args()

    todo = plan(args.days, shorts=args.shorts)
    if args.plan or not args.next:
        if not todo:
            print("nothing to release yet — no built songs found")
            print("(generation is window-gated; see scripts/watch.sh)")
            return 0
        print(f"{len(todo)} releases pending, {UPLOADS_PER_DAY}/day "
              f"(YouTube API quota: 10,000 units / 1,600 per upload):\n")
        for item in todo[:24]:
            kind = {"karaoke": "KARAOKE", "short": "SHORT  "}.get(item["kind"], "SONG   ")
            print(f"  {item['when']:%Y-%m-%d}  {kind}  {item['slug']}")
        if len(todo) > 24:
            print(f"  ... and {len(todo) - 24} more")
        return 0

    item = todo[0]
    slug, kind = item["slug"], item["kind"]
    state = load_state()
    used = uploads_today(state)
    if used >= UPLOADS_PER_DAY:
        print(f"today's quota is spent: {used}/{UPLOADS_PER_DAY} uploads already "
              f"made this Pacific day. A videos.insert costs 1,600 of the 10,000 "
              f"daily units, so the next one would 403. Try after 07:00 UTC.",
              file=sys.stderr)
        return 3
    title, desc, tags = describe(slug, kind, item.get("variant", ""))
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
    # pillarbox the cover. A Short's own frame is 9:16 and is used as-is, since
    # Shorts thumbnails are vertical.
    thumb = ROOT / "library" / "thumbs" / f"thumb-{kind}-{slug}.png"
    if item.get("variant"):
        vt = ROOT / "library" / "thumbs" / f"thumb-{item['variant']}.png"
        if vt.exists():
            thumb = vt
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
        "slug": slug, "kind": kind, "variant": item.get("variant", ""),
        "video_id": vid,
        "at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
        "public": bool(args.public),
    })
    save_state(state)
    print(f"recorded in {STATE.relative_to(ROOT)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
