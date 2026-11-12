#!/usr/bin/env python3
"""Build a self-contained share pack another AI can use as background music.

K (2026-11-07): "แชร์งานให้ ai อื่นเอาไปใช้ได้ไหม จะเอาไปทำดนตรีประกอบคลิป" —
can the finished music be shared so another AI can use it as a soundtrack?

The blocker is not the audio, it is that a bare folder of .mp3 files tells another
agent nothing: it cannot tell a 52 BPM funeral ballad from an 84 BPM battle theme,
so it picks at random and the cut feels wrong. This script turns the library into
a pack an agent can actually reason about — a machine-readable catalog keyed by
mood/tempo/tags, the audio beside it, a clear license, and a ready-to-paste prompt.

    python3 scripts/make_share_pack.py --beds        # catalog + audio + beds
    python3 scripts/make_share_pack.py --no-songs    # catalog + beds only

Output lands in `share/aeris-music/` at the repo root. It is gitignored (the audio
is large) but the repo itself is public, so an agent that can read the repo can
also read the catalog. Run `--push` to commit the small files (catalog, license,
prompt, beds) and leave the songs local.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
from pathlib import Path

# ffmpeg/ffprobe are not in the image; setup-pod.sh installs a static build under
# /workspace/ax-tools/bin, which is not on PATH by default.
_BIN = "/workspace/ax-tools/bin"
if Path(_BIN, "ffmpeg").exists() and _BIN not in os.environ.get("PATH", ""):
    os.environ["PATH"] = _BIN + os.pathsep + os.environ.get("PATH", "")

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent
SONGS = ROOT / "library" / "songs"
LYRICS = ROOT / "lyrics"
COVERS = ROOT / "library" / "covers"
OUT = REPO / "share" / "aeris-music"
MAKE_MUSIC = REPO / "aeris938-1" / "scripts" / "make_music.py"

# Thai search words per mood, so a Thai-speaking agent can ask in Thai.
MOOD_TH = {
    "sad": "เศร้า โศก เสียใจ จากลา อกหัก",
    "calm": "สงบ ผ่อนคลาย เบา ๆ กล่อม",
    "warm": "อบอุ่น ครอบครัว บ้าน หมู่บ้าน",
    "hopeful": "มีความหวัง สว่าง กำลังใจ เดินทาง",
    "mystic": "ลึกลับ ขลัง ความจำ เงียบขรึม",
    "epic": "ยิ่งใหญ่ สงคราม ฮีโร่ ตื่นเต้น",
    "mellow": "นุ่มนวล ช้า ๆ คิดถึง",
}

LICENSE = """AERIS Music — free soundtrack pack
====================================

