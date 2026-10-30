"""Tests for the music938-1 song pipeline.

Run:  python3 tests/run.py

These are fast, offline checks on the pure logic (parsing, melody, timing, ASS)
plus a few filesystem assertions about what a build produced. They deliberately
do not synthesise audio or run ffmpeg, so the suite stays under a few seconds and
can gate every commit.
"""
from __future__ import annotations

import re
import sys
import unicodedata
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "scripts"))

import common  # noqa: E402
import make_karaoke  # noqa: E402
import make_song  # noqa: E402
import music  # noqa: E402
import audio  # noqa: E402
import tts  # noqa: E402

import numpy as np  # noqa: E402

PASS = 0
FAIL = 0
FAILURES: list[str] = []


def check(name: str, cond: bool, detail: str = "") -> None:
    global PASS, FAIL
    if cond:
        PASS += 1
        print(f"  ok   {name}")
    else:
        FAIL += 1
        FAILURES.append(name)
        print(f"  FAIL {name} {detail}")


def section(title: str) -> None:
    print(f"\n{title}")


def has_thai(s: str) -> bool:
    return any("\u0e00" <= c <= "\u0e7f" for c in s)


def voice_ready() -> bool:
    """True when the Piper Thai voice can phonemise at all.

    `tts.is_speakable` asks Piper whether a syllable has phonemes. The piper
    package is not installed on a fresh sandbox - it belongs to the retired
    synthesis pipeline - so every answer is False, including for `ดี` and `ไป`.
    The speakable checks would then fail on any machine that never installed
    Piper, which is an environment fact and not a lyric defect, so they are
    skipped. The skip prints loudly: a silently skipped check is worse than a
    failing one.
    """
    try:
        return bool(tts._voice_obj().phonemize("ดี"))
    except Exception:
        return False


def skip(name: str) -> None:
    print(f"  skip {name} (Piper voice not installed)")


# --- lyrics ----------------------------------------------------------------

def test_lyrics() -> None:
    section("lyrics")
    files = sorted(common.LYRICS.glob("*.txt"))
    check("20 lyric files exist", len(files) == 20, f"found {len(files)}")
    slugs = set()
    for p in files:
        meta = make_song.parse_lyrics(p)
        slug = p.stem
        check(f"{slug}: has TITLE", bool(meta.get("title")))
        check(f"{slug}: title is Thai", has_thai(meta.get("title", "")))
        check(f"{slug}: has KEY", bool(meta.get("key")))
        check(f"{slug}: mood known", meta.get("mood", "").lower() in music.MOODS,
              meta.get("mood"))
        secs = meta["sections"]
        check(f"{slug}: has verse and chorus",
              any(s["name"] == "verse" for s in secs)
              and any(s["name"] == "chorus" for s in secs))
        n_lines = sum(len(s["lines"]) for s in secs)
        check(f"{slug}: 18-45 lines", 18 <= n_lines <= 45, f"{n_lines}")
        # No Latin letters in sung lines: the voice is Thai-only.
        bad = [l for s in secs for l in s["lines"] if re.search(r"[A-Za-z]", l)]
        check(f"{slug}: no Latin in lyrics", not bad, str(bad[:1]))
        slugs.add(slug)
    check("all slugs unique", len(slugs) == len(files))


# --- tokenizer -------------------------------------------------------------

def test_tokenizer() -> None:
    section("tokenizer")
    toks = make_song._tokenize("คนดีที่จากไป ไม่มีวันหวนคืน")
    text = "".join(t["text"] for t in toks)
    check("tokens rejoin to the line",
          text == "คนดีที่จากไป ไม่มีวันหวนคืน", repr(text))
    check("one space token", sum(1 for t in toks if t["space"]) == 1)
    check("spaces carry no sound", all(t["text"] == " " for t in toks if t["space"]))
    check("no leading/trailing space token",
          not toks[0]["space"] and not toks[-1]["space"])
    empty = make_song._tokenize("")
    check("empty line -> no tokens", empty == [])


# --- music theory ----------------------------------------------------------

