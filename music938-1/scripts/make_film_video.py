#!/usr/bin/env python3
"""Build a real music video out of public-domain film footage, matched to the song.

K (2026-11-13): "ช่องทำเพลง ai จะใช้ภาพนิ่งแล้วใช้เทคนิค เป็นหน้าฉากแบบการเล่น
วีดีโอเคลื่อนไหว ... ทำภาพเหมือนดีเจคุมเครื่องเสียง แต่ไม่ค่อยมีทำมิวสิควีดีโอ ถ้าเรา
ทำได้ น่าจะมีคนสนใจ" — the reference is Tones And I - Dance Monkey, a real film with
actors. Then the correction that sets the bar: "วีดีโอต้องเหมาะกับเพลงและบทเพลงสิ".

So this is not "a film that moves". It is *this* film for *this* song, cut to
*this* song's shape:

- **The film is chosen by the lyric's mood.** An epic rock anthem about refusing
  to stay down gets a fight-and-redemption film; a warm pop song gets a colour
  musical. A film that fights the song is the failure, however lively it is.
- **The cut follows the sections, not a flat beat.** A chorus is cut short and
  hard; a verse breathes on longer shots. The picture's pulse is the song's pulse.
- **The grade follows the section too.** Verses sit cool and a touch dark, the
  chorus lifts bright and warm, so the hook is felt and not only heard.
- **The footage is picked by energy.** Sampling the film for its most active,
  best-lit moments gives the chorus its movement and the verse its stillness.

Why a public-domain film and not an AI clip: every free ZeroGPU Space shares one
quota per IP, so three "different" programs buy the same three clips a day — not
enough for a film. The Internet Archive holds ~21,000 public-domain films with
real actors and real camera movement, free, no login, no quota.

Rule #1: the film is public domain, the song is ours, the tools are ffmpeg and
Pillow. Nothing is paid for. The film's own audio is discarded, so no third-party
score rides along to be claimed.

    python3 scripts/make_film_video.py --list
    python3 scripts/make_film_video.py 24-yut-mai-yom --seconds 40
    python3 scripts/make_film_video.py 24-yut-mai-yom --full
"""
from __future__ import annotations

import argparse
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(Path(__file__).resolve().parent))

import numpy as np  # noqa: E402

import release  # noqa: E402
from covers import THAI_FONT, _font  # noqa: E402
from make_short import _duration, chorus_span, load_lyrics  # noqa: E402

SONGS = ROOT / "library" / "songs"
LYRICS = ROOT / "lyrics"
WORK = ROOT / "work" / "filmvideo"
OUT_DIR = ROOT / "library" / "musicvideo"

# A film is ~300 MB; $HOME is wiped on a pod recycle and only /workspace survives,
# so the cache lives beside the other durable AX state, not in the repo.
FILM_DIR = Path("/workspace/ax-tools/aeris938-state/film")

W, H, FPS = 1920, 1080, 30

