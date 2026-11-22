#!/usr/bin/env python3
"""Build a real music video for a song — many moving shots, cut on the beat.

K (2026-11-13): "ช่องทำเพลง ai จะใช้ภาพนิ่งแล้วใช้เทคนิค เป็นหน้าฉากแบบการเล่น
วีดีโอเคลื่อนไหว ทำภาพเหมือนดีเจคุมเครื่องเสียง แต่ไม่ค่อยมีทำมิวสิควีดีโอ ถ้าเราทำได้
น่าจะมีคนสนใจ."

Every other AI music channel ships one still cover on a slow fake zoom, dressed up
as "the DJ at the console". Nobody ships an actual music video. This rail does:
several scenes, each with real camera movement, cut on the song's own beat, with
an audio-reactive VJ bar. That is the differentiator, and it is the thing a viewer
scrolls past a still to watch.

Why the movement is real, measured. On this ffmpeg a slow zoom over a whole clip
gives ~1.9 mean abs frame diff (barely alive). A *short* shot with a strong pan
gives 7.2, a push+rotate 4.2 — close to a free AI image-to-video model (8.3) but
with no quota and no wait. So the motion here is built from many short, strongly
moving shots, not one long gentle zoom.

Rule #1: the scenes come from Pollinations (free, key-less), the camera moves are
ffmpeg, the audio is the song we already own. Nothing is paid for.

    python3 scripts/make_music_video.py --list
    python3 scripts/make_music_video.py 01-khon-di-thi-chak-pai
    python3 scripts/make_music_video.py 01-khon-di-thi-chak-pai --full
    python3 scripts/make_music_video.py --all --seconds 40
"""
from __future__ import annotations

import argparse
import datetime
import json
import math
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

import ai_covers  # noqa: E402  (reuse the free, paced Pollinations fetch)
import release  # noqa: E402
from covers import THAI_FONT, _font  # noqa: E402
from make_short import _duration, chorus_span, load_lyrics  # noqa: E402

SONGS = ROOT / "library" / "songs"
COVERS = ROOT / "library" / "covers"
STORIES = ROOT / "library" / "stories"
SCENES = ROOT / "library" / "mv"          # AI-generated video scenes (cached)
WORK = ROOT / "work" / "mv"
OUT_DIR = ROOT / "library" / "musicvideo"

W, H, FPS = 1080, 1920, 30


def _k() -> float:
    """Overlay scale: every pixel size below was drawn for a 1920-tall frame.

    K asked for 4K MVs (2026-11-21). The camera moves are already parametric, but
    the cards and the VJ bar are absolute pixels, so at 2160x3840 an unscaled 96 px
    title reads as a caption. Everything that is a size is multiplied by this.
    """
    return H / 1920.0

# The AI scenes. These are the "not just a still" content: a console shot for the
# channel's signature, then places a lyric can live in. Kept text-free — Thai
# titles are composited by Pillow, because an image model misspells Thai.
SCENE_PROMPTS: list[tuple[str, str]] = [
    ("console", "a DJ seen from behind at a glowing mixing console, hands on the "
                "decks, neon nightclub, atmospheric haze, cinematic wide shot"),
    ("crowd", "a sea of raised hands in a dark neon club, silhouettes, sweeping "
              "stage light beams, confetti, cinematic"),
    ("city", "a rain-soaked neon city street at night, wet reflections, a lone "
             "figure walking away under a streetlight, cinematic"),
    ("sky", "a vast dramatic dusk sky over a dark silhouette landscape, "
            "volumetric clouds, warm horizon light, cinematic"),
]