License: CC0 1.0 (public domain dedication) for the music and karaoke tracks.
Credit: "AERIS Music (youtube.com/@aerismusicth)" — appreciated, not required.
Commercial use: yes. Remix / loop / trim / re-record: yes.
Restriction: do not re-upload the songs as-is to a music streaming service
(Spotify, Apple Music, YouTube Music) claiming them as your own catalog. Every
other use, including as background music in your own videos, is free.
"""


def lyric_meta(slug: str) -> dict:
    path = LYRICS / f"{slug}.txt"
    meta: dict[str, str] = {}
    if not path.exists():
        return meta
    for line in path.read_text(encoding="utf-8").splitlines():
        m = re.match(r"#\s*([A-Z]+)\s*:\s*(.+)", line)
        if m:
            meta[m.group(1).lower()] = m.group(2).strip()
    return meta


def probe(path: Path) -> float:
    out = subprocess.run(
        ["ffprobe", "-v", "error", "-show_entries", "format=duration",
         "-of", "default=nw=1:nk=1", str(path)],
        capture_output=True, text=True).stdout.strip()
    try:
        return round(float(out), 1)
    except ValueError:
        return 0.0


# The durable, public store for the audio itself. A fresh pod has an empty
# `library/`, so the GitHub Release is the only place the songs exist outside the
# build host — and it needs no login, which is what makes it shareable to another
# AI. `publish_media.py` uploads here; the catalog links here.
RELEASE = "media-938"
RELEASE_URL = ("https://github.com/aerismusic8-alt/aeris-drive-automation/"
               "releases/download/media-938")


def _public(name: str) -> str:
    return f"{RELEASE_URL}/{name}"


def release_song_names(tok: str = "") -> list[str]:
    """The song mp3 names that exist in the public release.

    The catalog must list every song, but a CI runner that just produced one song
    has only that one on disk. Building from the disk alone would then commit a
    catalog of one and hide the other 21. The release is the durable store, so it
    is the union's second half. Returns [] on any failure — a local, offline run
    still works off the disk.
    """
    import urllib.request
    url = f"https://api.github.com/repos/aerismusic8-alt/aeris-drive-automation/releases/tags/{RELEASE}"
    req = urllib.request.Request(url, headers={"Accept": "application/vnd.github+json"})
    if tok:
        req.add_header("Authorization", f"token {tok}")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            data = json.loads(r.read())
    except Exception:  # noqa: BLE001
        return []
    return sorted(a["name"] for a in data.get("assets", [])
                  if re.match(r"song-.*\.mp3$", a["name"]))


def _audio_provenance(slug: str) -> dict:
    """Did a real singer render this, or is it the ffmpeg synth bed?

    The discriminator is the one `provenance.py` already trusts: the synth bed is
    one mono signal copied into both channels, so its two channels are
    bit-identical over a stretch of audio. A real stereo mix never is. Presence of
    a `clipmeta` file would be easier but wrong — the older Flow renders have no
    clipmeta and are still real songs. Without this the catalogue called a bed a
    song and a consumer could not tell them apart; K heard the difference first
    (2026-11-07).
    """
    path = SONGS / f"song-{slug}.mp3"
    if not path.exists():
        return {"audio": "unknown", "has_vocals": None}
    try:
        import provenance  # noqa: PLC0415
        mono = bool(provenance.signature(path).get("mono_duplicated"))
    except Exception:  # noqa: BLE001 - a missing ffmpeg must not break the pack
        mono = None
    if mono is None:
        return {"audio": "unknown", "has_vocals": None}
    return {"audio": "synth-bed" if mono else "flow", "has_vocals": not mono}


def catalogue(extra_songs: list[str] | None = None) -> list[dict]:
    manifest = {}
    mpath = SONGS / "manifest.json"
    if mpath.exists():
        manifest = {e["id"]: e for e in json.loads(mpath.read_text(encoding="utf-8"))["entries"]}
    names = {f.name for f in SONGS.glob("song-*.mp3")}
    names |= set(extra_songs or [])
    rows = []
    for name in sorted(names):
        slug = name[len("song-"):-len(".mp3")]
        lid = f"song-{slug}"
        ent = manifest.get(lid, {})
        lm = lyric_meta(slug)
        mood = (ent.get("mood") or lm.get("mood") or "").lower() or "unspecified"
        tempo = lm.get("tempo") or ""
        local = SONGS / name
        row = {
            "id": lid,
            "title": ent.get("title") or lm.get("title") or slug,
            "mood": mood,
            "mood_th": MOOD_TH.get(mood, ""),
            "genre": lm.get("genre") or "pop",
            "key": ent.get("key") or lm.get("key") or "",
            "tempo_bpm": int(tempo) if str(tempo).isdigit() else None,
            "voice": ent.get("voice") or lm.get("voice") or "",
            "duration_seconds": ent.get("duration_seconds") or (probe(local) if local.exists() else None),
            # `file` is the local path inside the pack; `url` is the public one an
            # agent that never sees this disk can fetch.
            "file": f"music/{name}",
            "url": _public(name),
            "instrumental": f"music/karaoke-{slug}.mp3",
            "instrumental_url": _public(f"karaoke-{slug}.mp3"),
            "has_instrumental": (SONGS / f"karaoke-{slug}.mp3").exists(),
            "lyrics": f"../music938-1/lyrics/{slug}.txt",
        }
        row.update(_audio_provenance(slug))
        cover = COVERS / f"cover-{slug[3:]}.jpg"
        if cover.exists():
            row["cover"] = f"covers/{cover.name}"
            row["cover_url"] = _public(cover.name)
        rows.append(row)
    return rows


def build_beds(duration: float) -> list[dict]:
    beds = []
    for mood in ("calm", "warm", "sad", "hopeful", "mystic", "epic"):
        key = f"share-bed-{mood}"
        r = subprocess.run(
            [sys.executable, str(MAKE_MUSIC), key, mood,
             "--duration", str(duration), "--json"],
            capture_output=True, text=True)
        if r.returncode != 0:
            print(f"  bed {mood}: FAILED {r.stderr.strip()[-200:]}")
            continue
        src = Path(json.loads(r.stdout)["entry"]["file"])
        if not src.is_absolute():
            src = REPO / "aeris938-1" / src
        dst = OUT / "beds" / f"{mood}.mp3"
        dst.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(src, dst)
        beds.append({
            "id": f"bed-{mood}", "mood": mood, "mood_th": MOOD_TH.get(mood, ""),
            "file": f"beds/{mood}.mp3", "duration_seconds": duration,
            "note": "instrumental bed, no vocals — loop or trim to length",
        })
        print(f"  bed {mood}: {dst.name} ({dst.stat().st_size // 1024} KB)")
    return beds


PROMPT_TH = """คุณคือผู้ช่วยทำคลิปวิดีโอ ฉันมีชุดเพลงให้ใช้เป็นดนตรีประกอบฟรี
ดัชนีเพลง (อ่านอันนี้ก่อน): https://raw.githubusercontent.com/aerismusic8-alt/aeris-drive-automation/main/share/aeris-music/catalog.json
ลิงก์โหลดตรงทุกเพลงอยู่ในฟิลด์ url / instrumental_url ของแต่ละรายการ (โหลดได้เลย ไม่ต้องล็อกอิน)
บรรเลงล้วน (สำหรับคลิปที่มีเสียงพูด) โหลดได้ที่ (แทน <mood> ด้วย calm/warm/sad/hopeful/mystic/epic):
  https://raw.githubusercontent.com/aerismusic8-alt/aeris-drive-automation/main/share/aeris-music/beds/<mood>.mp3