# Public-domain films on the Internet Archive. `moods` is the point: a film is
# cast like an actor, so the picture answers the lyric. `ident` is the item,
# `file` the derivative to pull, `note` the credit for the description.
FILMS: list[dict] = [
    {
        "id": "rock_rock_rock",
        "ident": "rock_rock_rock",
        "file": "Rock_Rock_Rock.mp4",
        "title": "Rock, Rock, Rock!",
        "year": 1956,
        # A colour rock'n'roll film: live bands, dancing teenagers. The closest
        # thing in the public domain to the energy of a rock song's own genre.
        "moods": ["epic", "hopeful"],
        "note": "Rock, Rock, Rock! (1956), public domain, via Internet Archive.",
    },
    {
        "id": "criminal",
        "ident": "They_Made_Me_A_Criminal_1939",
        "file": "they_made_me_a_criminal_1939.mp4",
        "title": "They Made Me a Criminal",
        "year": 1939,
        # A boxer on the run who clears his name and stands up again: the exact
        # arc of "ยืนหยัดไม่ยอมแพ้โชคชะตา".
        "moods": ["epic", "hopeful", "sad"],
        "note": "They Made Me a Criminal (1939), public domain, via Internet Archive.",
    },
    {
        "id": "gun_pulpit",
        "ident": "cco_thegunandthepulpit",
        "file": "ccoPublicDomainThe_Gun_and_the_Pulpit.mp4",
        "title": "The Gun and the Pulpit",
        "year": 1974,
        "moods": ["epic", "mystic", "warm"],
        "note": "The Gun and the Pulpit (1974), public domain, via Internet Archive.",
    },
    {
        "id": "pied_piper",
        "ident": "The_Pied_Piper_of_Hamelin",
        "file": "pied.mp4",
        "title": "The Pied Piper of Hamelin",
        "year": 1957,
        # A colour musical: singing, dancing, a crowd — for a bright pop hook.
        "moods": ["hopeful", "warm", "calm"],
        "note": "The Pied Piper of Hamelin (1957), public domain, via Internet Archive.",
    },
    {
        "id": "haunted_hill",
        "ident": "house_on_haunted_hill_ipod",
        "file": "house_on_haunted_hill_512kb.mp4",
        "title": "House on Haunted Hill",
        "year": 1959,
        # Black-and-white noir: shadow and unease, for a sad or mystic song.
        "moods": ["sad", "mystic"],
        "note": "House on Haunted Hill (1959), public domain, via Internet Archive.",
    },
    {
        "id": "his_girl_friday",
        "ident": "his_girl_friday",
        "file": "his_girl_friday_512kb.mp4",
        "title": "His Girl Friday",
        "year": 1940,
        "moods": ["warm", "hopeful"],
        "note": "His Girl Friday (1940), public domain, via Internet Archive.",
    },
]

# A song may name its own film with `# FILM: <id>` in the lyric header; otherwise
# the mood picks one. Either way the choice is recorded in the returned info.
DEFAULT_FILM = "haunted_hill"

# How hard a section is cut. A chorus is the hook, so it is cut fast; a verse is
# where the story is told, so it breathes.
SECTION_ENERGY: dict[str, float] = {
    "chorus": 1.0, "prechorus": 0.8, "bridge": 0.7, "solo": 0.7,
    "verse": 0.45, "instrumental": 0.5, "intro": 0.3, "outro": 0.3,
    "break": 0.3, "end": 0.3,
}

# Mood -> a single eq filter. This is the whole look; the per-section lift is
# applied on top, per shot.
MOOD_GRADE: dict[str, str] = {
    "epic": "eq=contrast=1.12:saturation=1.06:brightness=0.01",
    "hopeful": "eq=contrast=1.05:saturation=1.16:brightness=0.04,"
               "colorbalance=rs=0.03:gs=0.01:bs=-0.03",
    "warm": "eq=contrast=1.04:saturation=1.08:brightness=0.03,"
            "colorbalance=rs=0.04:bs=-0.04",
    "sad": "eq=contrast=1.05:saturation=0.84:brightness=-0.02,"
           "colorbalance=bs=0.05:rs=-0.03",
    "mystic": "eq=contrast=1.08:saturation=0.94:brightness=-0.01,"
              "colorbalance=bs=0.04",
    "calm": "eq=contrast=1.02:saturation=1.0:brightness=0.03",
}