# Camera moves over a still. Each returns an ffmpeg -vf fragment for a shot of
# `n` frames at FPS. The oversize factor leaves room to pan without black edges.
# A shot is short (2-4 s) so a strong move reads as energy, not as a drift.
MOVES: dict[str, str] = {
    # Push in: the classic, but over a SHORT shot it actually reads as motion.
    "push": ("scale={ow}:{oh}:force_original_aspect_ratio=increase,"
             "crop={w}:{h}:x='(iw-{w})/2':y='(ih-{h})/2',"
             "zoompan=z='min(1+{zr}*on/{n},{zmax})':d=1:"
             "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={w}x{h}:fps={fps}"),
    "pull": ("scale={ow}:{oh}:force_original_aspect_ratio=increase,"
             "crop={w}:{h}:x='(iw-{w})/2':y='(ih-{h})/2',"
             "zoompan=z='max({zmax}-{zr}*on/{n},1.0)':d=1:"
             "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={w}x{h}:fps={fps}"),
    # Pan right/left across the oversize: the strongest cheap move (7.2 measured).
    "pan_r": ("scale={ow}:{oh}:force_original_aspect_ratio=increase,"
              "crop={w}:{h}:x='(iw-{w})*min(t/{d},1)':y='(ih-{h})/2'"),
    "pan_l": ("scale={ow}:{oh}:force_original_aspect_ratio=increase,"
              "crop={w}:{h}:x='(iw-{w})*(1-min(t/{d},1))':y='(ih-{h})/2'"),
    # Tilt up/down, for the sky and the console.
    "tilt_u": ("scale={ow}:{oh}:force_original_aspect_ratio=increase,"
               "crop={w}:{h}:x='(iw-{w})/2':y='(ih-{h})*(1-min(t/{d},1))'"),
    "tilt_d": ("scale={ow}:{oh}:force_original_aspect_ratio=increase,"
               "crop={w}:{h}:x='(iw-{w})/2':y='(ih-{h})*min(t/{d},1)'"),
    # Diagonal drift: pan and push at once, the most "shot on a gimbal" of them.
    "drift": ("scale={ow}:{oh}:force_original_aspect_ratio=increase,"
              "crop={w}:{h}:x='(iw-{w})*min(t/{d},1)':y='(ih-{h})*(1-min(t/{d},1))',"
              "zoompan=z='min(1+{zr}*on/{n},{zdmax})':d=1:"
              "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={w}x{h}:fps={fps}"),
    # Push with a slow sway, for the emotional chorus. It starts already zoomed
    # (Z_MIN) because `rotate` runs after the crop: at z=1.0 there is no overscan
    # for the rotation to eat, and the frame's corners go black.
    "push_rotate": ("scale={ow}:{oh}:force_original_aspect_ratio=increase,"
                    "crop={w}:{h}:x='(iw-{w})/2':y='(ih-{h})/2',"
                    "zoompan=z='min({zmin}+{zr}*on/{n},{zmax})':d=1:"
                    "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={w}x{h}:fps={fps},"
                    "rotate='0.012*sin(2*PI*t/{d})':fillcolor=black"),
}

# One move per shot, chosen so no two neighbours repeat and the song's arc rises:
# open wide, travel, and land on a push for the hook.
MOVE_ORDER = ("pan_r", "push", "drift", "tilt_u", "pull", "pan_l",
              "push_rotate", "tilt_d")

# How much bigger than the frame the pan source is. This is also the distance a
# pan travels in one shot, so it sets how fast the picture slides: 1.45 moved 45%
# of the frame width inside a 1.6 s shot, which reads as a whip pan rather than a
# camera. 1.20 halves that travel and the longer shot below quarters the speed.
OVERSIZE = 1.20

# Zoom travel per shot. The old 0.16-0.34 range was a lunge; a push that grows
# ~10% over three seconds reads as a deliberate move.
ZOOM_RATE = 0.10
ZOOM_MAX = 1.18
ZOOM_DRIFT_MAX = 1.08
# `push_rotate` rotates after the crop, so it needs overscan to rotate into or
# the corners swing black. Start it already inside the zoom range.
ZOOM_MIN_ROTATE = 1.10

# K, 2026-11-20: "ภาพเลื่อนเร็วเกิน" — the picture moved too fast. At two beats
# per cut a 120 bpm song changed shot every 1.6 s (140 shots in 222 s), and each
# shot slid 45% of the frame. The cut now lands on the beat but only where a shot
# is long enough to read: three to four seconds.
SHOT_MIN, SHOT_MAX = 2.8, 5.5


