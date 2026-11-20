#!/usr/bin/env python3
"""The clip lane: a finished 9:16 Short built from bank stills and a real song.

K (2026-11-19): "ถ้าแยกระบบ สร้างภาพกับทำคลิปได้แยกงานทำคู่ขนานเลย" — split the
system so making pictures and making clips run as two parallel jobs, and
"มีวัตถุดิบแล้วก็ทำคลิปต่อเลย".

Why a separate lane rather than a flag on `make_short`. The two jobs have
opposite bottlenecks and must not wait for each other:

  * the art lane is network-bound (a Commons sweep, or a Dreamina queue) and
    wants to run for an hour;
  * the clip lane is CPU-bound (ffmpeg + PIL) and finishes in a couple of
    minutes once the stills exist.

Running them as one job meant a slow sweep starved the renderer and a long
render blocked the sweep. Now each has its own workflow and its own cadence, and
the only thing they share is the manifest — which is committed, so the clip lane
never waits on a download to start.

The clip is deliberately not `make_short`. That path is a *karaoke* Short: it
needs lyric timing, ASS captions and a chorus span, and it falls back to a
letterbox over one cover when it has nothing better. This lane is the simpler,
more robust thing K actually asked for: real footage stills from the bank, cut
every few seconds, a Thai title card, the follow ask at the end, and the song
underneath. It renders even when the lyrics are unknown, which is the common
case for a bed.

    python3 ops/clip_lane.py --song music-d-44-party-khuen-ni-mai-yut-v44 \
        --query "bangkok night" --seconds 58

Every clip goes through `ops/clip_standard.py`, so a below-floor render is
deleted rather than shipped — the same gate every other lane obeys.
"""
from __future__ import annotations

import argparse
import json
import os
import random
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ops"))
sys.path.insert(0, str(ROOT / "music938-1" / "scripts"))

# Clips built from the bank live in their own namespace. `library/shorts` is the
# posting queue, and `crosspost._slug_of` derives a lyrics slug from every
# `short-*.mp4` name there -- a bank clip has no lyric timing, so putting it in
# that directory would make the queue look for lyrics that do not exist.
MANIFEST = ROOT / "music938-1" / "library" / "stock" / "manifest.json"
BANK_IMG = ROOT / "music938-1" / "library" / "stock" / "img"
MUSIC = ROOT / "aeris938-1" / "library" / "music"
OUT = ROOT / "music938-1" / "library" / "bank"
FONT = ROOT / "music938-1" / "fonts" / "NotoSansThai.ttf"

REPO = "aerismusic8-alt/aeris-drive-automation"
RELEASE_TAG = "media-938"
# The generated frames ride their own release: they are 164 MB of PNG, so they
# cannot be committed, and reusing media-938 would mean re-uploading every song
# master to add a picture.
SCENES_TAG = "scenes-938"
SCENES_IMG = ROOT / "music938-1" / "library" / "scenes"

W, H = 1080, 1920
FPS = 30

# A still that trips an advertiser filter costs the whole upload: YouTube and
# TikTok demote or age-gate a clip for a profanity neon sign in the background,
# and the channel's revenue gate is watch-hours, so a demoted clip is a lost
# month. Gemini flagged a "bangkok night" render for exactly this (SHOT 5, a bar
# strip sign, 2026-11-20). The bank is large enough that dropping these rows
# still fills a clip, so the match is a reject, not a warning.
ADULT_TITLE = re.compile(
    r"patpong|soi cowboy|nana plaza|go-?go|red.?light|nightlife|"
    r"bars? (and|&) clubs?|strip ?club|adult|sex|ping ?pong|massage parlou?r|"
    r"ladyboy|girly ?bar|beer ?bar", re.I)


def _branding():
    import branding  # noqa: PLC0415

    return branding


def _shard_urls() -> dict[str, str]:
    doc = json.loads(MANIFEST.read_text(encoding="utf-8"))
    return {s["name"]: s["url"] for s in doc.get("shards", []) if s.get("url")}


_SHARD_CACHE: dict[str, Path] = {}