อ่าน catalog.json ก่อน แล้วเลือกเพลงตามอารมณ์ของคลิป โดยดู 2 ค่า:
- mood / mood_th  = อารมณ์ (sad=เศร้า, calm=สงบ, warm=อบอุ่น, hopeful=มีหวัง, mystic=ลึกลับ, epic=ยิ่งใหญ่)
- tempo_bpm       = จังหวะ (ต่ำกว่า 70 = ช้า/เศร้า, 70-100 = กลาง, 100+ = เร็ว/ตื่นเต้น)

ทุกเพลงใน songs/ เป็นเพลงร้องจริง (audio="flow", มีร้อง) ตรวจสอบได้จากฟิลด์:
- audio = "flow" (เพลงร้องจริง) หรือ "synth-bed" (ดนตรีบรรเลงล้วน)
- has_vocals = true/false — ถ้า true ใช้เป็นเพลงเปิด มีเสียงร้อง, ถ้า false ใช้เป็นดนตรีประกอบที่มีคนพูดทับ
ถ้าคลิปมีเสียงบรรยาย ต้องใช้เฉพาะรายการ has_vocals=false หรือไฟล์ใน beds/ เท่านั้น อย่าเอาเพลงร้องไปทับเสียงพูด

กติกาการใช้:
1. ใช้ได้ฟรีทั้งหมด (CC0) รวมงานขาย ใส่เครดิต "AERIS Music (youtube.com/@aerismusicth)" ไม่บังคับแต่ขอบคุณ
2. ห้ามเอาเพลงไปอัปซ้ำเป็นเพลงของตัวเองบน Spotify/Apple Music/YouTube Music เท่านั้น
3. ถ้าคลิปต้องมีเสียงคนพูด ให้ใช้ไฟล์ใน beds/ (บรรเลงล้วน ไม่มีร้อง) หรือใช้ instrumental ของเพลง
4. เพลงยาว ~3-4 นาที ทำเป็นลูปได้ ให้ตัด fade เข้า-ออก 2-3 วินาที

