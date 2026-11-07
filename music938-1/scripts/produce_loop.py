#!/usr/bin/env python3
"""Produce new songs continuously as raw material for other AIs to make clips.

K (2026-11-07): "งานเพลงต้องสร้างต่อเนื่องไว้เป็นวัตถุดิบให้ ai เอาไปสร้างคลิปด้วย
แล้วล่ะ" — keep producing songs as material for other AIs to build clips from.

The bottleneck is not taste, it is the login. Flow Music renders a real vocal but
has no API, burns ~2-3 free credits a day, and its browser session dies. So this
job runs in two lanes:

  * **keyless lane (the one that never stops).** Duck.ai drafts the lyric (no
    login), `flow_song.py --offline` synthesises the master with ffmpeg, and the
    cover is drawn with PIL. No credential, no quota — it can run every hour, all
    night, on a pod with nothing configured. These are instrumentals/synth
    masters, which is exactly what a clip wants as a bed.
  * **quality lane (opportunistic).** When the Flow Music session is alive, a
    song from the front of the queue is upgraded to a real vocal render. It is
    never *required*: if Flow is down, the keyless master already exists.

One run produces at most `--count` songs (default 1, so an hourly cron cannot
flood), appends them to the share pack, and — with `--push` — uploads the media
to the public `media-938` release and commits the refreshed catalog, so any AI
can fetch the new songs without a login.

    python3 scripts/produce_loop.py --count 1              # one keyless song
    python3 scripts/produce_loop.py --count 3 --push       # + publish to the release
    python3 scripts/produce_loop.py --flow                 # also try a Flow render
    python3 scripts/produce_loop.py --plan                 # what it would make next
"""
from __future__ import annotations

import argparse
import json
import os
import re
import subprocess
import sys
from pathlib import Path

# ffmpeg is not in the image; setup-pod.sh installs a static build under
# /workspace/ax-tools/bin (survives a recycle) but it is not on PATH by default.
_BIN = "/workspace/ax-tools/bin"
if Path(_BIN, "ffmpeg").exists() and _BIN not in os.environ.get("PATH", ""):
    os.environ["PATH"] = _BIN + os.pathsep + os.environ.get("PATH", "")

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent
sys.path.insert(0, str(ROOT / "scripts"))

import ai_lyrics as A  # noqa: E402
import genres as G  # noqa: E402

QUEUE = ROOT / "work" / "produce-queue.json"

# A theme pool, one row per (genre, angle, title seed). The advisor panel
# (2026-11-07) named this "theme-pool + seed rotator": a small curated list keeps
# the catalogue coherent, and the queue rotates through it instead of asking a
# model for a fresh idea each run (which drifts and duplicates).
THEMES = [
    ("lofi", "การทำงานดึกอย่างสงบ", "คืนที่ยังไม่หลับ", "calm", "khuen-thi-yang-mai-lap"),
    ("acoustic", "ความรักเรียบง่ายในบ้านเกิด", "บ้านหลังเล็กของเรา", "warm", "ban-lang-lek-khong-rao"),
    ("citypop", "ค่ำคืนในเมืองที่ไม่เคยหลับ", "ไฟนีออนกับใจที่ล้า", "mystic", "fai-nion-kap-chai-thi-la"),
    ("synthpop", "ความฝันวัยหนุ่มสาว", "แสงสีที่ยังตามหา", "hopeful", "saeng-si-thi-yang-tam-ha"),
    ("rnb", "ความคิดถึงที่ไม่กล้าบอก", "ข้อความที่ไม่ได้ส่ง", "sad", "kho-khwam-thi-mai-dai-song"),
    ("morlam", "กลับบ้านไปหาพ่อแม่", "กลับบ้านเถิดหล่า", "hopeful", "klap-ban-thoet-la"),
    ("rock", "สู้ต่อแม้ไม่มีใครเชื่อ", "ไฟที่ยังไม่ดับ", "epic", "fai-thi-yang-mai-dap"),
    ("pop", "รักในวันที่ธรรมดา", "วันธรรมดาที่พิเศษ", "warm", "wan-tham-mada-thi-phi-set"),
    ("indie", "เพื่อนเก่าที่ห่างกันไป", "เพลงที่เราเคยร้อง", "calm", "phleng-thi-rao-khoei-rong"),
    ("edm", "ปลุกใจก่อนออกไปสู้", "ลุกขึ้นแล้วไป", "epic", "luk-khuen-laeo-pai"),
    ("jazz", "ค่ำคืนในร้านเล็ก ๆ", "แก้วสุดท้ายของคืนนี้", "mystic", "kaeo-sut-thai-khong-khuen-ni"),
    ("country", "ชีวิตชนบทที่สงบ", "ทุ่งนากับแสงเช้า", "calm", "thung-na-kap-saeng-chao"),
]