# Gentle camera moves. The film already moves, so the move only adds intent: a
# slow push or a slight pan, never the aggressive oversize a still needs.
FILM_MOVES: dict[str, str] = {
    "push": ("scale={ow}:{oh},crop={w}:{h}:x='(iw-{w})/2':y='(ih-{h})/2',"
             "zoompan=z='min(1+0.06*on/{n},1.12)':d=1:"
             "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={w}x{h}:fps={fps}"),
    "pull": ("scale={ow}:{oh},crop={w}:{h}:x='(iw-{w})/2':y='(ih-{h})/2',"
             "zoompan=z='max(1.12-0.06*on/{n},1.0)':d=1:"
             "x='iw/2-(iw/zoom/2)':y='ih/2-(ih/zoom/2)':s={w}x{h}:fps={fps}"),
    "pan_r": ("scale={ow}:{oh},crop={w}:{h}:"
              "x='(iw-{w})*min(t/{d},1)':y='(ih-{h})/2'"),
    "pan_l": ("scale={ow}:{oh},crop={w}:{h}:"
              "x='(iw-{w})*(1-min(t/{d},1))':y='(ih-{h})/2'"),
    "tilt_u": ("scale={ow}:{oh},crop={w}:{h}:"
               "x='(iw-{w})/2':y='(ih-{h})*(1-min(t/{d},1))'"),
    "tilt_d": ("scale={ow}:{oh},crop={w}:{h}:"
               "x='(iw-{w})/2':y='(ih-{h})*min(t/{d},1)'"),
}
MOVE_ORDER = ("pan_r", "push", "pan_l", "tilt_u", "pull", "tilt_d")
OVERSIZE = 1.12  # just enough to pan without a black edge

BEATS_PER_CUT = 2
SHOT_MIN, SHOT_MAX = 0.9, 4.2  # a chorus can flash; a verse may hold


def film_by_id(fid: str) -> dict:
    return next(f for f in FILMS if f["id"] == fid)


def film_for_mood(mood: str) -> dict:
    """Cast the film: the first that lists this mood, else a noir default."""
    for f in FILMS:
        if mood in f.get("moods", []):
            return f
    return film_by_id(DEFAULT_FILM)


def film_path(film: dict) -> Path:
    return FILM_DIR / f"{film['id']}-{film['file']}"


def ensure_film(film: dict) -> Path:
    """Download the film once and keep it; it is the raw material for every song."""
    out = film_path(film)
    if out.exists() and out.stat().st_size > 1_000_000:
        return out
    FILM_DIR.mkdir(parents=True, exist_ok=True)
    url = f"https://archive.org/download/{film['ident']}/{film['file']}"
    print(f"  fetching {film['title']} ({film['year']}) from the Internet Archive…",
          file=sys.stderr)
    subprocess.run(["curl", "-sL", "--fail", "-o", str(out), url], check=True)
    return out


def song_sections(slug: str) -> list[tuple[str, float, float]]:
    """[(name, start_frac, len_frac)] over the sung lines, in order.

    Consecutive lines of one section are one block, so a three-chorus song gives
    three chorus blocks at their true share of the song, which is what lets the
    cut tighten exactly on the hook.
    """
    text = (LYRICS / f"{slug}.txt").read_text(encoding="utf-8")
    order: list[str] = []
    section = ""
    for raw in text.splitlines():
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        if line.startswith("[") and line.endswith("]"):
            section = line[1:-1].strip().lower()
            continue
        order.append(section)
    if not order:
        return [("verse", 0.0, 1.0)]
    total = len(order)
    out, i = [], 0
    while i < total:
        sec, j = order[i], i
        while j < total and order[j] == sec:
            j += 1
        out.append((sec, i / total, (j - i) / total))
        i = j
    return out


def window_sections(slug: str, total: float, start: float,
                    length: float) -> list[tuple[str, float, float, float]]:
    """The song's sections clipped to [start, start+length] and rebased to it.

    Returns [(name, energy, local_start, local_len)] in seconds. A hook window
    usually starts inside the first chorus, so the first entry is a partial one.
    """
    out = []
    for name, sf, lf in song_sections(slug):
        s, l = sf * total, lf * total
        a, b = max(s, start), min(s + l, start + length)
        if b - a <= 0.05:
            continue
        out.append((name, SECTION_ENERGY.get(name, 0.5), a - start, b - a))
    if not out:  # a song with no bracketed sections at all
        out = [("verse", 0.5, 0.0, length)]
    return out