def test_music() -> None:
    section("music")
    root, scale = music.parse_key("Am")
    check("A minor root", root % 12 == 9, str(root))
    check("minor scale", scale == music.MINOR)
    root2, scale2 = music.parse_key("C")
    check("C major root", root2 % 12 == 0)
    check("major scale", scale2 == music.MAJOR)

    chords = music.progression(root, scale, [0, 5, 3, 4], 8)
    check("progression length", len(chords) == 8)
    check("chords are triads", all(len(c.notes) == 3 for c in chords))
    check("chord notes ascend", all(c.notes == sorted(c.notes) for c in chords))

    # The tonic triad on a minor key is minor: 3 semitones to the third.
    i = music.diatonic(root, scale, 0)
    check("i is a minor triad", (i[1] - i[0]) % 12 == 3, str(i))

    import random
    rng = random.Random(7)
    notes, deg = music.melody_for_line(rng, root, scale, chords[0], 8, 4.0, None)
    check("one note per syllable", len(notes) == 8)
    check("notes fit the line length", abs(sum(b for _, b in notes) - 4.0) < 1e-6)
    check("notes are positive", all(m > 0 and b > 0 for m, b in notes))
    check("degree returned", isinstance(deg, int))


# --- line sizing -----------------------------------------------------------

def test_duration_target() -> None:
    section("duration target (3.5-5 min)")
    for p in sorted(common.LYRICS.glob("*.txt")):
        meta = make_song.parse_lyrics(p)
        mood = meta.get("mood", "calm").lower()
        tempo = float(meta.get("tempo") or music.MOODS[mood]["tempo"])
        spb = 60.0 / tempo
        n_lines = sum(len(s["lines"]) for s in meta["sections"])
        lb = make_song._auto_line_beats(n_lines, spb)
        total = n_lines * lb * spb + 34.0
        check(f"{p.stem}: 210-300s", 210.0 <= total <= 300.0, f"{total:.0f}s")


# --- ASS karaoke -----------------------------------------------------------

def test_thai_font() -> None:
    section("Thai font (WIRING: tofu-box lyric bug)")
    # libass draws a Thai syllable as a box when the style's font is absent, and
    # the clip still plays, so nothing downstream notices. The font must be
    # bundled and must actually reach the ass filter.
    font_path = make_karaoke.FONTS_DIR / "NotoSansThai.ttf"
    bundled = font_path.is_file()
    check("font is bundled", bundled, str(font_path))
    # ass_filter raises when the font is gone, which is the point of it, but a
    # raise here would abort the whole suite instead of failing one check.
    try:
        filt = make_karaoke.ass_filter(Path("/tmp/x.ass"))
    except FileNotFoundError as exc:
        filt = ""
        check("ass filter builds with the bundled font", False, str(exc))
    else:
        check("ass filter builds with the bundled font", True)
    check("ass filter passes fontsdir", "fontsdir=" in filt, filt)
    check("ass filter points at the bundle",
          str(make_karaoke.FONTS_DIR) in filt, filt)
    # The render style must name the family the bundled font declares, or libass
    # picks a different face and falls back to boxes anyway.
    check("style names Noto Sans Thai", "Noto Sans Thai" in make_karaoke.FONT)
    if not bundled:
        return
    # A Thai glyph must survive a real rasterise through the bundled file. If
    # the font lost its Thai block, the mask would be empty or a solid block.
    import numpy as np
    from PIL import Image, ImageDraw, ImageFont
    font = ImageFont.truetype(str(font_path), 64)
    img = Image.new("L", (600, 120), 0)
    ImageDraw.Draw(img).text((10, 20), "คนดี", font=font, fill=255)
    mask = np.asarray(img) > 128
    check("Thai glyphs rasterise", mask.sum() > 300, f"{int(mask.sum())} px")
    # A tofu box is a solid rectangle: every inked row would be the same width.
    # Thai text has a tall ascender row and a thin tone-mark row above it, so the
    # run of distinct row widths must be wider than a box's flat profile.
    row_w = mask.sum(1)
    inked = row_w[row_w > 0]
    distinct = len(set(inked.tolist()))
    check("glyphs are not boxes", distinct >= 6, f"{distinct} distinct row widths")


def test_ass() -> None:
    section("ASS karaoke")
    timed = [
        {"text": "สวัสดี โลก", "start": 1.0, "end": 3.0},
    ]
    meta = {"title": "ทดสอบ", "subtitle": "ทดสอบ"}
    ass = make_karaoke.build_ass(timed, meta, 200.0)
    check("has Script Info", "[Script Info]" in ass)
    check("has Events", "[Events]" in ass)
    check("uses karaoke tag", "\\kf" in ass)
    check("title present", "ทดสอบ" in ass)
    check("lyric present", "สวัสดี" in ass and "โลก" in ass)
    # Two words over 2.0s, weighted by length: the sweep must total 200cs.
    total = sum(int(m) for m in re.findall(r"\\kf(\d+)", ass))
    check("sweep covers the line", total == 200, f"{total}cs")
    check("PlayResX 1920", "PlayResX: 1920" in ass)
    # Braces and backslashes in lyric text must be escaped or libass eats them.
    esc = make_karaoke.build_ass([{"text": "a{b}\\c", "start": 0.0, "end": 1.0}],
                                 {"title": "t"}, 100.0)
    check("braces escaped", "\\{b\\}" in esc and "\\\\c" in esc)