MOOD_KEY = {"sad": "Am", "calm": "C", "warm": "G", "hopeful": "D",
            "mystic": "Em", "epic": "Am"}
MOOD_TEMPO = {"sad": "68", "calm": "72", "warm": "78", "hopeful": "96",
              "mystic": "84", "epic": "124"}


def existing_slugs() -> set[str]:
    return {f.stem for f in (ROOT / "lyrics").glob("*.txt")}


def next_number() -> int:
    nums = []
    for s in existing_slugs():
        m = re.match(r"(\d+)-", s)
        if m:
            nums.append(int(m.group(1)))
    return (max(nums) + 1) if nums else 1


def load_queue() -> dict:
    if QUEUE.exists():
        return json.loads(QUEUE.read_text(encoding="utf-8"))
    return {"made": 0, "log": []}


def save_queue(q: dict) -> None:
    QUEUE.parent.mkdir(parents=True, exist_ok=True)
    QUEUE.write_text(json.dumps(q, ensure_ascii=False, indent=2), encoding="utf-8")


def pick_theme(used: set[str]) -> tuple[str, str, str, str, str] | None:
    """The first theme not yet attempted. `used` is the titles already in the log."""
    for theme in THEMES:
        if theme[2] in used:
            continue
        return theme
    return None


def make_one(theme: tuple[str, str, str, str, str], *, flow: bool) -> dict:
    genre, angle, title, mood, slug_word = theme
    n = next_number()
    slug = f"{n:02d}-{slug_word or _slugify(title)}"
    meta = {"TITLE": title, "SUBTITLE": f"เพลงที่ {n} · {G.by_id().get(genre, {}).get('name_th', genre)}",
            "GENRE": genre, "MOOD": mood, "TEMPO": MOOD_TEMPO.get(mood, "80"),
            "KEY": MOOD_KEY.get(mood, "C"), "VOICE": "female"}

    print(f"[{slug}] {title} ({genre}/{mood}) — drafting lyric…", flush=True)
    # Duck.ai first (best Thai) but it needs the desktop's CDP port; pollinations
    # is plain HTTP so the loop still runs on a machine with no browser. The lint
    # decides either way.
    secs, problems = [], []
    for drafter in ("duck", "pollinations"):
        try:
            secs, problems = A.draft(meta, angle, drafter=drafter)
        except Exception as exc:  # noqa: BLE001
            problems = [f"{drafter}: {type(exc).__name__}: {exc}"]
            continue
        print(f"  {drafter}: sections={len(secs)} problems={problems[:2]}", flush=True)
        if secs and not problems:
            break
    if not secs or problems:
        print(f"  draft rejected: {problems[:3]}", flush=True)
        return {"slug": slug, "result": "no-draft", "problems": problems[:3]}
    (ROOT / "lyrics" / f"{slug}.txt").write_text(A.render_file(meta, secs), encoding="utf-8")
    print(f"  lyric written: lyrics/{slug}.txt ({sum(len(l) for _, l in secs)} lines)", flush=True)

    # Cover art is PIL, no login.
    subprocess.run([sys.executable, str(ROOT / "scripts" / "covers.py"),
                    "--only", slug], cwd=ROOT, capture_output=True, text=True)

    rec = {"slug": slug, "title": title, "genre": genre, "mood": mood,
           "result": "lyric", "flow": False}
    # Keyless master first, so the song exists even if Flow is down.
    r = subprocess.run([sys.executable, str(ROOT / "scripts" / "flow_song.py"),
                        slug, "--offline", "--force"],
                       cwd=ROOT, capture_output=True, text=True, timeout=900)
    rec["offline_rc"] = r.returncode
    print(f"  keyless master: rc={r.returncode} {(r.stdout or r.stderr or '').strip()[-120:]}", flush=True)

    if flow:
        r2 = subprocess.run([sys.executable, str(ROOT / "scripts" / "flow_song.py"),
                             slug, "--force"],
                            cwd=ROOT, capture_output=True, text=True, timeout=1500)
        rec["flow_rc"] = r2.returncode
        rec["flow"] = r2.returncode == 0
        print(f"  flow render: rc={r2.returncode} (kept the keyless master either way)", flush=True)

    # The synth master has no vocal, so it doubles as the instrumental bed a
    # clip with narration wants. A Flow render does have a vocal, so it must not
    # be filed as karaoke.
    song = ROOT / "library" / "songs" / f"song-{slug}.mp3"
    if song.exists() and not rec["flow"]:
        import shutil
        shutil.copyfile(song, ROOT / "library" / "songs" / f"karaoke-{slug}.mp3")
        rec["instrumental"] = True
    return rec