def _shard_local(name: str, url: str, log=print) -> Path | None:
    """Download a shard once per run and reuse it for every still inside it.

    A clip wants ~8 stills and they cluster in a few shards, so fetching a 120 MB
    tar per still would be a gigabyte for one render. One fetch per shard, cached
    in the runner's temp dir, is the difference between a 2-minute render and a
    20-minute one.
    """
    import tempfile  # noqa: PLC0415
    import urllib.request  # noqa: PLC0415

    if name in _SHARD_CACHE:
        return _SHARD_CACHE[name]
    dest = Path(tempfile.gettempdir()) / f"ax-{name}"
    if not dest.exists():
        try:
            with urllib.request.urlopen(url, timeout=900) as resp, dest.open("wb") as f:
                shutil.copyfileobj(resp, f, 1 << 20)
        except Exception as exc:  # noqa: BLE001
            log(f"bank: shard {name} fetch failed ({type(exc).__name__})")
            dest.unlink(missing_ok=True)
            return None
    _SHARD_CACHE[name] = dest
    return dest


def _fetch_scenes(rows: list[dict], log=print) -> int:
    """Pull generated frames from the scenes release into `library/scenes/`.

    Same reason the photo bank is sharded: the pictures are 4-5 MB each and
    gitignored, so a runner starts with the manifest and no pixels. One tarball
    per genre keeps it to a single download instead of 42. Returns how many files
    it landed; 0 means the release does not carry them yet.
    """
    import tempfile  # noqa: PLC0415
    import tarfile  # noqa: PLC0415
    import urllib.error  # noqa: PLC0415
    import urllib.request  # noqa: PLC0415

    genres = sorted({(r.get("genre") or "") for r in rows} - {""})
    base = f"https://github.com/{REPO}/releases/download/{SCENES_TAG}"
    landed = 0
    for g in genres:
        url = f"{base}/scenes-{g}.tar"
        dest = Path(tempfile.gettempdir()) / f"ax-scenes-{g}.tar"
        try:
            if not dest.exists():
                with urllib.request.urlopen(url, timeout=600) as resp, \
                        dest.open("wb") as f:
                    shutil.copyfileobj(resp, f, 1 << 20)
            with tarfile.open(dest, mode="r") as tf:
                for m in tf.getmembers():
                    if not m.isfile():
                        continue
                    name = Path(m.name).name
                    if not name.lower().endswith((".png", ".jpg", ".jpeg", ".webp")):
                        continue
                    out = SCENES_IMG / g / name
                    out.parent.mkdir(parents=True, exist_ok=True)
                    with tf.extractfile(m) as src, out.open("wb") as dst:
                        shutil.copyfileobj(src, dst)
                    landed += 1
        except (urllib.error.HTTPError, urllib.error.URLError, OSError) as exc:
            log(f"ai: scenes-{g}.tar not fetched ({type(exc).__name__})")
            continue
    if landed:
        log(f"ai: fetched {landed} generated frame(s) from {SCENES_TAG}")
    return landed


def _materialise(row: dict, urls: dict[str, str], log=print) -> bool:
    """Extract one packed still out of its shard, on demand."""
    import tarfile  # noqa: PLC0415

    name = row.get("shard") or ""
    url = urls.get(name)
    if not url:
        return False
    shard = _shard_local(name, url, log=log)
    if not shard:
        return False

    want = row["file"]
    dest = BANK_IMG / Path(want).name
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        with tarfile.open(shard, mode="r") as tf:
            for m in tf.getmembers():
                if m.name == want:
                    tf.extract(m, ROOT / "music938-1" / "library" / "stock",
                               filter="data")
                    return dest.exists()
    except Exception as exc:  # noqa: BLE001
        log(f"bank: could not extract {want} ({type(exc).__name__})")
    return False


NEAR_DUP_BITS = 6   # a 64-bit dHash this close is the same scene to a viewer


def _dhash(path: Path, size: int = 8) -> int:
    """64-bit difference hash of the picture *as the clip will show it*.

    Hashing the whole file missed two stills that the render made identical: the
    clip cover-crops to 9:16, so two photos that differ only outside the crop
    look the same on screen. Gemini flagged the repeat; this measures the crop.
    """
    from PIL import Image  # noqa: PLC0415

    with Image.open(path) as im:
        im = im.convert("RGB")
        w, h = im.size
        want = W / H
        if w / h > want:
            nw = int(round(h * want))
            im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
        else:
            nh = int(round(w / want))
            im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
        g = im.convert("L").resize((size + 1, size), Image.LANCZOS)
    px = list(g.getdata())
    bits = 0
    for row in range(size):
        for col in range(size):
            i = row * (size + 1) + col
            bits = (bits << 1) | (px[i] > px[i + 1])
    return bits