def test_karaoke_estimate() -> None:
    section("karaoke line timing")
    lines = ["หนึ่ง", "สอง สาม สี่"]
    timed = make_karaoke.estimate(lines, 200.0)
    check("one entry per line", len(timed) == 2)
    check("starts after the lead-in", timed[0]["start"] >= make_karaoke.LEAD)
    check("ends before the tail",
          timed[-1]["end"] <= 200.0 - make_karaoke.TAIL + 1e-6)
    check("lines do not overlap", timed[0]["end"] <= timed[1]["start"] + 1e-6)
    check("longer line gets more time",
          (timed[1]["end"] - timed[1]["start"]) > (timed[0]["end"] - timed[0]["start"]))
    check("empty input is safe", make_karaoke.estimate([], 200.0) == [])


def test_lyrics_parse() -> None:
    section("lyrics file parsing")
    meta, lines = make_karaoke.load_lyrics("01-khon-di-thi-chak-pai")
    check("title read", bool(meta.get("title")), str(meta.get("title")))
    check("title is Thai", has_thai(meta.get("title", "")))
    check("sung lines found", len(lines) > 10, f"{len(lines)}")
    # Section tags and blank lines must not leak into the lyric lines.
    check("no section tags in lines", not any(l.startswith("[") for l in lines))
    check("all lines are Thai", all(has_thai(l) for l in lines))
    # An intro/outro is instrumental, so its (empty) body is not a lyric line.
    check("no header lines in body", not any(l.startswith("#") for l in lines))


# --- rendered output -------------------------------------------------------

def test_outputs() -> None:
    section("rendered output")
    songs = sorted((common.LIBRARY / "songs").glob("song-*.mp3"))
    if not songs:
        # Nothing built yet (the producer is still rendering): an empty pack is
        # expected, not a failure.
        print("  skip (no songs built yet)")
        return
    for song in songs:
        slug = song.stem.removeprefix("song-")
        kara = common.LIBRARY / "songs" / f"karaoke-{slug}.mp3"
        cover = common.LIBRARY / "covers" / f"cover-{slug}.jpg"
        video = common.LIBRARY / "karaoke" / f"karaoke-{slug}.mp4"
        check(f"{slug}: karaoke exists", kara.exists())
        check(f"{slug}: cover exists", cover.exists())
        # The video is rendered separately and may lag the audio, so its
        # absence is reported but does not fail the audio deliverable.
        if not video.exists():
            print(f"  note {slug}: karaoke video not rendered yet")
        # The pack's brief is 3.5-5 min. A take under the floor is a real defect
        # in the deliverable, not a test artefact - song 01's is 178.7s and the
        # generator caps takes near 3:00, so this stays red until generation
        # produces a longer take. It is reported rather than skipped, because the
        # gap is exactly what K needs to see.
        dur = common.duration(song)
        check(f"{slug}: duration in 3.5-5 min", 210 <= dur <= 300, f"{dur:.1f}s")
        if kara.exists():
            kd = common.duration(kara)
            check(f"{slug}: karaoke same length as song", abs(kd - dur) < 1.0,
                  f"{kd:.1f}s vs {dur:.1f}s")


# --- regression: syllable repair -------------------------------------------

def test_syllable_repair() -> None:
    section("syllable repair (WIRING: silent-syllable bug)")
    # pythainlp splits these inside a vowel cluster; every part must be speakable.
    # The rejoin assertion is pure string work and always runs; the speakable half
    # needs the Piper voice, which a fresh sandbox does not have.
    have_voice = voice_ready()
    for word in ["เปียกชื้น", "ไขว่คว้า", "ขวักไขว่", "ตั๋วรถคันสุดท้าย"]:
        parts = tts.syllabify(word)
        check(f"{word}: rejoins intact", "".join(parts) == word, str(parts))
        if have_voice:
            bad = [p for p in parts if not tts.is_speakable(p)]
            check(f"{word}: all parts speakable", not bad, str(bad))
        else:
            skip(f"{word}: all parts speakable")
    # A plain word must not be fragmented: the repair only merges.
    plain = tts.syllabify("คิดถึงเธอทุกคืน")
    check("plain word keeps its syllables", plain == ["คิด", "ถึง", "เธอ", "ทุก", "คืน"],
          str(plain))
    # The untranscribable repeat mark is dropped from sung tokens.
    toks = make_song._tokenize("เบา ๆ")
    check("repeat mark dropped", "".join(t["text"] for t in toks) == "เบา",
          repr("".join(t["text"] for t in toks)))
    # Every lyric syllable in the pack must be speakable.
    if not have_voice:
        skip("every lyric syllable is speakable")
        return
    unspeakable = set()
    for p in sorted(common.LYRICS.glob("*.txt")):
        for raw in p.read_text(encoding="utf-8").splitlines():
            line = raw.strip()
            if not line or line.startswith("#") or line.startswith("["):
                continue
            for chunk in line.split(" "):
                chunk = chunk.strip("ๆ").strip()
                if not chunk:
                    continue
                for syl in tts.syllabify(chunk):
                    if not tts.is_speakable(syl):
                        unspeakable.add(syl)
    check("every lyric syllable is speakable", not unspeakable, str(sorted(unspeakable)))