def plan_by_section(sections: list[tuple[str, float, float, float]],
                    bpm: float) -> list[tuple[float, float, str, float]]:
    """[(local_start, dur, section, energy)] — a cut plan that follows the song.

    Every section is tiled exactly, and its shot length is scaled by its energy:
    a chorus cuts ~2x faster than the base beat, a verse ~1.4x slower. So the
    picture speeds up and slows down with the song instead of marching to one
    metronome.
    """
    base = 60.0 / max(bpm, 40.0) * BEATS_PER_CUT
    out = []
    for name, energy, lstart, llen in sections:
        scale = 1.0 / max(energy, 0.2)          # high energy -> shorter shots
        target = min(SHOT_MAX, max(SHOT_MIN, base * scale))
        n = max(1, int(round(llen / target)))
        shot = llen / n
        for i in range(n):
            out.append((lstart + i * shot, shot, name, energy))
    return out


def clip_stats(film: Path, start: float, dur: float = 2.0,
               w: int = 160, h: int = 90, ffmpeg: str = "ffmpeg") -> tuple[float, float]:
    """(motion, brightness) of a short clip, decoded straight to numpy.

    Motion is the mean abs frame difference — the same metric the still rail used
    to prove a pan beats a zoom (a still sits near 0.8, live footage near 4-9, a
    hard cut ~20). Brightness matters because old films fade to black between
    reels; a beat cut that lands on black reads as a broken player.
    """
    cmd = [ffmpeg, "-v", "error", "-ss", f"{start:.2f}", "-t", f"{dur:.2f}",
           "-i", str(film), "-vf", f"scale={w}:{h},format=gray",
           "-f", "rawvideo", "-pix_fmt", "gray", "-"]
    raw = subprocess.run(cmd, capture_output=True, check=True).stdout
    a = np.frombuffer(raw, dtype=np.uint8)
    n = a.size // (w * h)
    if n < 3:
        return 0.0, 0.0
    a = a[: n * w * h].reshape(n, h, w).astype(np.float32)
    return float(np.abs(np.diff(a, axis=0)).mean()), float(a.mean())


def sample_film(film: Path, *, samples: int = 64,
                ffmpeg: str = "ffmpeg") -> list[tuple[float, float, float]]:
    """[(motion, brightness, t)] over a grid of the film, black frames dropped."""
    total = _duration(film)
    edge = 3.0
    out = []
    for i in range(samples):
        t = edge + (total - 2 * edge) * (i + 0.5) / samples
        try:
            m, b = clip_stats(film, t, ffmpeg=ffmpeg)
        except subprocess.CalledProcessError:
            continue
        if b < 18:  # a fade-to-black; unusable at any beat
            continue
        out.append((m, b, t))
    return out or [(0.0, 60.0, edge)]


