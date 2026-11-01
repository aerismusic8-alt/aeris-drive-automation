#!/usr/bin/env python3
"""Fill ch3's playlists from the videos already on the channel.

Why this is worth doing. A playlist is free (no upload quota, no render) and it
does three things a lone video cannot: it keeps a viewer on the channel (YouTube
autoplays the next item), it gives each group its own searchable page, and it
makes the channel read as a body of work rather than a scatter of uploads. The
dossier already names the playlists; this just makes the channel match it.

Idempotent: it reads what is already in each playlist and adds only the missing
videos, so it is safe to re-run after every release.

    python3 scripts/fill_playlists.py --plan     # what would change
    python3 scripts/fill_playlists.py --apply    # do it
"""
from __future__ import annotations

import argparse
import json
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
OPS = ROOT.parent / "ops"
STATE = ROOT / "work" / "playlist-state.json"

# Each bucket: (key, title, description, title-test). Order matters — a karaoke
# title also contains the song name, so karaoke is tested before song.
BUCKETS = [
    ("karaoke", "คาราโอเกะ — ร้องตามได้ทุกเพลง",
     "รวมทุกเพลงเป็นเวอร์ชันคาราโอเกะ ไม่มีเสียงร้อง ร้องตามได้เลย\n\n"
     "AERIS Music · เพลงไทยที่ตั้งใจทำ",
     lambda t: "คาราโอเกะ" in t),
    ("short", "ท่อนฮุก — เพลงไทยสั้น ๆ",
     "รวมท่อนฮุกของทุกเพลง ฟังสั้น ๆ ได้ใจความ\n\nAERIS Music · เพลงไทยที่ตั้งใจทำ",
     lambda t: "#Shorts" in t or "ท่อนที่" in t),
    ("compilation", "รวมเพลงยาว — ฟังเพลินเป็นชั่วโมง",
     "คอมไพล์เพลงไทยเพื่อชีวิตแบบยาว เลือกเพลงฟังได้ มีบทนำทุกเพลง\n\n"
     "AERIS Music · เพลงไทยที่ตั้งใจทำ",
     lambda t: "รวมเพลง" in t),
    ("song", "เพลงไทยเพื่อชีวิต — รวมทุกเพลง",
     "รวมทุกเพลงไทยเพื่อชีวิตของ AERIS Music ร้องด้วยเสียงจริง เนื้อร้องและทำนองใหม่\n\n"
     "AERIS Music · ฟังเพลิน ฟังได้ทุกวัน",
     lambda t: True),
]
ARTIST = ("naviya", "NAVIYA", "เพลงทั้งหมดของ NAVIYA ศิลปินคนแรกของ AERIS Music\n\n"
          "AERIS Music · สร้างศิลปินทีละคน")

# Mood playlists. A song belongs to its mood *and* to the all-songs playlist, so
# these are additive rather than one-bucket-per-video (see `moods()`). The three
# are the ones GROWTH.md names; the mood of each song comes from the `# MOOD:`
# header in its lyric file, keyed by the lyric's title.
MOODS = [
    ("mood-sad", "เพลงเศร้า — อกหัก คิดถึง คร่ำครวญ",
     "รวมเพลงเศร้าของ AERIS Music อกหัก คิดถึง คนที่จากไป\n\n"
     "AERIS Music · เพลงไทยที่ตั้งใจทำ", {"sad"}),
    ("mood-warm", "เพลงอบอุ่น — ฟังแล้วใจนุ่ม",
     "รวมเพลงอบอุ่นของ AERIS Music รัก ครอบครัว บ้าน\n\n"
     "AERIS Music · เพลงไทยที่ตั้งใจทำ", {"warm", "calm"}),
    ("mood-hopeful", "เพลงให้กำลังใจ — สู้ต่อไป",
     "รวมเพลงให้กำลังใจของ AERIS Music กำลังใจ ความฝัน วันใหม่\n\n"
     "AERIS Music · เพลงไทยที่ตั้งใจทำ", {"hopeful", "epic"}),
]


def song_moods() -> dict[str, str]:
    """title -> mood, read from the `# MOOD:` header of each lyric file.

    The playlist API only sees a video title, and the mood lives with the song,
    so the two are joined on the lyric's `# TITLE:`. A song whose lyric is
    missing is simply not in a mood playlist, which is the safe default.
    """
    out: dict[str, str] = {}
    for f in sorted((ROOT / "lyrics").glob("*.txt")):
        title = mood = None
        for line in f.read_text(encoding="utf-8").splitlines()[:10]:
            if line.startswith("# TITLE:"):
                title = line.split(":", 1)[1].strip()
            elif line.startswith("# MOOD:"):
                mood = line.split(":", 1)[1].strip()
        if title and mood:
            out[title] = mood
    return out