def shot_seconds(bpm: float) -> float:
    """Per-shot length for a song at `bpm`: a whole number of beats, 2.8-5.5 s.

    The multiple is chosen rather than fixed, so a cut still lands on the beat at
    any tempo while the shot itself stays long enough to watch: 68 bpm gives four
    beats (3.5 s), 120 bpm six (3.0 s), 180 bpm eight (2.7 s).
    """
    beat = 60.0 / max(bpm, 40.0)
    for beats in (2, 3, 4, 6, 8, 10, 12, 16):
        length = beat * beats
        if length >= SHOT_MIN:
            return min(SHOT_MAX, length)
    return SHOT_MAX


def distinct_sources(paths: list[Path]) -> list[Path]:
    """The pictures, each one once, in order (K, 2026-11-21).

    "ภาพ mv ห้ามซ้ำกันในแต่ละ mv" — a still may appear only once in a video.
    Two entries can resolve to the same file (a cover that is also in the
    library), and a caller may hand the same path twice, so dedupe on the
    resolved path rather than on the string.
    """
    seen: set[Path] = set()
    out: list[Path] = []
    for p in paths:
        key = p.resolve()
        if key in seen:
            continue
        seen.add(key)
        out.append(p)
    return out


def plan_shots(length: float, bpm: float) -> tuple[int, float]:
    """How many shots the video has, and the evened-out length of each.

    Evened out so the last shot is not a stub and every shot gets the same
    camera move budget.
    """
    n = max(3, int(math.ceil(length / shot_seconds(bpm))))
    return n, length / n


def _scene(slug: str, name: str) -> Path:
    return SCENES / f"scene-{slug}-{name}.jpg"


def scene_prompt(name: str) -> str:
    return next(p for n, p in SCENE_PROMPTS if n == name)


# Song mood -> picture-library theme. The library holds real 4K photographs, and
# a 4K source is what lets a pan or push stay sharp; Pollinations answers at
# 1024x576, which softens the moment the camera moves. So the library is tried
# first and the AI route is only a gap-filler.
MOOD_THEMES: dict[str, str] = {
    "sad": "lesson", "hopeful": "nature", "warm": "city", "mystic": "horror",
    "calm": "nature", "epic": "temple",
}


def library_scenes(slug: str, want: int, log=print) -> list[Path]:
    """4K stills from the picture library, chosen by the song's mood."""
    try:
        sys.path.insert(0, str(ROOT.parent / "ops"))
        import media_home  # noqa: PLC0415
    except Exception:  # noqa: BLE001
        return []
    meta, _ = load_lyrics(slug)
    theme = MOOD_THEMES.get((meta.get("mood") or "").lower(), "city")
    try:
        lib = media_home.pictures()
    except SystemExit:
        return []
    idx = lib / "index.json"
    if not idx.exists():
        return []
    try:
        rows = json.loads(idx.read_text(encoding="utf-8")).get("images", [])
    except (OSError, ValueError):
        return []
    rows = [r for r in rows if r.get("theme") == theme and (lib / r["file"]).exists()]
    rows.sort(key=lambda r: (r.get("uses") or 0, r.get("id") or ""))
    picked = [lib / r["file"] for r in rows[:want]]
    for r in rows[:want]:
        r["uses"] = (r.get("uses") or 0) + 1
    if picked:
        try:
            idx.write_text(json.dumps({"images": rows}, ensure_ascii=False, indent=1))
        except OSError:
            pass
        log(f"  [mv] {len(picked)} scene(s) from the 4K library ({theme})")
    return picked