def footage_for_sections(samples: list[tuple[float, float, float]],
                         plan: list[tuple[float, float, str, float]]
                         ) -> list[float]:
    """Pick a film time for every shot, by matching its energy to the footage.

    A chorus wants the film's most active moments; a verse wants its calmer ones.
    Rank the samples by motion x brightness and hand the high-energy shots the top
    of the list and the low-energy shots the bottom, cycling within each band so
    the film is walked through rather than repeated.
    """
    ranked = sorted(samples, key=lambda x: x[0] * x[1], reverse=True)
    lo = max(1, len(ranked) // 3)
    active = ranked[:lo]
    calm = ranked[-lo:] or ranked
    times, ai, ci = [], 0, 0
    for _, _, _, energy in plan:
        if energy >= 0.7:
            times.append(active[ai % len(active)][2])
            ai += 1
        else:
            times.append(calm[ci % len(calm)][2])
            ci += 1
    return times


def _shot_filter(move: str, frames: int, dur: float) -> str:
    ow, oh = int(W * OVERSIZE), int(H * OVERSIZE)
    return FILM_MOVES[move].format(w=W, h=H, ow=ow, oh=oh, n=frames,
                                   d=f"{dur:.3f}", fps=FPS)


def section_grade(mood: str, energy: float) -> str:
    """The mood look, lifted for the hook and held back for the verse.

    A chorus gets a little more contrast, saturation and light than the verse, so
    the hook reads as a change even before the vocal arrives.
    """
    base = MOOD_GRADE.get(mood, MOOD_GRADE["calm"])
    if energy >= 0.9:
        extra = "eq=contrast=1.06:saturation=1.10:brightness=0.03"
    elif energy <= 0.5:
        extra = "eq=contrast=1.02:saturation=0.92:brightness=-0.03"
    else:
        extra = "null"
    return f"{base},{extra}"


def render_shot(film: Path, start: float, move: str, dur: float, out: Path,
                grade: str, ffmpeg: str = "ffmpeg") -> None:
    """Cut one graded, moving shot out of the film at 1080p landscape."""
    frames = max(1, int(round(dur * FPS)))
    vf = (_shot_filter(move, frames, dur)
          + f",scale={W}:{H}:force_original_aspect_ratio=increase"
          + f",crop={W}:{H},{grade},setsar=1,format=yuv420p")
    subprocess.run(
        [ffmpeg, "-y", "-v", "error", "-ss", f"{start:.3f}", "-t", f"{dur:.3f}",
         "-i", str(film), "-vf", vf, "-an", "-r", str(FPS),
         "-c:v", "libx264", "-preset", "veryfast", "-crf", "20", str(out)],
        check=True)


def _cut_card(text: str, sub: str, out: Path) -> None:
    """A Thai title/end card, letterboxed like the film, so it opens and closes right."""
    from PIL import Image, ImageDraw, ImageFilter

    img = Image.new("RGB", (W, H), (8, 8, 12))
    d = ImageDraw.Draw(img)
    for i in range(60):
        c = int(8 + 34 * (1 - abs(i - 30) / 30))
        d.rectangle([0, i * H // 60, W, (i + 1) * H // 60], fill=(c // 3, c // 4, c))
    img = img.filter(ImageFilter.GaussianBlur(10))
    d = ImageDraw.Draw(img)
    f1 = _font(THAI_FONT, 92, bold=True)
    f2 = _font(THAI_FONT, 46)
    tw = d.textlength(text, font=f1)
    d.text(((W - tw) / 2, H / 2 - 150), text, font=f1, fill=(255, 255, 255))
    sw = d.textlength(sub, font=f2)
    d.text(((W - sw) / 2, H / 2 + 20), sub, font=f2, fill=(190, 205, 255))
    img.save(out)


def build(slug: str, *, film_id: str | None = None, seconds: float | None = None,
          full: bool = False, ffmpeg: str = "ffmpeg") -> dict:
    song = SONGS / f"song-{slug}.mp3"
    if not song.exists():
        raise SystemExit(f"no song: {song}")
    meta, _ = load_lyrics(slug)
    mood = meta.get("mood", "calm")
    # A song may name its own film; otherwise the mood casts one.
    fid = film_id or meta.get("film") or film_for_mood(mood)["id"]
    film = film_by_id(fid)
    src = ensure_film(film)

    total = _duration(song)
    if full:
        start, length = 0.0, total
    else:
        sf, lf = chorus_span(slug)
        start, length = sf * total, lf * total
        if seconds:
            length = min(length, seconds)
        length = max(length, 8.0)

    try:
        bpm = float(meta.get("tempo", 90))
    except ValueError:
        bpm = 90.0

    sections = window_sections(slug, total, start, length)
    plan = plan_by_section(sections, bpm)
    samples = sample_film(src, ffmpeg=ffmpeg)
    times = footage_for_sections(samples, plan)

    # Shots live in a per-render directory: the hook and the full cut of the same
    # song share shot filenames, so two renders at once would overwrite each
    # other's frames and produce a corrupt file (moov atom not found).
    tag = "full" if full else "hook"
    work = WORK / f"{slug}-{tag}"
    work.mkdir(parents=True, exist_ok=True)
    shots: list[Path] = []
    for i, ((_, dur, _sec, energy), t) in enumerate(zip(plan, times)):
        move = MOVE_ORDER[i % len(MOVE_ORDER)]
        out = work / f"shot-{i:03d}.mp4"
        render_shot(src, t, move, dur, out, section_grade(mood, energy), ffmpeg=ffmpeg)
        shots.append(out)

    OUT_DIR.mkdir(parents=True, exist_ok=True)
    out = OUT_DIR / (f"film-{slug}.mp4" if full else f"film-{slug}-hook.mp4")

    title = work / "card-title.png"
    endc = work / "card-end.png"
    _cut_card(meta.get("title", slug), release.FOLLOW_ASK, title)
    _cut_card(meta.get("title", slug), release.FOLLOW_PROMISE, endc)

    listfile = work / "concat.txt"
    listfile.write_text("".join(f"file '{p.resolve()}'\n" for p in shots),
                        encoding="utf-8")

    # Concatenate the cut, lay the two cards, add a subtle audio-reactive bar, and
    # mux the song. The film's own audio is never mapped, so no third-party score
    # rides along to be claimed.
    t_fade = 1.5
    fc = (
        f"[0:v]fps={FPS},format=yuv420p[base];"
        f"[1:v]format=rgba,fade=t=in:st=0:d={t_fade}:alpha=1,"
        f"fade=t=out:st={t_fade}:d={t_fade}:alpha=1[tc];"
        f"[2:v]format=rgba,fade=t=in:st=0:d=1.2:alpha=1[ec];"
        f"[base][tc]overlay=0:0:enable='lt(t,{t_fade*2})'[b1];"
        f"[b1][ec]overlay=0:0:enable='gt(t,{length-3.0})'[b2];"
        f"[3:a]showwaves=s={W}x180:mode=cline:colors=0x8affc1|0xff8ad8:"
        f"rate={FPS},format=rgba,colorchannelmixer=aa=0.22[wave];"
        f"[b2][wave]overlay=0:H-220[b3];"
        f"[b3]setsar=1,format=yuv420p[out]"
    )
    subprocess.run(
        [ffmpeg, "-y", "-v", "error",
         "-f", "concat", "-safe", "0", "-i", str(listfile),
         "-loop", "1", "-i", str(title),
         "-loop", "1", "-i", str(endc),
         "-ss", f"{start:.3f}", "-t", f"{length:.3f}", "-i", str(song),
         "-filter_complex", fc, "-map", "[out]", "-map", "3:a",
         "-t", f"{length:.3f}", "-c:v", "libx264", "-preset", "medium",
         "-crf", "20", "-pix_fmt", "yuv420p", "-r", str(FPS),
         "-c:a", "aac", "-b:a", "192k", "-shortest", str(out)],
        check=True)

    return {"slug": slug, "path": str(out), "shots": len(shots),
            "seconds": round(length, 1), "bpm": bpm, "mood": mood,
            "film": film["title"], "credit": film["note"],
            "sections": [s[0] for s in sections], "bytes": out.stat().st_size}


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("slug", nargs="?")
    ap.add_argument("--film", help="force a film id (default: cast by the song's mood)")
    ap.add_argument("--all", action="store_true")
    ap.add_argument("--full", action="store_true")
    ap.add_argument("--seconds", type=float)
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()

    if args.list:
        print("public-domain films (cast by mood):")
        for f in FILMS:
            print(f"  {f['id']:14s} {f['title']} ({f['year']}) moods={','.join(f['moods'])}")
        print("mood grade:", ", ".join(MOOD_GRADE))
        print("camera moves:", ", ".join(FILM_MOVES))
        return 0

    if args.all:
        slugs = sorted(p.stem[len("song-"):] for p in SONGS.glob("song-*.mp3"))
    elif args.slug:
        slugs = [args.slug]
    else:
        ap.error("give a slug or --all")

    for slug in slugs:
        try:
            info = build(slug, film_id=args.film, seconds=args.seconds, full=args.full)
            print(f"{slug}: {info['path']} ({info['shots']} shots, "
                  f"{info['seconds']}s, {info['bpm']:.0f} bpm, {info['mood']}, "
                  f"{info['film']}, sections={'/'.join(info['sections'])})")
        except Exception as e:  # noqa: BLE001
            print(f"{slug}: FAILED {type(e).__name__}: {e}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