งานที่ให้ทำ:
- เสนอ 3 เพลงที่เข้ากับอารมณ์คลิปของฉัน พร้อมเหตุผลสั้น ๆ (อ้าง mood + bpm)
- บอกชื่อไฟล์ที่ต้องโหลดจากแต่ละเพลง
- ถ้าฉันบอกความยาวคลิป บอกจุดตัด/จุดลูปที่แนะนำ

รอฉันบอกว่าเป็นคลิปแนวไหนก่อน แล้วค่อยเลือก
"""


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--songs", dest="songs", action="store_true", default=True)
    ap.add_argument("--no-songs", dest="songs", action="store_false",
                    help="catalog only; do not copy the ~440 MB of song audio")
    ap.add_argument("--beds", action="store_true",
                    help="also synthesise 6 instrumental beds (one per mood)")
    ap.add_argument("--bed-duration", type=float, default=120.0)
    ap.add_argument("--push", action="store_true",
                    help="git add/commit the small pack files (not the audio)")
    args = ap.parse_args()

    OUT.mkdir(parents=True, exist_ok=True)
    rows = catalogue(extra_songs=release_song_names(os.environ.get("AX_GH_TOKEN", "")))
    beds = build_beds(args.bed_duration) if args.beds else []
    print(f"catalogue: {len(rows)} songs, {len(beds)} beds")

    if args.songs:
        (OUT / "music").mkdir(exist_ok=True)
        for r in rows:
            src = SONGS / Path(r["file"]).name
            if not src.exists():  # on the release but not on this disk (CI run)
                continue
            shutil.copy2(src, OUT / r["file"])
            if r["has_instrumental"]:
                shutil.copy2(SONGS / Path(r["instrumental"]).name, OUT / r["instrumental"])
        if COVERS.exists():
            (OUT / "covers").mkdir(exist_ok=True)
            for c in sorted(COVERS.glob("cover-*.jpg")):
                shutil.copy2(c, OUT / "covers" / c.name)

    (OUT / "catalog.json").write_text(
        json.dumps({"pack": "AERIS Music", "license": "CC0-1.0",
                    "credit": "AERIS Music (youtube.com/@aerismusicth)",
                    "songs": rows, "beds": beds},
                   ensure_ascii=False, indent=2), encoding="utf-8")
    csv = ["id,title,mood,audio,has_vocals,tempo_bpm,key,duration_seconds,url,instrumental_url"]
    for r in rows:
        csv.append(",".join(str(r.get(k, "")) for k in
                            ("id", "title", "mood", "audio", "has_vocals",
                             "tempo_bpm", "key", "duration_seconds", "url",
                             "instrumental_url")))
    (OUT / "catalog.csv").write_text("\n".join(csv) + "\n", encoding="utf-8")
    (OUT / "LICENSE.txt").write_text(LICENSE, encoding="utf-8")
    (OUT / "PROMPT-TH.md").write_text(PROMPT_TH, encoding="utf-8")

    total = sum(f.stat().st_size for f in OUT.rglob("*") if f.is_file())
    print(f"wrote {OUT}  ({total // 1024 // 1024} MB)")
    print(f"prompt for another AI: {OUT / 'PROMPT-TH.md'}")

    if args.push:
        root = OUT.parent.parent
        r = subprocess.run(
            ["git", "add", "-f", "share/aeris-music/catalog.json",
             "share/aeris-music/catalog.csv", "share/aeris-music/LICENSE.txt",
             "share/aeris-music/PROMPT-TH.md", "share/aeris-music/beds",
             "share/aeris-music/covers"],
            cwd=str(root), capture_output=True, text=True)
        if r.returncode == 0:
            subprocess.run(["git", "commit", "-m",
                            "share: AERIS Music pack (catalog + license + prompt + beds)"],
                           cwd=str(root))
        else:
            print("git add failed:", r.stderr.strip()[-200:])
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