def make_scene(slug: str, name: str, *, force: bool = False) -> Path:
    """Generate (or reuse) one AI scene at 16:9, via the free Pollinations route."""
    out = _scene(slug, name)
    if out.exists() and not force:
        return out
    SCENES.mkdir(parents=True, exist_ok=True)
    meta, _ = load_lyrics(slug)
    prompt = (scene_prompt(name)
              + f" | mood: {meta.get('mood', 'cinematic')}, "
              + "style: cinematic film still, moody, rich colour grading, "
                "high dynamic range, anamorphic, subtle grain, "
                "absolutely no text, no letters, no words, no watermark")
    seed = abs(hash((slug, name))) % 100000
    data = ai_covers._fetch_pollinations(prompt, seed)
    out.write_bytes(data)
    return out


def _shot_filter(move: str, frames: int, dur: float) -> str:
    ow, oh = int(W * OVERSIZE), int(H * OVERSIZE)
    return MOVES[move].format(w=W, h=H, ow=ow, oh=oh, n=frames, d=f"{dur:.3f}",
                              fps=FPS, zr=ZOOM_RATE, zmax=ZOOM_MAX,
                              zdmax=ZOOM_DRIFT_MAX, zmin=ZOOM_MIN_ROTATE)


def render_shot(src: Path, move: str, dur: float, out: Path,
                ffmpeg: str = "ffmpeg") -> None:
    """Render one still into a moving shot of `dur` seconds."""
    frames = max(1, int(round(dur * FPS)))
    vf = _shot_filter(move, frames, dur) + ",setsar=1,format=yuv420p"
    subprocess.run(
        [ffmpeg, "-y", "-v", "error", "-loop", "1", "-framerate", str(FPS),
         "-i", str(src), "-t", f"{dur:.3f}", "-vf", vf, "-r", str(FPS),
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", str(out)],
        check=True)


def _cut_card(text: str, sub: str, out: Path, *, fade: bool = True) -> None:
    """A Thai title/end card on a dark field, so the video opens and closes right."""
    from PIL import Image, ImageDraw, ImageFilter

    k = _k()
    img = Image.new("RGB", (W, H), (10, 10, 14))
    d = ImageDraw.Draw(img)
    for i in range(60):  # a soft vertical glow, no photo needed
        c = int(10 + 40 * (1 - abs(i - 30) / 30))
        d.rectangle([0, i * H // 60, W, (i + 1) * H // 60], fill=(c // 3, c // 4, c))
    img = img.filter(ImageFilter.GaussianBlur(max(2.0, 8 * k)))
    d = ImageDraw.Draw(img)
    f1 = _font(THAI_FONT, int(96 * k), bold=True)
    f2 = _font(THAI_FONT, int(52 * k))
    tw = d.textlength(text, font=f1)
    d.text(((W - tw) / 2, H / 2 - int(140 * k)), text, font=f1,
           fill=(255, 255, 255))
    sw = d.textlength(sub, font=f2)
    d.text(((W - sw) / 2, H / 2 + int(10 * k)), sub, font=f2,
           fill=(180, 200, 255))
    img.save(out)


def shelve(clip: str, title: str, theme: str) -> str:
    """Move a QC-passed MV onto the finished shelf and index it (K 2026-11-20)."""
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import media_home  # noqa: PLC0415

    dest_dir = media_home.finished()
    dest = dest_dir / Path(clip).name
    if Path(clip).resolve() != dest.resolve():
        Path(clip).replace(dest)
    idx = dest_dir / "index.json"
    try:
        data = json.loads(idx.read_text(encoding="utf-8"))
    except (OSError, ValueError):
        data = {"clips": []}
    clips = [c for c in data.get("clips", []) if c.get("file") != dest.name]
    clips.append({
        "file": dest.name, "title": title, "theme": theme,
        "bytes": dest.stat().st_size,
        "at": datetime.datetime.now(datetime.timezone.utc).isoformat(
            timespec="seconds"),
        "uploaded": False,
    })
    idx.write_text(json.dumps({"clips": clips}, ensure_ascii=False, indent=1),
                   encoding="utf-8")
    return str(dest)


def build(slug: str, *, seconds: float | None = None, full: bool = False,
          ffmpeg: str = "ffmpeg", force_scenes: bool = False) -> dict:
    song = SONGS / f"song-{slug}.mp3"
    if not song.exists():
        raise SystemExit(f"no song: {song}")
    # An MV is a publish, so the genre rule applies. It is asked of the
    # compass, which is the one place that answers it.
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import compass  # noqa: PLC0415
    gate_ok, gate_why = compass.is_publishable(slug)
    if not gate_ok:
        raise SystemExit(f"genre gate refuses {slug}: {gate_why}")
    meta, _ = load_lyrics(slug)

    total = _duration(song)
    if full:
        start, length = 0.0, total
    else:
        sf, lf = chorus_span(slug)
        start, length = sf * total, lf * total
        if seconds:
            length = min(length, seconds)
        length = max(length, 8.0)

    # The beat. TEMPO is the song's own BPM; cut every 2 beats so a slow ballad
    # still changes picture often enough to hold a scrolling viewer.
    try:
        bpm = float(meta.get("tempo", 80))
    except ValueError:
        bpm = 80.0
    n_shots, shot = plan_shots(length, bpm)

    WORK.mkdir(parents=True, exist_ok=True)
    shots: list[Path] = []
    # The 4K library first: it is the only source that stays sharp under a pan.
    # The AI scenes only fill what the library cannot cover for this mood, and
    # they are never mixed in when the library already has enough pictures —
    # a 1024 px scene next to a 3840 px one reads as a soft shot.
    sources: list[Path] = list(library_scenes(slug, want=n_shots))
    if len(sources) < 4:
        for name, _ in SCENE_PROMPTS:
            try:
                sources.append(make_scene(slug, name, force=force_scenes))
            except Exception as e:  # noqa: BLE001 - a missing scene must not kill the video
                print(f"  scene {name} unavailable: {type(e).__name__}: {str(e)[:100]}",
                      file=sys.stderr)
    for p in (COVERS / f"cover-{slug}.jpg", STORIES / f"story-{slug}.jpg"):
        if p.exists():
            sources.append(p)
    if not sources:
        raise SystemExit(f"no art at all for {slug}")

    # No picture twice in one video: dedupe, then hold each shot longer rather
    # than repeat a picture. Repeating it was the old behaviour (`i % len`), and
    # with 8 sources it showed the same 8 stills eight times in a 3-minute MV.
    sources = distinct_sources(sources)
    if len(sources) < n_shots:
        print(f"  [mv] {len(sources)} distinct picture(s) for {n_shots} shots — "
              f"holding each longer instead of repeating one", file=sys.stderr)
        n_shots = len(sources)
        shot = length / n_shots

    for i in range(n_shots):
        src = sources[i]
        move = MOVE_ORDER[i % len(MOVE_ORDER)]
        out = WORK / f"shot-{slug}-{i:02d}.mp4"
        render_shot(src, move, shot, out, ffmpeg=ffmpeg)
        shots.append(out)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / (f"mv-{slug}-full.mp4" if full else f"mv-{slug}-hook.mp4")

    # Title at the top, end card at the tail, both as stills laid over the cut.
    title = WORK / f"card-title-{slug}.png"
    endc = WORK / f"card-end-{slug}.png"
    _cut_card(meta.get("title", slug), release.FOLLOW_ASK, title)
    _cut_card(meta.get("title", slug), release.FOLLOW_PROMISE, endc)

    listfile = WORK / f"concat-{slug}.txt"
    listfile.write_text("".join(f"file '{p.resolve()}'\n" for p in shots),
                        encoding="utf-8")

    # Concat the shots, overlay the two cards, lay an audio-reactive VJ bar at the
    # foot (showwaves reacts to the real song, so the picture answers the music),
    # and mux the chorus.
    t_fade = 1.5
    fc = (
        f"[0:v]fps={FPS},format=yuv420p[base];"
        f"[1:v]format=rgba,fade=t=in:st=0:d={t_fade}:alpha=1,"
        f"fade=t=out:st={t_fade}:d={t_fade}:alpha=1[tc];"
        f"[2:v]format=rgba,fade=t=in:st=0:d=1.2:alpha=1[ec];"
        f"[base][tc]overlay=0:0:enable='lt(t,{t_fade*2})'[b1];"
        f"[b1][ec]overlay=0:0:enable='gt(t,{length-3.0})'[b2];"
        f"[3:a]showwaves=s={W}x{int(220 * _k())}:mode=cline:"
        f"colors=0x8affc1|0xff8ad8:"
        f"rate={FPS},format=rgba,colorchannelmixer=aa=0.30[wave];"
        f"[b2][wave]overlay=0:H-{int(300 * _k())}[b3];"
        f"[b3]setsar=1,format=yuv420p[out];"
        # Normalise at the mux, as the film lane does, so every MV meets the
        # channel floor regardless of the source master's level.
        f"[3:a]loudnorm=I=-14:TP=-2.0:LRA=11,alimiter=limit=0.7:level=0[aout]"
    )
    subprocess.run(
        [ffmpeg, "-y", "-v", "error",
         "-f", "concat", "-safe", "0", "-i", str(listfile),
         "-loop", "1", "-i", str(title),
         "-loop", "1", "-i", str(endc),
         "-ss", f"{start:.3f}", "-t", f"{length:.3f}", "-i", str(song),
         "-filter_complex", fc, "-map", "[out]", "-map", "[aout]",
         "-t", f"{length:.3f}", "-c:v", "libx264", "-preset", "medium",
         "-crf", "20", "-pix_fmt", "yuv420p", "-r", str(FPS),
         "-c:a", "aac", "-ar", "48000", "-b:a", "192k", "-shortest", str(out)],
        check=True)

    # The floor gate. K: "คลิปวีดีโอที่ต่ำกว่าเกณฑ์มาตรฐาน ห้ามอัพขึ้นเด็ดขาด", so an
    # MV below the floor is deleted here rather than left on disk looking shippable.
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import clip_standard as cs  # noqa: PLC0415
    problems = cs.check(str(out), "vertical")
    for name, ok, detail in problems:
        print(f"  [qc] {'ok  ' if ok else 'FAIL'} {name}: {detail}")
    if not all(ok for _, ok, _ in problems):
        out.unlink(missing_ok=True)
        raise SystemExit("MV below the clip floor, deleted")

    dest = shelve(str(out), meta.get("title", slug), "mv")
    return {"slug": slug, "path": str(dest), "shots": n_shots,
            "seconds": round(length, 1), "bpm": bpm,
            "bytes": Path(dest).stat().st_size}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("slug", nargs="?")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--full", action="store_true", help="the whole song, not the hook")
    ap.add_argument("--seconds", type=float, help="cap the length")
    ap.add_argument("--force-scenes", action="store_true", help="regenerate AI scenes")
    ap.add_argument("--height", type=int, default=1920,
                    help="output height; 3840 for a 4K vertical MV (default 1920)")
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    global W, H
    if args.height and args.height != H:
        H = args.height + (args.height % 2)
        W = int(H * 9 / 16)
        W += W % 2
        print(f"[mv] {W}x{H} ({H / 1920:.2f}x overlays)")

    if args.list:
        print("scenes:")
        for n, p in SCENE_PROMPTS:
            print(f"  {n:9s} {p[:70]}")
        print("camera moves:", ", ".join(MOVES))
        return 0

    if args.all:
        # `ops/compass.py` decides which songs a lane may render; globbing
        # here rendered parked-genre clips that could never be uploaded.
        sys.path.insert(0, str(ROOT.parent / "ops"))
        import compass  # noqa: PLC0415
        slugs = compass.songs("mv")
    elif args.slug:
        slugs = [args.slug]
    else:
        ap.error("give a slug or --all")

    for slug in slugs:
        try:
            info = build(slug, seconds=args.seconds, full=args.full,
                         force_scenes=args.force_scenes)
            print(f"{slug}: {info['path']} "
                  f"({info['shots']} shots, {info['seconds']}s, {info['bpm']:.0f} bpm)")
        except Exception as e:  # noqa: BLE001
            print(f"{slug}: FAILED {type(e).__name__}: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