def _slugify(title: str) -> str:
    """A romanised, filename-safe slug. Thai has no ASCII, so fall back to a hash
    when there is nothing to transliterate; a stable slug is what a save and a
    playlist key off, so it must not change between runs."""
    ascii_words = re.findall(r"[a-z0-9]+", title.lower())
    if ascii_words:
        return "-".join(ascii_words)[:40]
    import hashlib
    return "thai-" + hashlib.sha1(title.encode("utf-8")).hexdigest()[:8]


def publish(pack_only: bool) -> int:
    """Refresh the share pack and (optionally) push the media to the release."""
    rc = subprocess.run([sys.executable, str(ROOT / "scripts" / "make_share_pack.py"),
                         "--no-songs", "--beds"], cwd=ROOT).returncode
    if pack_only:
        return rc
    pub = REPO / "music938-1" / "scripts" / "publish_media.py"
    r = subprocess.run([sys.executable, str(pub)], cwd=ROOT)
    return rc | r.returncode


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--count", type=int, default=1, help="songs to produce this run")
    ap.add_argument("--flow", action="store_true",
                    help="also attempt a Flow Music vocal render (needs the session)")
    ap.add_argument("--push", action="store_true",
                    help="publish the new media to the public media-938 release")
    ap.add_argument("--pack-only", action="store_true",
                    help="refresh the share pack but do not upload media")
    ap.add_argument("--plan", action="store_true", help="show the next themes, make nothing")
    args = ap.parse_args()

    q = load_queue()
    used = {r.get("title") for r in q["log"]}
    if args.plan:
        for i in range(args.count):
            t = pick_theme(used | {x[2] for x in THEMES[:i]})
            print("  next:", t)
        print(f"built so far: {len(existing_slugs())} lyrics, {q['made']} produced by this loop")
        return 0

    made = []
    for _ in range(max(1, args.count)):
        used = {r.get("title") for r in q["log"]}
        theme = pick_theme(used)
        if not theme:
            print("theme pool exhausted — extend THEMES in produce_loop.py")
            break
        rec = make_one(theme, flow=args.flow)
        q["log"].append(rec)
        if rec.get("result") == "lyric":
            q["made"] += 1
            made.append(rec)
        save_queue(q)

    if made and (args.push or args.pack_only):
        publish(args.pack_only)

    print(json.dumps({"produced": [m["slug"] for m in made],
                      "total_made": q["made"]}, ensure_ascii=False))
    return 0 if made or not made else 0


if __name__ == "__main__":
    raise SystemExit(main())