def _hamming(a: int, b: int) -> int:
    return bin(a ^ b).count("1")


MIN_CROP_WIDTH = 1000   # below this the 9:16 crop is upscaled and goes soft


def _crop_width(path: Path) -> int:
    """Width of the 9:16 picture this file yields, in pixels."""
    from PIL import Image  # noqa: PLC0415

    with Image.open(path) as im:
        w, h = im.size
    return int(h * W / H) if w / h > W / H else w


def _sharpness(path: Path) -> float:
    """Variance of the Laplacian on the 9:16 crop: higher is crisper.

    Gemini named "เกรน/นอยส์ค่อนข้างเยอะในฉากมืด" on every version of the clip.
    The bank's night photos are grainy, and a noisy source plus an upscale reads
    as a bad clip no matter how good the edit is. Measuring the crop lets the
    lane pick the cleaner frame instead of trusting the query alone.
    """
    import numpy as np  # noqa: PLC0415
    from PIL import Image  # noqa: PLC0415

    with Image.open(path) as im:
        im = im.convert("RGB")
        w, h = im.size
        if w / h > W / H:
            nw = int(round(h * W / H))
            im = im.crop(((w - nw) // 2, 0, (w - nw) // 2 + nw, h))
        else:
            nh = int(round(w * H / W))
            im = im.crop((0, (h - nh) // 2, w, (h - nh) // 2 + nh))
        a = np.asarray(im.convert("L").resize((270, 480)), dtype=np.float32)
    lap = (a[1:-1, :-2] + a[1:-1, 2:] + a[:-2, 1:-1] + a[2:, 1:-1]
           - 4 * a[1:-1, 1:-1])
    return float(lap.var())


def _safe_rows(rows: list[dict], log=print) -> tuple[list[dict], int]:
    """Drop rows that would embarrass the channel, and collapse duplicate ids.

    Two separate defects live here. The manifest carries 14 ids twice with
    different `file` values, so the same picture arrives under two names and the
    de-duplication by image hash cannot see it — the picture simply appears
    twice in one clip. And 44 rows are bar-strip / nightlife scenes whose neon
    signage trips an advertiser filter. Both are dropped before any hash work,
    so a rejected row costs nothing.
    """
    seen_ids: set[str] = set()
    out: list[dict] = []
    risky = dup = 0
    for r in rows:
        if ADULT_TITLE.search(r.get("title", "") or ""):
            risky += 1
            continue
        if r.get("id") in seen_ids:
            dup += 1
            continue
        seen_ids.add(r.get("id"))
        out.append(r)
    if risky or dup:
        log(f"bank: dropped {risky} adult/nightlife row(s) and {dup} duplicate "
            f"manifest id(s) before picking")
    return out, risky + dup


def bank_stills(query: str, want: int, seed: int, log=print) -> list[dict]:
    """Pick stills for a query from the committed manifest, fetching what is packed.

    Prefers rows whose file is still on local disk. When a match is only inside a
    shard, it is materialised on demand, so this lane works on a fresh runner
    where nothing has been extracted yet — which is the normal case on Actions.
    """
    doc = json.loads(MANIFEST.read_text(encoding="utf-8"))
    terms = [t for t in query.lower().split() if t]
    rows = [r for r in doc.get("images", [])
            if all(t in json.dumps(r, ensure_ascii=False).lower() for t in terms)]
    rows, dropped = _safe_rows(rows, log=log)
    if not rows:
        log(f"bank: nothing matches {query!r}")
        return []

    random.Random(seed).shuffle(rows)
    urls = _shard_urls()
    picked, seen = [], []
    for r in rows:
        p = BANK_IMG / Path(r["file"]).name
        if not p.exists() and not _materialise(r, urls, log=log):
            continue
        h = _dhash(p)
        # Two frames of the same corner of the same street are the same picture
        # to a viewer, and Gemini failed a clip for exactly that ("ช็อตซ้ำในลำดับ
        # ใกล้กัน ... มุมเกือบเหมือนกันเป๊ะ"). The bank has many near-duplicates,
        # so reject a candidate that looks like one already chosen. A duplicate
        # is worse than a soft frame, so this rejection is never relaxed.
        if any(_hamming(h, q) <= NEAR_DUP_BITS for q in seen):
            continue
        seen.append(h)
        # A crop narrower than the frame is upscaled to fill 1080x1920, and that
        # upscale is what reads as soft and noisy. Prefer sharp candidates, but
        # keep the narrow one when the sharp pool runs out: the bank's median
        # 9:16 crop is 810 px, so a hard 1000 px cut left the lane with one
        # usable still for "bangkok night" and it refused to render at all
        # (2026-11-20). A soft-but-real frame still beats no clip.
        narrow = _crop_width(p) < MIN_CROP_WIDTH
        picked.append({"path": p, "soft": narrow, **r})
        if len(picked) >= want:
            break
    sharp = [c for c in picked if not c.get("soft")]
    if len(sharp) >= want:
        picked = sharp
    elif picked:
        log(f"bank: kept {len(picked) - len(sharp)} narrow crop(s) under "
            f"{MIN_CROP_WIDTH}px — sharp pool had only {len(sharp)} of {want}")
    return picked[:want]


def song_genre(song: str) -> str | None:
    """The genre id for a song, from whichever record knows it.

    A produced song carries `# GENRE:` in its lyric header, but the masters that
    actually get rendered are older and have no header, so the produce queue is
    the second source. Returns None when nothing knows, and the caller mixes
    across genres rather than guessing one.
    """
    try:
        sys.path.insert(0, str(ROOT / "music938-1" / "scripts"))
        import genres  # noqa: PLC0415
        g = genres.genre_of(song)
        if g:
            return g["id"]
    except Exception:  # noqa: BLE001 - a missing genre is not a render failure
        pass
    try:
        doc = json.loads((ROOT / "music938-1" / "work" / "produce-queue.json")
                         .read_text(encoding="utf-8"))
        for row in doc.get("log", []):
            if row.get("slug") == song and row.get("genre"):
                return row["genre"].lower()
    except Exception:  # noqa: BLE001
        pass
    return None


def ai_stills(genre: str | None, want: int, seed: int, log=print) -> list[dict]:
    """Stills from the AI lane (`ops/image_library.py`), which costs nothing now.

    K (2026-11-20): "เราใช้ผสมกันได้ไม่ใช่เหรอ ขึ้นกับไอเดียในการสร้างวีดีโอ" —
    real photographs and generated frames are both legitimate, and the channel
    says openly that it is AI-made. The generated bank already holds 42 frames
    at 2560x1440 (a 810 px 9:16 crop, the same as the photo bank's median), so
    they pass the same soft-crop rule and add the one thing photographs cannot:
    a frame built for the song instead of found for it.

    An unknown genre is not a reason to skip them. It is a reason to draw from
    every genre, so a song nobody classified still gets generated frames.
    """
    try:
        sys.path.insert(0, str(ROOT / "ops"))
        import image_library  # noqa: PLC0415
    except Exception as exc:  # noqa: BLE001
        log(f"ai: image_library unavailable ({type(exc).__name__}); photos only")
        return []

    doc = image_library.load()
    rows = [r for r in doc.get("images", [])]
    if not rows:
        log("ai: the generated bank is empty; using photographs alone")
        return []
    on_disk = [r for r in rows if (image_library.LIB / r["file"]).exists()]
    if not on_disk:
        # The frames are gitignored (164 MB of PNG), so a fresh runner has the
        # manifest and none of the pictures. Fetch them from the release the same
        # way the photo shards are fetched, then carry on: a mix that silently
        # degrades to photographs looks exactly like a working mix in the log.
        got = _fetch_scenes(rows, log=log)
        on_disk = [r for r in rows if (image_library.LIB / r["file"]).exists()]
        if not got:
            log(f"ai: {len(rows)} generated frame(s) in the manifest but none on "
                f"disk and none in {SCENES_TAG}; using photographs alone")
            return []
    rows = on_disk
    if genre:
        rows = [r for r in rows if r.get("genre") == genre] or rows
    if not rows:
        return []

    random.Random(seed).shuffle(rows)
    picked, seen = [], []
    for r in rows:
        p = image_library.LIB / r["file"]
        h = _dhash(p)
        if any(_hamming(h, q) <= NEAR_DUP_BITS for q in seen):
            continue
        seen.append(h)
        picked.append({"path": p, "soft": _crop_width(p) < MIN_CROP_WIDTH,
                       "origin": "ai", **r})
        if len(picked) >= want:
            break
    if picked:
        log(f"ai: {len(picked)} generated still(s)"
            + (f" for genre {genre}" if genre else " (genre unknown, mixed)"))
    return picked


def mixed_stills(song: str, query: str, want: int, seed: int, log=print) -> list[dict]:
    """Photographs and generated frames, interleaved so neither dominates.

    Variety is the point (K 2026-11-20), and a clip that is all photos looks
    like a documentary while a clip that is all generated frames looks synthetic.
    Alternating them gives each cut a different texture, which is what keeps a
    58 s vertical clip watchable.

    The photo bank stays the base: it is unlimited and free to re-pull, while the
    generated bank is finite, so a shortage on either side is filled from the
    other instead of failing the render.
    """
    genre = song_genre(song)
    ai = ai_stills(genre, max(2, want // 2), seed, log=log)
    photos = bank_stills(query, want, seed, log=log)
    if not ai:
        return photos
    if not photos:
        return ai

    out, i, j = [], 0, 0
    while len(out) < want and (i < len(photos) or j < len(ai)):
        # A photo first: it establishes the place, a generated frame then sets
        # the mood. A clip that opens on generated art reads as a slideshow of
        # wallpapers rather than a song about a real street.
        if i < len(photos):
            out.append(photos[i]); i += 1
        if len(out) >= want:
            break
        if j < len(ai):
            out.append(ai[j]); j += 1
    log(f"mix: {len(out)} still(s) = {i} photo(s) + {j} generated")
    return out[:want]


def _card(text: str, out: Path, size: int = 72, pad: int = 40) -> Path:
    """A Thai title card as a transparent PNG, sized to the text."""
    from PIL import Image, ImageDraw, ImageFont  # noqa: PLC0415

    font = ImageFont.truetype(str(FONT), size)
    tmp = Image.new("RGBA", (10, 10))
    box = ImageDraw.Draw(tmp).multiline_textbbox((0, 0), text, font=font)
    w, h = box[2] - box[0] + pad * 2, box[3] - box[1] + pad * 2
    img = Image.new("RGBA", (w, h), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    d.rounded_rectangle([0, 0, w - 1, h - 1], radius=24, fill=(0, 0, 0, 150))
    d.multiline_text((pad - box[0], pad - box[1]), text, font=font,
                     fill=(255, 255, 255, 255))
    img.save(out)
    return out


def _song_path(song: str, log=print) -> Path | None:
    """Find the audio for a song, fetching it from the release if needed.

    The masters are gitignored (a 240 s mp3 is 5.7 MB), so a fresh runner has the
    script but no music. They do live on `media-938`, so the lane fetches the one
    it needs instead of failing — which is what makes the clip lane runnable on
    Actions at all.
    """
    local = MUSIC / f"{song}.mp3"
    if local.exists():
        return local

    import urllib.request  # noqa: PLC0415

    url = (f"https://github.com/{REPO}/releases/download/{RELEASE_TAG}/{song}.mp3")
    dest = MUSIC / f"{song}.mp3"
    dest.parent.mkdir(parents=True, exist_ok=True)
    try:
        with urllib.request.urlopen(url, timeout=300) as resp, dest.open("wb") as f:
            shutil.copyfileobj(resp, f, 1 << 20)
        log(f"audio: fetched {song}.mp3 from {RELEASE_TAG}")
        return dest
    except Exception as exc:  # noqa: BLE001
        log(f"audio: {song}.mp3 is neither local nor in {RELEASE_TAG} "
            f"({type(exc).__name__})")
        dest.unlink(missing_ok=True)
        return None


def _publishable_only(songs: list[str], log=print) -> list[str]:
    """Drop songs whose genre K parked, so a render cannot start in the wrong lane.

    The release still carries the original 20 เพื่อชีวิต masters, so without this
    a scheduled render would keep producing clips of a parked genre and hand them
    to the publish step. Filtering at the picker is the cheapest place to stop it.
    """
    sys.path.insert(0, str(ROOT / "music938-1" / "scripts"))
    try:
        import genres  # noqa: PLC0415
    except Exception as exc:  # noqa: BLE001
        log(f"genres: cannot load the plan ({type(exc).__name__}); keeping every song")
        return songs
    kept, dropped = [], []
    for s in songs:
        ok, _why = genres.publishable(s)
        (kept if ok else dropped).append(s)
    if dropped:
        log(f"songs: skipped {len(dropped)} in a parked/unknown genre: "
            f"{', '.join(dropped[:4])}{'...' if len(dropped) > 4 else ''}")
    return kept


def available_songs(log=print) -> list[str]:
    """Song names usable on this machine: local files first, then the release.

    The workflow needs this because a fresh runner has no music directory at all,
    and guessing a slug there costs a whole job. The list is the machine-readable
    output (`--list-songs | shuf -n 1`), so progress notes must not share stdout:
    a log line picked as a "song" fails the download and the job with it.
    """
    note = lambda m: print(m, file=sys.stderr)  # noqa: E731
    local = sorted(p.stem for p in MUSIC.glob("*.mp3")) if MUSIC.exists() else []
    if local:
        return _publishable_only(local, log=note)

    import urllib.request  # noqa: PLC0415

    req = urllib.request.Request(
        f"https://api.github.com/repos/{REPO}/releases/tags/{RELEASE_TAG}",
        headers={"Accept": "application/vnd.github+json"})
    tok = os.environ.get("AX_GH_TOKEN")
    if tok:
        req.add_header("Authorization", f"Bearer {tok}")
    try:
        with urllib.request.urlopen(req, timeout=120) as r:
            doc = json.load(r)
        remote = sorted(a["name"][:-4] for a in doc.get("assets", [])
                        if a["name"].endswith(".mp3"))
        return _publishable_only(remote, log=note)
    except Exception as exc:  # noqa: BLE001
        note(f"songs: could not list the release ({type(exc).__name__})")
        return []


def _merge_to(shots: list[dict], n: int) -> list[dict]:
    """Fold a shot list down to `n` shots, so no picture has to repeat.

    Merging keeps the cut that mattered — the boundary with the most energy —
    rather than re-timing everything to a flat grid, which is the slideshow this
    lane replaced. `still` is reassigned 0..n-1 in order, so every picture is
    used exactly once.
    """
    if n <= 0:
        return []
    out = [dict(s) for s in shots]
    while len(out) > n:
        # Drop the boundary whose two sides are closest in energy: that cut is
        # the least audible, so removing it changes the rhythm least.
        i = min(range(len(out) - 1),
                key=lambda k: abs(out[k]["energy"] - out[k + 1]["energy"]))
        out[i]["dur"] = round(out[i]["dur"] + out[i + 1]["dur"], 3)
        del out[i + 1]
    t = 0.0
    for i, s in enumerate(out):
        s["start"] = round(t, 3)
        s["still"] = i
        t += s["dur"]
    # Absorb the rounding drift so the video stays exactly `seconds` long.
    out[-1]["dur"] = round(out[-1]["dur"] + (shots[-1]["start"] + shots[-1]["dur"]
                                             - t), 3)
    return out


def render(song: str, query: str, seconds: float, seed: int, out_dir: Path,
           log=print, mix: bool = True, direct: bool = True) -> Path | None:
    audio = _song_path(song, log=log)
    if audio is None:
        return None

    import shot_director as director  # noqa: PLC0415

    # Plan first, then fetch as many stills as the song wants cuts. The director
    # assigns `still = idx % n_stills`, so a pool smaller than its shot list
    # repeats a picture and Gemini fails the clip for "ช็อตซ้ำ" — a 58 s song
    # asked for 16 cuts from 8 stills, so shots 0-7 came back verbatim in 8-15
    # (2026-11-20). One picture per cut is the honest fix; merging is the
    # fallback for a pool that cannot supply them.
    planned = (director.plan(audio, 64, seconds, seed, log=lambda *_: None)
               if direct else [])
    count = len(planned) if planned else max(6, int(seconds / 7))
    stills = (mixed_stills(song, query, count, seed, log=log) if mix
              else bank_stills(query, count, seed, log=log))
    if len(stills) < 3:
        log(f"render: only {len(stills)} usable still(s); a clip needs 3+")
        return None
    if planned and len(planned) > len(stills):
        log(f"render: {len(planned)} cut(s) but only {len(stills)} still(s); "
            f"merging the closest cuts so no picture repeats")
        planned = _merge_to(planned, len(stills))

    brand = _branding()

    out_dir.mkdir(parents=True, exist_ok=True)
    out = out_dir / f"bank-{song}-{query.replace(' ', '-')}.mp4"

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        title = _card(f"{brand.NAME}\n{brand.FOLLOW_PROMISE}", td / "title.png", 64)
        tail = _card(f"{brand.FOLLOW_ASK}\n{brand.FOLLOW_PROMISE}", td / "tail.png", 58)

        # A director cuts on the music, not on the clock. Every still used to
        # hold `seconds / len(stills)`, which put the cut wherever arithmetic
        # landed -- a slideshow. `shot_director` reads the song and returns a
        # shot list: boundaries snapped to onsets, shot length following the
        # energy, and the camera move rotating so no two shots look alike.
        #
        # Each shot is its own `-loop 1 -t dur` input, so `zoompan`'s `d` is 1
        # (one output frame per input frame) and `on` runs 0..n-1 for the move
        # expressions. The old form looped the image and asked for `per * FPS`
        # output frames each, which multiplied out to per^2 * FPS^2 frames from
        # the first image alone (18,750 for a 30 s clip) and stills 2..n never
        # appeared; the clip played as one still that slowly zoomed.
        shots = (planned if planned else
                 [{"start": i * (seconds / len(stills)),
                   "dur": seconds / len(stills), "still": i,
                   "move": "push_in", "energy": 0.5}
                  for i in range(len(stills))])
        if log is not None and direct:
            log("director: shot list\n" + director.describe(shots))

        args = ["ffmpeg", "-y", "-loglevel", "error", "-ss", "0",
                "-t", f"{seconds:.2f}", "-i", str(audio)]
        for s in shots:
            # `-framerate` matters: without it the still loop runs at ffmpeg's
            # default 25 fps while the output is 30, so the shot drifts and the
            # concat stretches it. One input frame per output frame is what lets
            # `zoompan d=1` walk the move across the whole shot.
            args += ["-loop", "1", "-framerate", str(FPS),
                     "-t", f"{s['dur']:.3f}",
                     "-i", str(stills[s["still"]]["path"])]
        n = len(shots)
        args += ["-loop", "1", "-t", "3", "-i", str(title)]
        args += ["-loop", "1", "-t", "3", "-i", str(tail)]

        parts = []
        for i, s in enumerate(shots):
            frames = max(1, int(round(s["dur"] * FPS)))
            # Cover-crop straight to the frame, then let zoompan move. The old
            # chain pre-scaled to 2x and cropped that, which turned a 1920x1280
            # landscape into a 720-wide 9:16 strip blown up 3x -- the noise and
            # softness Gemini reported on every night clip. Lanczos keeps a
            # genuine upscale clean when the bank has nothing larger.
            parts.append(
                f"[{i + 1}:v]scale={W}:{H}:force_original_aspect_ratio=increase:"
                f"flags=lanczos,crop={W}:{H},"
                f"{director.zoompan(s, frames, W, H, FPS)},setsar=1[v{i}]")
        chain = "".join(f"[v{i}]" for i in range(n)) + f"concat=n={n}:v=1:a=0[base]"
        parts.append(chain)

        # Title over the first two seconds, follow ask over the last three.
        parts.append(f"[base][{n + 1}:v]overlay=(W-w)/2:180:enable='lt(t,2.5)'[t1]")
        parts.append(f"[t1][{n + 2}:v]overlay=(W-w)/2:h-h-420:"
                     f"enable='gt(t,{seconds - 3:.2f})'[vout]")
        parts.append("[0:a]loudnorm=I=-15:TP=-1.5:LRA=11[aout]")

        args += ["-filter_complex", ";".join(parts),
                 "-map", "[vout]", "-map", "[aout]",
                 "-c:v", "libx264", "-preset", "medium", "-crf", "21",
                 "-pix_fmt", "yuv420p", "-r", str(FPS),
                 "-c:a", "aac", "-b:a", "160k", "-ar", "48000", "-ac", "2",
                 "-movflags", "+faststart", "-shortest", str(out)]

        log(f"render: {n} still(s) over {seconds:.0f}s -> {out.name}")
        r = subprocess.run(args, capture_output=True, text=True)
        if r.returncode != 0:
            log(f"render FAILED: {r.stderr.strip()[:600]}")
            return None

    import clip_standard  # noqa: PLC0415

    failed = [f"{name}: {detail}" for name, ok, detail
              in clip_standard.check(str(out), profile="vertical") if not ok]
    if failed:
        log("render: below the clip floor, deleted -- " + "; ".join(failed))
        out.unlink(missing_ok=True)
        return None

    # Written before the Gemini gate, not after: a clip kept for review still has
    # sources to attribute, and CC BY-SA requires the credit wherever the clip
    # goes. Writing it only on the pass path left a clip that was reviewed later
    # and then published with no credit file at all.
    #
    # A generated frame has no Commons licence to attribute, and `licence: null`
    # would read as a missing credit rather than a different kind of source. K
    # (2026-11-20) is explicit that the channel does not hide the AI, so the file
    # says it plainly.
    credits = []
    for s in stills:
        if s.get("origin") == "ai":
            credits.append({"file": s["path"].name, "origin": "ai",
                            "model": s.get("model"), "prompt": s.get("prompt")})
        else:
            credits.append({"file": s["path"].name, "licence": s.get("licence"),
                            "credit": s.get("credit"), "source": s.get("source")})
    out.with_suffix(".credits.json").write_text(
        json.dumps({"song": song, "query": query, "items": credits},
                   ensure_ascii=False, indent=1), encoding="utf-8")

    # The floor above measures the file, not the content: a clip whose six
    # stills collapsed into one frozen picture passed all 14 rules on
    # 2026-11-19 and reached K. Content needs its own gate, and K's rule is
    # absolute -- "no Gemini pass, no upload" -- so a
    # clip with no passing verdict is not shown and not kept.
    import gemini_gate  # noqa: PLC0415

    ok, why = gemini_gate.check(out)
    if not ok:
        # Not a failure of this lane: the file is rendered and above the floor,
        # and what it waits for is a Gemini verdict, which needs the signed-in
        # desktop and so cannot happen on a runner. The marker is distinct from
        # PASSED so the workflow reports "awaiting review" instead of going red
        # forever -- a permanently red rail is how a real red gets ignored.
        # Nothing is uploaded from this branch; K's rule is no verdict, no channel.
        log(f"render: AWAITING GEMINI REVIEW -> {out}")
        log(f"render: NOT SHOWN, waiting for a Gemini pass -- {why}")
        log("render: review it with "
            f"`python3 ops/gemini_review.py {out}`")
        return out

    log(f"render: PASSED the floor -> {out}")
    return out


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument("--song", help="a name in aeris938-1/library/music (or the release)")
    ap.add_argument("--list-songs", action="store_true")
    ap.add_argument("--query", default="bangkok night")
    ap.add_argument("--seconds", type=float, default=58)
    ap.add_argument("--seed", type=int, default=11)
    ap.add_argument("--out", default=str(OUT))
    ap.add_argument("--photos-only", action="store_true",
                    help="skip the generated bank and use photographs alone")
    ap.add_argument("--no-direct", action="store_true",
                    help="cut on an even grid instead of on the music")
    args = ap.parse_args(argv)
    if args.list_songs:
        songs = available_songs()
        print("\n".join(songs))
        return 0 if songs else 1
    if not args.song:
        ap.error("--song is required unless --list-songs is given")
    # An explicit --song bypasses the picker, so the gate has to be repeated here
    # or a hand-run could still render a parked genre.
    if _publishable_only([args.song]) != [args.song]:
        print(f"refusing --song {args.song}: its genre is parked or unknown "
              f"(see music938-1/channel/genres.json)")
        return 1
    got = render(args.song, args.query, args.seconds, args.seed, Path(args.out),
                 mix=not args.photos_only, direct=not args.no_direct)
    return 0 if got else 1


if __name__ == "__main__":
    raise SystemExit(main())