# --- regression: karaoke must not out-shout the song ------------------------

def test_normalize_floor() -> None:
    section("vocal normalisation (WIRING: karaoke louder than song)")
    # A sparse track: loud bursts separated by silence.
    x = np.zeros(22050 * 4, dtype=np.float32)
    for i in range(0, 4):
        x[i * 22050 + 1000:i * 22050 + 2000] = 0.5
    plain = audio.normalize(x, 0.12)
    floored = audio.normalize(x, 0.12, floor=True)
    # The floored version must be quieter overall (it measures the bursts, not
    # the silence), which is what keeps the vocal from swamping the backing.
    check("floored gain is smaller", audio.rms(floored) < audio.rms(plain),
          f"{audio.rms(floored):.4f} vs {audio.rms(plain):.4f}")
    check("floored track still has signal", audio.rms(floored) > 1e-4)
    # A fully silent track must not blow up.
    z = audio.normalize(np.zeros(1000, dtype=np.float32), 0.1, floor=True)
    check("silence stays silent", audio.rms(z) == 0.0)


def test_level_ordering() -> None:
    section("level ordering (song vs karaoke)")
    songs = sorted((common.LIBRARY / "songs").glob("song-*.mp3"))
    if not songs:
        print("  skip (no songs built yet)")
        return
    for song in songs:
        slug = song.stem.removeprefix("song-")
        kara = common.LIBRARY / "songs" / f"karaoke-{slug}.mp3"
        if not kara.exists():
            continue
        s, k = common.integrated_lufs(song), common.integrated_lufs(kara)
        if s is None or k is None:
            continue
        # The karaoke is normalised to -16 LUFS; the song should sit at least
        # as loud, so the instrumental is never louder than the vocal mix.
        check(f"{slug}: karaoke not louder than song", k <= s + 0.5,
              f"song {s} karaoke {k}")


def test_shorts() -> None:
    section("shorts (discovery rail)")
    import make_short
    # The hook must land on the chorus, not the intro. Song 01's first chorus
    # begins at ~20% of the sung lines; a wrong section model would put it at 0.
    start_frac, len_frac = make_short.chorus_span("01-khon-di-thi-chak-pai")
    check("hook starts past the intro", start_frac > 0.05, f"{start_frac:.3f}")
    check("hook is a real block", len_frac > 0.05, f"{len_frac:.3f}")
    # A song has three choruses, and each is a separate hook - so three Shorts,
    # not one per sung line and not one per song.
    spans = make_short.chorus_spans("01-khon-di-thi-chak-pai")
    check("three chorus hooks", len(spans) == 3, str(len(spans)))
    check("hooks are in order", all(spans[i][0] < spans[i + 1][0]
                                    for i in range(len(spans) - 1)))
    # A Short must stay under the 60s ceiling whatever the song length is.
    for dur in (150.0, 178.7, 300.0):
        for _, length in make_short._pick_windows("01-khon-di-thi-chak-pai", dur):
            check(f"short <= 60s at {dur:.0f}s song", length <= 60.0, f"{length:.1f}")
    # Vertical canvas, or YouTube will not treat it as a Short.
    check("vertical canvas", (make_short.W, make_short.H) == (1080, 1920))


def main() -> int:
    test_lyrics()
    test_tokenizer()
    test_music()
    test_duration_target()
    test_thai_font()
    test_ass()
    test_karaoke_estimate()
    test_lyrics_parse()
    test_syllable_repair()
    test_normalize_floor()
    test_level_ordering()
    test_shorts()
    test_outputs()
    print(f"\n{PASS} passed, {FAIL} failed")
    if FAILURES:
        print("failed: " + ", ".join(FAILURES[:10]))
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