def moods(title: str, by_title: dict[str, str]) -> list[str]:
    """The mood buckets a video belongs to (may be empty, may be several).

    A full-song video's title is the lyric title plus a suffix (a mood tag, or
    nothing), so the join is by containment. Only the full song joins a mood
    playlist: its Shorts and karaoke are separate buckets, and a 40-second hook
    is not what "เพลงเศร้า" promises.
    """
    song = next((t for t in by_title if t in title), None)
    if not song:
        return []
    return [key for key, _t, _d, want in MOODS if by_title[song] in want]


def _api(method: str, path: str, tok: str, body: dict | None = None):
    req = urllib.request.Request(
        "https://www.googleapis.com/youtube/v3/" + path,
        data=json.dumps(body).encode() if body else None, method=method,
        headers={"Authorization": f"Bearer {tok}", "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=60) as r:
        return json.loads(r.read() or b"{}")


def _tok(ch: str) -> str:
    sys.path.insert(0, str(OPS))
    import yt_auth  # noqa: E402
    return yt_auth.access_token(ch)


def classify(title: str) -> str:
    """Which bucket a video belongs to. First match wins (see BUCKETS order)."""
    if "NAVIYA" in title.upper():
        return "naviya"
    for key, _t, _d, test in BUCKETS:
        if test(title):
            return key
    return "song"


def channel_videos(ch: str) -> list[dict]:
    tok = _tok(ch)
    up = _api("GET", f"channels?part=contentDetails&mine=true", tok)
    pid = up["items"][0]["contentDetails"]["relatedPlaylists"]["uploads"]
    out, page = [], None
    while True:
        p = f"playlistItems?part=snippet,contentDetails&maxResults=50&playlistId={pid}"
        if page:
            p += f"&pageToken={page}"
        d = _api("GET", p, tok)
        for it in d["items"]:
            out.append({"id": it["contentDetails"]["videoId"],
                        "title": it["snippet"]["title"]})
        page = d.get("nextPageToken")
        if not page:
            break
    return out


def playlist_items(pid: str, tok: str) -> set[str]:
    got, page = set(), None
    while True:
        p = f"playlistItems?part=contentDetails&maxResults=50&playlistId={pid}"
        if page:
            p += f"&pageToken={page}"
        d = _api("GET", p, tok)
        for it in d["items"]:
            got.add(it["contentDetails"]["videoId"])
        page = d.get("nextPageToken")
        if not page:
            break
    return got


def ensure_playlist(state: dict, key: str, title: str, desc: str, ch: str) -> str:
    if state.get(key):
        return state[key]
    pid = _api("POST", "playlists?part=snippet,status", _tok(ch), {
        "snippet": {"title": title[:150], "description": desc[:5000],
                    "defaultLanguage": "th"},
        "status": {"privacyStatus": "public"}})["id"]
    state[key] = pid
    print(f"created playlist {pid}: {title}")
    return pid


def add(pid: str, vid: str, tok: str) -> bool:
    try:
        _api("POST", "playlistItems?part=snippet", tok, {
            "snippet": {"playlistId": pid,
                        "resourceId": {"kind": "youtube#video", "videoId": vid}}})
        return True
    except urllib.error.HTTPError as e:
        print(f"  add {vid} failed: HTTP {e.code} {e.read()[:120]}", file=sys.stderr)
        return False


def run(apply: bool, ch: str = "ch3") -> int:
    state = json.loads(STATE.read_text()) if STATE.exists() else {}
    vids = channel_videos(ch)
    tok = _tok(ch)
    groups: dict[str, list[dict]] = {}
    for v in vids:
        groups.setdefault(classify(v["title"]), []).append(v)

    titles = {k: (t, d) for k, t, d, _f in BUCKETS}
    titles["naviya"] = (ARTIST[1], ARTIST[2])
    titles.update({k: (t, d) for k, t, d, _w in MOODS})

    # Mood playlists are additive: a full song joins its mood playlist *and* the
    # all-songs one. Only the "song" bucket joins — a karaoke or a Short is a
    # different promise than "เพลงเศร้า".
    by_title = song_moods()
    for v in groups.get("song", []):
        for key in moods(v["title"], by_title):
            groups.setdefault(key, []).append(v)

    changes = 0
    for key, items in sorted(groups.items()):
        title, desc = titles[key]
        pid = state.get(key)
        have = playlist_items(pid, tok) if pid else set()
        todo = [v for v in items if v["id"] not in have]
        print(f"{key:12} {len(items):2} videos, {len(have):2} in playlist, "
              f"{len(todo):2} to add")
        if not apply or not todo:
            changes += len(todo)
            continue
        pid = ensure_playlist(state, key, title, desc, ch)
        for v in todo:
            if add(pid, v["id"], tok):
                changes += 1
    if apply:
        STATE.write_text(json.dumps(state, indent=2, ensure_ascii=False))
    print(f"{'applied' if apply else 'would add'} {changes} playlist item(s)")
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--plan", action="store_true", help="report only (default)")
    ap.add_argument("--apply", action="store_true", help="write the changes")
    ap.add_argument("--ch", default="ch3")
    a = ap.parse_args()
    return run(a.apply, a.ch)


if __name__ == "__main__":
    sys.exit(main())
