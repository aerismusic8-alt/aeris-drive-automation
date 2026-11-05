"""Tests for the music938-1 song pipeline.

Run:  python3 tests/run.py

These are fast, offline checks on the pure logic (parsing, melody, timing, ASS)
plus a few filesystem assertions about what a build produced. They deliberately
do not synthesise audio or run ffmpeg, so the suite stays under a few seconds and
can gate every commit.
"""
from __future__ import annotations

import json
import os
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
    # K, 2026-11-01: the catalogue is no longer capped at 20 songs. The floor
    # stays (the first pack), but there is no ceiling, so a new batch never
    # breaks the suite.
    check("at least 20 lyric files", len(files) >= 20, f"found {len(files)}")
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
    section("ASS overlay")
    timed = [
        {"text": "สวัสดี โลก", "start": 1.0, "end": 3.0},
    ]
    meta = {"title": "ทดสอบ", "subtitle": "ทดสอบ"}
    # Default: songs only, no burned text at all (K, 2026-11-04).
    ass = make_karaoke.build_ass(timed, meta, 200.0)
    check("has Script Info", "[Script Info]" in ass)
    check("has Events", "[Events]" in ass)
    check("PlayResX 1920", "PlayResX: 1920" in ass)
    check("no dialogue by default", "Dialogue:" not in ass)
    check("no lyric text by default", "สวัสดี" not in ass)
    check("no title card by default", "ทดสอบ" not in ass)

    # The old behaviour stays behind captions=True for a deliberate re-render.
    cap = make_karaoke.build_ass(timed, meta, 200.0, captions=True)
    check("uses karaoke tag when asked", "\\kf" in cap)
    check("lyric present when asked", "สวัสดี" in cap and "โลก" in cap)
    # Two words over 2.0s, weighted by length: the sweep must total 200cs.
    total = sum(int(m) for m in re.findall(r"\\kf(\d+)", cap))
    check("sweep covers the line", total == 200, f"{total}cs")
    # Braces and backslashes in lyric text must be escaped or libass eats them.
    esc = make_karaoke.build_ass([{"text": "a{b}\\c", "start": 0.0, "end": 1.0}],
                                 {"title": "t"}, 100.0, captions=True)
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

def test_affiliate_short() -> None:
    """The affiliate card must be honest, attributable, and positioned.

    Three failures this pins, each of which costs money or a channel:
      * a card that makes a claim we cannot back ("รวยแน่นอน", "ทดลองใช้แล้ว")
        breaches Shopee's affiliate terms and Thai ad law;
      * a card whose link is not the *surface's* tracking link loses the
        attribution, so the click is invisible and looks like "no interest";
      * a card whose five text lines all land on the same anchor overprints
        into an unreadable smear — the exact bug the first render had.
    """
    section("affiliate short")
    import make_affiliate_short as aff

    products = aff.load_products()
    check("product cards exist", len(products) >= 5, f"{len(products)}")
    for p in products:
        check(f"{p['id']}: no banned claim", aff.claim_problem(p) is None,
              str(aff.claim_problem(p)))
        check(f"{p['id']}: has a song", bool(p.get("song")))
        check(f"{p['id']}: has bullets", len(p.get("bullets", [])) >= 2)
        # Shorts are decided in the first 3 seconds, so the burned opening line
        # is a scroll-stopper, distinct from the topic title.
        check(f"{p['id']}: has a hookline", bool(p.get("hookline")))
        check(f"{p['id']}: hookline is Thai", has_thai(p.get("hookline", "")))
        check(f"{p['id']}: hookline differs from the title",
              p.get("hookline") != p.get("title"))

    # The link is resolved per surface, not stored on the card: a card that
    # stored one link would tag every sale to the same surface.
    check("cards do not hard-code a url", all("url" not in p for p in products))
    import monetize
    monetize.CACHE = None
    tk = aff.caption(products[0], "tiktok")
    fb = aff.caption(products[0], "facebook")
    yt = aff.caption(products[0], "youtube")
    check("tiktok caption carries the tiktok link",
          monetize.link("tiktok") in tk)
    check("facebook caption carries the facebook link",
          monetize.link("facebook") in fb)
    check("youtube caption carries the youtube link",
          monetize.link("youtube") in yt)
    for name, cap in (("tiktok", tk), ("facebook", fb), ("youtube", yt)):
        check(f"{name} caption discloses the affiliate link",
              "ลิงก์พันธมิตร" in cap)
        check(f"{name} caption has Thai", has_thai(cap))
        check(f"{name} caption is not over-long",
              len(cap) <= 400, f"{len(cap)}")

    # The card's text must be positioned, or libass overprints every line.
    ass = aff.build_ass(products[0], 58.0)
    dialogue = [ln for ln in ass.splitlines() if ln.startswith("Dialogue:")]
    check("card draws hook + 3 bullets + cta + disclosure",
          len(dialogue) >= 5, f"{len(dialogue)}")
    check("every card line is positioned",
          all("\\pos(" in ln for ln in dialogue))
    ys = [int(re.search(r"\\pos\(\d+,(\d+)\)", ln).group(1)) for ln in dialogue]
    check("card lines do not share a y", len(set(ys)) == len(ys), f"{ys}")
    check("card lines are inside the frame", all(0 < y < aff.H for y in ys))
    check("disclosure is drawn on the card",
          "ลิงก์พันธมิตร" in ass)
    check("the opening line drawn is the hookline",
          products[0]["hookline"] in ass)
    check("no emoji in the burned text",
          not any(0x1F300 <= ord(c) <= 0x1FAFF for c in ass))
    monetize.CACHE = None


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


def test_provenance() -> None:
    section("provenance (WIRING: retired Piper engine must not ship)")
    import provenance
    # The gate is the left/right channel difference: make_song.py copies one mono
    # signal into both channels, so its files are bit-identical, while a real
    # Flow Music mix never is. Pin the threshold, not an audio file.
    check("mono epsilon is exact", provenance.MONO_EPSILON == 1e-6)
    # A file whose channels are identical must read as retired; a real stereo
    # pair must not. This is the whole decision, so test it directly.
    identical = np.stack([np.linspace(-0.5, 0.5, 4096)] * 2, axis=1).astype(np.float32)
    differing = np.stack([np.linspace(-0.5, 0.5, 4096),
                          np.linspace(-0.5, 0.5, 4096) * 0.5], axis=1).astype(np.float32)
    check("identical channels are retired",
          float(np.abs(identical[:, 0] - identical[:, 1]).max()) <= provenance.MONO_EPSILON)
    check("real stereo is not retired",
          float(np.abs(differing[:, 0] - differing[:, 1]).max()) > provenance.MONO_EPSILON)
    # The retired engine is fenced off: neither entry point may run it by default.
    for script in ("make_song.py", "build_all.py"):
        text = (ROOT / "scripts" / script).read_text(encoding="utf-8")
        check(f"{script}: refuses the retired engine by default",
              "--retired-engine" in text and "return 2" in text)
    # One manifest schema, or the index page breaks. Readers (pack_index,
    # build_all, provenance) all use "entries"; the writer must match.
    writer = (ROOT / "scripts" / "manifest.py").read_text(encoding="utf-8")
    check("manifest writer uses the entries key", '"entries": entries' in writer)
    if (ROOT / "library" / "songs" / "manifest.json").exists():
        data = json.loads((ROOT / "library" / "songs" / "manifest.json").read_text(encoding="utf-8"))
        check("manifest on disk is readable by the readers",
              "entries" in data and all("id" in e for e in data["entries"]))


def test_genres() -> None:
    section("genres (WIRING: catalogue is open, any genre)")
    import genres
    # K, 2026-11-01: unlimited songs, any genre. Every genre in the plan needs a
    # Flow Music style and a Thai tagline, or a new song in it ships with the
    # wrong sound or an empty tagline.
    for g in genres.genres():
        check(f"{g['id']}: has a style", bool(g.get("style", "").strip()))
        check(f"{g['id']}: has a tagline", bool(g.get("tagline", "").strip()))
        check(f"{g['id']}: has hashtags", bool(g.get("hashtags")))
        check(f"{g['id']}: plans at least one song", int(g.get("planned", 0)) >= 1)
    # A genre must not borrow the retired Piper engine's sound; the style is a
    # Flow Music prompt and must stay free of the offline engine's markers.
    for g in genres.genres():
        check(f"{g['id']}: style is not a Piper prompt",
              "piper" not in g["style"].lower() and "tts" not in g["style"].lower())
    # The first 20 songs have no GENRE header and must keep working off MOOD.
    check("genre_of on a header-less song is None",
          genres.genre_of("01-khon-di-thi-chak-pai") is None)
    # An unknown genre id must not crash; it falls back to the caller's default.
    check("unknown genre returns None", genres.genre_of("does-not-exist") is None)
    # The plan is internally consistent: unique ids, a name in both languages.
    ids = [g["id"] for g in genres.genres()]
    check("genre ids are unique", len(ids) == len(set(ids)))
    for g in genres.genres():
        check(f"{g['id']}: has Thai and English names",
              bool(g.get("name_th")) and bool(g.get("name_en")))
    # Every genre maps to a real cover palette, so a new genre needs no new art.
    from covers import PALETTES
    for g in genres.genres():
        check(f"{g['id']}: maps to a known palette",
              genres.PALETTE_FOR.get(g["id"]) in PALETTES)


def test_thumb_contrast() -> None:
    """A thumbnail must not be flat.

    Measured 2026-10-30 against 12 top competitor thumbnails: their luminance
    standard deviation spans 21.7-80.1, while ours measured 13.4-23.9 - every
    frame we had was at the bottom of that range, which is why they disappear in
    a feed. The floor here is the competitor minimum, not a style opinion.
    """
    section("thumbnail contrast (competitor floor)")
    from PIL import Image, ImageStat
    floor = 21.7
    made = sorted((ROOT / "library" / "thumbs").glob("thumb-song-*.png"))
    if not made:
        skip("no thumbnails on disk yet")
        return
    worst = None
    for p in made:
        im = Image.open(p).convert("L").resize((64, 36))
        sd = ImageStat.Stat(im).stddev[0]
        if worst is None or sd < worst[1]:
            worst = (p.name, sd)
    check(f"every song thumbnail has spread >= {floor}", worst[1] >= floor,
          f"worst {worst[0]} std={worst[1]:.1f}")
    covers = sorted((ROOT / "library" / "covers").glob("*.jpg"))
    if covers:
        sds = [ImageStat.Stat(Image.open(p).convert("L").resize((64, 36))).stddev[0]
               for p in covers]
        check(f"every cover has spread >= {floor}", min(sds) >= floor,
              f"min std={min(sds):.1f}")


def test_titles() -> None:
    """Release titles must fit the shape the competitor scan says wins.

    Of 1,546 scanned videos, the ones past 100k views averaged 47.9 characters
    and used `|` in 8% of titles; the sub-1k ones averaged 60.7 and used `|` in
    38.9%. YouTube truncates past ~60 characters, so a long title hides its own
    tail. This pins the fix: no `| AERIS Music` suffix, and under 60 characters.
    """
    section("release titles (competitor shape)")
    import release
    slug = "01-khon-di-thi-chak-pai"
    for kind, variant in (("song", ""), ("karaoke", ""),
                          ("short", "short-song-h1-01-khon-di-thi-chak-pai"),
                          ("short", "")):
        title, _desc, _tags = release.describe(slug, kind, variant)
        check(f"{kind}/{variant or 'plain'} title <= 60 chars", len(title) <= 60,
              f"{len(title)}: {title}")
        check(f"{kind}/{variant or 'plain'} title has no brand suffix",
              "AERIS Music" not in title, title)
    # The Short must still be discoverable as a Short.
    st, _, _ = release.describe(slug, "short", "")
    check("short title carries #Shorts", "#Shorts" in st, st)


def test_compilation() -> None:
    """A compilation's title and chapters are the watch-hour lever.

    `เลือกเพลงฟังได้` is the strongest signal in the scan (37 winner titles, 0
    loser titles). It only holds if the description carries timestamps, so both
    the phrase and the chapter list are checked, and the thin-catalogue guard is
    checked so a 1-song "compilation" can never ship.
    """
    section("compilation (watch-hour lever)")
    import compile_album
    title = compile_album.compilation_title("รวมเพลงไทยเพื่อชีวิต", 24)
    check("title carries เลือกเพลงฟังได้", "เลือกเพลงฟังได้" in title, title)
    check("title states the track count", "24 เพลง" in title, title)
    check("title fits 60 chars", len(title) <= 60, f"{len(title)}")
    check("a 12-song floor is enforced", compile_album.MIN_TRACKS >= 12,
          str(compile_album.MIN_TRACKS))
    desc = compile_album.compilation_description(
        "รวมเพลงไทยเพื่อชีวิต", ["01-khon-di-thi-chak-pai"])
    check("description carries a 00:00 chapter", "\n00:00 " in desc, desc[:50])
    # render() used to rewrite the description as a bare tracklist, which
    # silently dropped the timestamps the title promises. It must keep chapters.
    render_body = (ROOT / "scripts" / "compile_album.py").read_text().split(
        "def render(", 1)[1].split("\ndef ", 1)[0]
    check("render keeps the chaptered description",
          "compilation_description" in render_body)


def test_flow_extend_kinds() -> None:
    """An Extend renders as `audio__render_edit`, not `audio__extend_song`.

    Flow re-renders the whole take when a section is appended, so waiting only
    for `audio__extend_song` never saw a completed extend and every song stayed
    under the 3.5-minute floor (the old "16 creates, 0 extends" note). This is a
    source check because driving the real panel needs the signed-in desktop.
    """
    section("Flow extend clip kind (WIRING: short-take bug)")
    src = (ROOT / "scripts" / "flow_song.py").read_text()
    body = src.split("def _extend(", 1)[1].split("\ndef ", 1)[0]
    check("extend waits for audio__render_edit", "audio__render_edit" in body)


def test_market_report() -> None:
    """The marketing brief must diff two readings and stay Thai.

    `market.py` is the measurement half of the continuous marketing loop; it runs
    daily with no LLM. These checks pin the two things that would silently break
    it: the delta against the previous snapshot, and the report being Thai.
    """
    section("marketing report (market.py)")
    import market
    prev = {"channel_stats": {"subs": 10, "views": 100, "videos": 4},
            "videos": {"a": {"views": 5}}}
    cur = market.build_snapshot("ch3",
                                {"subs": 15, "views": 130, "videos": 6},
                                [{"video_id": "a", "slug": "01", "kind": "short",
                                  "public": True, "title": "คนดีที่จากไป", "views": 40,
                                  "likes": 3, "comments": 0},
                                 {"video_id": "b", "slug": "02", "kind": "song",
                                  "public": True, "title": "รักที่ไม่มีวันจบ", "views": 2,
                                  "likes": 0, "comments": 0}])
    report = market.render_report(prev, cur)
    check("report is Thai", any("\u0e00" <= c <= "\u0e7f" for c in report))
    check("report shows the growth (+35)", "+35" in report)
    check("report shows the subscriber delta (+5)", "+5" in report)
    check("report lists the moving video first", report.index("คนดีที่จากไป")
          < report.index("รักที่ไม่มีวันจบ"))
    check("report names the monetization target", "1,000" in report and "4,000" in report)


def test_market_plugin_wiring() -> None:
    """The daily plugin must run market.py and commit the report back.

    A source check, because driving the real automation needs the cloud. If the
    driver path or the commit list drifts, the loop stops recording with no
    visible error — which is exactly the failure mode this pins.
    """
    section("marketing plugin wiring (market-daily)")
    src = (ROOT.parent / "plugins" / "market-daily" / "scripts" / "main.py").read_text()
    check("runs market.py", "market.py" in src)
    check("passes the repo root", '"--root"' in src)
    check("commits the report back", "market-report.md" in src)
    check("commits the snapshot back", "market-snapshot.json" in src)
    check("refreshes the promo site", "ar_promo_site.py" in src)


def test_market_root_resolution() -> None:
    """`market.py` must find the ledger whether --root is the repo or the tree.

    The daily plugin passes the repo root; run by hand the base is music938-1.
    Resolving the wrong one reads <repo>/work/release-state.json, which does not
    exist, so the report silently tracks zero videos and still exits 0 — the
    marketing loop then reports an empty channel every day.
    """
    section("marketing root resolution (market.py)")
    import market
    repo = ROOT.parent
    check("repo root -> music938-1", market.resolve_root(repo) == repo / "music938-1")
    check("tree itself -> unchanged", market.resolve_root(ROOT) == ROOT)
    check("ledger exists under the resolved root",
          (market.resolve_root(repo) / "work" / "release-state.json").exists())


def test_crosspost_engine() -> None:
    """The FB/TikTok rail must queue every Short and caption it in Thai.

    Offline checks only: the real post needs the signed-in desktop, so this pins
    the queue build, the per-platform caption and the posted-once guard.
    """
    section("crosspost rail (Facebook Reels + TikTok)")
    import crosspost

    q = crosspost.build_queue()
    shorts = list((ROOT / "library" / "shorts").glob("short-*.mp4"))
    aff = list((ROOT / "library" / "affiliate").glob("short-aff-*.mp4"))
    if not shorts:
        print("  skip (no shorts rendered yet)")
        return
    # Both content types are queued: the song Shorts and the affiliate product
    # cards, each on both platforms. A product card that never reaches the queue
    # is a clip nobody ever sees.
    check("every short is queued on both platforms",
          len(q) == (len(shorts) + len(aff)) * 2,
          f"{len(q)} vs ({len(shorts)}+{len(aff)})*2")
    check("ids are unique", len({it["id"] for it in q}) == len(q))

    t = next(it for it in q if it["platform"] == "tiktok")
    f = next(it for it in q if it["platform"] == "facebook")
    check("tiktok caption carries #fyp", "#fyp" in t["caption"])
    check("facebook caption has no #fyp", "#fyp" not in f["caption"])
    for it in (t, f):
        check(f"{it['platform']}: caption is Thai",
              any("\u0e00" <= ch <= "\u0e7f" for ch in it["caption"]))
        check(f"{it['platform']}: slug resolves to a real short",
              (ROOT / it["video"]).exists())

    # An affiliate card is captioned by the affiliate module, not the song
    # caption: it must carry the affiliate link and the disclosure, and be
    # marked as an affiliate item so it can be told apart in the queue.
    aff_items = [it for it in q if it.get("kind") == "affiliate"]
    if aff:
        check("affiliate cards are queued on both platforms",
              len(aff_items) == len(aff) * 2, f"{len(aff_items)}")
        check("affiliate caption carries the surface link",
              all("s.shopee.co.th" in it["caption"] for it in aff_items))
        check("affiliate caption discloses the link",
              all("ลิงก์พันธมิตร" in it["caption"] for it in aff_items))

    # A posted item must never come back as pending.
    state = {"posted": {t["id"]: {"at": "x", "url": "y"}}}
    left = crosspost.pending(q, state, "tiktok")
    check("posted items are excluded", t["id"] not in {it["id"] for it in left})
    check("facebook still pending",
          len(left) == len(shorts) + len(aff) - 1,
          f"{len(left)}")

    # A product card must not sit behind the whole song backlog: at DAILY_CAP a
    # surface would not reach one for ~11 days. The build folds a card pair in
    # after every 4 items, so the first affiliate item is early in the queue.
    if aff_items:
        first_aff = min(i for i, it in enumerate(q) if it.get("kind") == "affiliate")
        check("the first affiliate card is near the front of the queue",
              first_aff <= 8, f"index {first_aff}")
        # Interleaving must not drop or duplicate anything.
        check("interleaving keeps every item exactly once",
              len({it["id"] for it in q}) == len(q))

    # A stored post URL carries tracking params, so the readback must compare on
    # the stable /reel/<id> part or it returns the previous post every run.
    seen = crosspost._posted_urls({
        "posted": {
            "a": {"url": "https://www.facebook.com/reel/111/?notif_id=9&ref=notif"},
            "b": {"url": "https://www.tiktok.com/@x/video/222?lang=th"},
            "c": {"url": ""},
        }
    })
    check("posted urls are reduced to stable ids",
          seen == {"/reel/111", "/video/222"}, str(sorted(seen)))

    # Facebook must post to the Page, not the personal profile. The plain
    # `facebook.com/reels/create/` composer posts as the person, and the 60 Reels
    # sent before the Page existed landed there — so the Page rail needs both a
    # Page-scoped composer and a state key that does not count those old posts.
    fb = crosspost.PLATFORMS["facebook"]
    check("facebook posts through the Business Suite Page composer",
          "business.facebook.com" in fb["upload"] and "asset_id=" in fb["upload"])
    check("facebook composer is not the personal reels route",
          "facebook.com/reels/create/" not in fb["upload"])
    check("facebook state key differs from the platform name",
          fb["state_key"] != "facebook" and fb["state_key"].startswith("facebook"))
    check("facebook ids carry the distinct state key",
          all(it["id"].startswith("facebook-page:") for it in q if it["platform"] == "facebook"))

    src = (ROOT / "scripts" / "crosspost.py").read_text()
    body = src.split("def post_facebook(", 1)[1].split("\ndef ", 1)[0]
    check("composer advances two steps", body.count('"ถัดไป"') >= 2)
    # Publish is "แชร์เลย" (Share now), not "แชร์". "แชร์" is the tab that reveals
    # the share options; clicking it left the Reel unpublished and the run blamed
    # the login. A regression here silently stops every Facebook post.
    check("publish is แชร์เลย, force-clicked",
          'name="แชร์เลย"' in body and "force=True" in body)
    check("publish does not treat the แชร์ tab as publish",
          'name="แชร์", exact=True' not in body)
    check("publish is confirmed by the dialog or a navigation",
          "กำลังประมวลผลคลิป Reels" in body and "reels_composer" in body)


def test_browser_ci_storage_state() -> None:
    """`browser.connect` must offer a CI mode that needs no cloud desktop.

    Facebook/TikTok posting used to require a build pod because the only signed-in
    browser was the cloud desktop. The Actions rail restores a saved session, so
    `connect` has to launch its own Chromium when `AERIS_STORAGE_STATE_B64` is
    set — otherwise the cron has nothing to attach to.
    """
    section("browser: CI storage-state mode")
    src = (ROOT.parent / "aeris938-1" / "scripts" / "browser.py").read_text()
    connect = src.split("def connect(", 1)[1].split("\ndef ", 1)[0]
    check("reads AERIS_STORAGE_STATE_B64", "AERIS_STORAGE_STATE_B64" in connect)
    check("launches its own Chromium for CI", "chromium.launch(" in connect)
    check("still falls back to the cloud desktop over CDP",
          "connect_over_cdp" in connect)


def test_crosspost_uses_committed_queue() -> None:
    """`post` must act on the committed queue, not a fresh disk build.

    `library/shorts/` is gitignored, so on a fresh pod `build_queue()` returns
    only the Shorts that happen to be on disk and the real backlog is silently
    dropped — the 32 pending Reels for songs 13-20 became unreachable this way.
    """
    section("crosspost reads the committed queue (fresh-pod fix)")
    import crosspost

    src = (ROOT / "scripts" / "crosspost.py").read_text()
    body = src.split("def post(", 1)[1].split("\ndef ", 1)[0]
    check("post() loads the queue via load_queue", "load_queue()" in body)
    check("post() does not rebuild the queue from disk", "build_queue()" not in body)
    check("load_queue prefers the committed file", "QUEUE.exists()" in
          src.split("def load_queue(", 1)[1].split("\ndef ", 1)[0])

    # Behaviour: a queue file on disk wins over whatever library/ holds.
    real = crosspost.QUEUE
    import tempfile
    try:
        with tempfile.TemporaryDirectory() as d:
            crosspost.QUEUE = Path(d) / "q.json"
            sample = [{"id": "facebook-page:x", "platform": "facebook",
                       "video": "v.mp4", "caption": "c"}]
            crosspost.QUEUE.write_text(json.dumps(sample), encoding="utf-8")
            check("load_queue returns the file contents",
                  crosspost.load_queue() == sample)
    finally:
        crosspost.QUEUE = real


def test_crosspost_pace_and_captions() -> None:
    """The two defects found on 2026-11-01 must not come back.

    The first run posted 60 clips in 98 minutes (median gap 26 s) and gave the
    three chorus hooks of one song a byte-identical caption. Both are pinned
    here; the real posting path needs the signed-in desktop, so these are the
    offline halves of the contract.
    """
    section("crosspost cadence + hook captions (2026-11-01 burst)")
    import crosspost
    import time

    # Captions: every queued caption on a platform is distinct, and a hook
    # beyond the first is marked. Before the fix the three hooks of a song
    # shared one caption exactly.
    q = crosspost.build_queue()
    if not q:
        print("  skip (no shorts rendered yet)")
        return
    for plat in ("tiktok", "facebook"):
        caps = [it["caption"] for it in q if it["platform"] == plat]
        check(f"{plat}: captions are all distinct",
              len(set(caps)) == len(caps), f"{len(set(caps))} of {len(caps)}")
    h2 = next((it for it in q if it["hook"] == 2), None)
    check("hook 2 is tagged in the caption", h2 is not None and "ท่อน 2" in h2["caption"])
    h1 = next((it for it in q if it["hook"] == 1), None)
    check("hook 1 stays untagged", h1 is not None and "ท่อน" not in h1["caption"])
    check("hook number is carried on the queue item",
          all("hook" in it for it in q))

    # The caption's last job is the ask: a follow so the next song reaches them,
    # and a question because a comment is the cheapest engagement a small Page
    # can earn. Both must survive a caption rewrite.
    fb_cap = crosspost.caption("01-khon-di-thi-chak-pai", "facebook", 1)
    check("facebook caption asks for a follow", "กดติดตาม" in fb_cap)
    check("facebook caption asks a question", "คอมเมนต์" in fb_cap)
    tt_cap = crosspost.caption("01-khon-di-thi-chak-pai", "tiktok", 1)
    check("tiktok caption asks for a follow", "กดติดตาม" in tt_cap)

    # Cross-promotion: the four surfaces are one audience split across apps, so
    # each caption names the other two by handle. A URL would read as spam.
    check("facebook caption cross-promotes YouTube + TikTok",
          "@aerismusicth" in fb_cap and "@aeris.music4" in fb_cap)
    check("tiktok caption cross-promotes YouTube + Facebook",
          "@aerismusicth" in tt_cap and "AERIS Music" in tt_cap)

    # `refresh_captions` must rewrite only what has not gone out, and leave a
    # posted item's caption alone — the queue is a committed artifact and a
    # rebuild would drop the gitignored backlog.
    import tempfile
    real_q = crosspost.QUEUE
    real_load = crosspost.load_state
    try:
        with tempfile.TemporaryDirectory() as d:
            crosspost.QUEUE = Path(d) / "q.json"
            crosspost.QUEUE.write_text(json.dumps([
                {"id": "facebook-page:pending", "platform": "facebook",
                 "slug": "01-khon-di-thi-chak-pai", "hook": 1, "video": "v.mp4",
                 "caption": "stale"},
                {"id": "facebook-page:posted", "platform": "facebook",
                 "slug": "01-khon-di-thi-chak-pai", "hook": 1, "video": "v.mp4",
                 "caption": "already out"},
            ], ensure_ascii=False), encoding="utf-8")
            crosspost.load_state = lambda: {"posted": {"facebook-page:posted": {}}}
            n = crosspost.refresh_captions()
            q = json.loads(crosspost.QUEUE.read_text(encoding="utf-8"))
            by_id = {it["id"]: it for it in q}
            check("refresh rewrites the pending caption", n == 1)
            check("refresh keeps the posted caption",
                  by_id["facebook-page:posted"]["caption"] == "already out")
            check("refresh adds the cross-promo to the pending one",
                  "@aerismusicth" in by_id["facebook-page:pending"]["caption"])
            check("refresh is idempotent", crosspost.refresh_captions() == 0)
    finally:
        crosspost.QUEUE = real_q
        crosspost.load_state = real_load

    # Cadence: the shape of the 2026-11-01 run must now be refused. Sixty
    # posts inside the last 24 h is over the daily cap; a post 5 minutes old
    # is inside the minimum gap; a post an hour old on an empty day is fine.
    now = time.time()
    def at(secs_ago: float) -> str:
        return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime(now - secs_ago))

    # Newest post 30 min old, so the minimum-gap rule passes and the daily cap
    # is what refuses the run.
    burst = {"posted": {f"tiktok:s{i}": {"at": at(1800 + i * 90)} for i in range(60)}}
    ok, why = crosspost.pace_ok(burst, "tiktok", now)
    check("a 60-post burst is held back", not ok, why)
    check("the daily cap is named in the reason", "cap" in why)

    recent = {"posted": {"tiktok:x": {"at": at(300)}}}
    ok, why = crosspost.pace_ok(recent, "tiktok", now)
    check("a post 5 minutes old is inside the minimum gap", not ok, why)

    spaced = {"posted": {"tiktok:x": {"at": at(3600)}}}
    check("a post an hour old is allowed", crosspost.pace_ok(spaced, "tiktok", now)[0])

    check("an empty state is allowed", crosspost.pace_ok({"posted": {}}, "tiktok", now)[0])

    # Cadence is per platform: a busy TikTok must not hold Facebook back.
    check("the cap is counted per platform",
          crosspost.pace_ok(burst, "facebook", now)[0])

    # A Page post is stored under the `facebook-page` state key, not `facebook`.
    # The guard must read that key, or it goes blind to Page posts — which is how
    # a second Reel slipped out 45 s after the first on 2026-11-02.
    page = {"posted": {"facebook-page:x": {"at": at(60)}}}
    check("a Page post 1 minute old holds Facebook back",
          not crosspost.pace_ok(page, "facebook", now)[0])
    page_burst = {"posted": {f"facebook-page:s{i}": {"at": at(1800 + i * 90)}
                             for i in range(5)}}
    check("5 Page posts in a day hit the daily cap",
          not crosspost.pace_ok(page_burst, "facebook", now)[0])

    # The post URL must come from the platform's own list, never `page.url`.
    src = (ROOT / "scripts" / "crosspost.py").read_text()
    check("a post-list reader exists", "def newest_post_url(" in src)
    check("the studio/composer page is not stored as the post URL",
          "real = newest_post_url(" in src)


def test_social_stats_parser() -> None:
    """The dashboard reader must never invent a number.

    The whole point of this rail is to be trustworthy enough for the strategy
    pass to act on, so the parser is tested against the exact shapes the two
    dashboards were seen to produce, including the ones that must yield
    UNKNOWN.
    """
    section("social stats reader (FB / TikTok / Shopee)")
    import social_stats

    # TikTok puts the value on the line after the label, not on it.
    tiktok = "Video views\n--\n0\n(--)\nProfile views\n--\n0\n(--)\nEst. rewards\n$0.00"
    check("value on the next line is found",
          social_stats._first_int(tiktok, ["Video views"]) == 0)
    check("a different metric is not mistaken for the first",
          social_stats._first_int(tiktok, ["Est. rewards"]) == 0)
    # Commission and rewards are decimals, so a whole-number-only parser would
    # silently report UNKNOWN for the one number that matters commercially.
    check("a decimal is read, not dropped",
          social_stats._first_int("ค่าคอมมิชชั่น\n฿12.50\n", ["ค่าคอมมิชชั่น"]) == 12.5)

    # Facebook writes the follower count into one line.
    fb = "AERIS Music\u00a0\nผู้ติดตาม 0 คน • กำลังติดตาม 0 คน"
    check("Thai follower count is read",
          social_stats._first_int(fb, ["ผู้ติดตาม"]) == 0)

    # The insights page states followers only as a share ("ผู้ติดตาม 94.4%",
    # beside "ไม่ใช่ผู้ติดตาม"), so a first-number scan reported 94.4 as the
    # follower total. `_followers` reads the count from the profile line only.
    insights = ("การดูโดยผู้ติดตามเทียบกับคนที่ไม่ใช่ผู้ติดตาม\n100%\n"
                "ไม่ใช่ผู้ติดตาม\n0%\nผู้ติดตาม\n94.4%\nคลิป Reels")
    check("the insights share is not read as a follower count",
          social_stats._followers(insights) == "UNKNOWN")
    check("the profile count is read",
          social_stats._followers("AERIS Music\nผู้ติดตาม 1 คน • กำลังติดตาม 0 คน") == 1)
    check("a thousands-separated count is read",
          social_stats._followers("ผู้ติดตาม 1,234 คน") == 1234)

    # Nothing matching must be UNKNOWN, not 0 and not a neighbouring number.
    check("a missing metric is UNKNOWN, not 0",
          social_stats._first_int("no metrics here\n7\n", ["ยอดดู", "views"]) == "UNKNOWN")

    # Sign-out detection: the login word is in the chrome even when signed in,
    # so the test must key on the Page's own content.
    check("a signed-in Page is not called signed out",
          not social_stats._fb_signed_out("AERIS Music\nผู้ติดตาม 0 คน\nเข้าสู่ระบบ"))
    check("a real login wall is caught",
          social_stats._fb_signed_out("เข้าสู่ระบบ\nลืมบัญชีใช่ไหม\nสมัคร"))

    # The report must render UNKNOWN for an unreadable surface, never a blank.
    md = social_stats.render({
        "facebook": {"reachable": False, "note": "not signed in"},
        "tiktok": {"reachable": True, "views_7d": 0, "followers_total": 1,
                   "followers_change_7d": 0, "detail_locked_under_100": True},
        "shopee": {"reachable": False, "note": "not onboarded"},
    })
    check("unreadable surfaces render UNKNOWN", md.count("UNKNOWN") >= 4)
    check("the 100-follower lock is called out", "100 ผู้ติดตาม" in md)

    # Shopee's dashboard answers a fresh automated browser with an anti-bot
    # captcha, which is neither the login page nor the dashboard. It must read
    # as unreachable so the caller falls back to a real dated number, instead
    # of a "reachable" page whose every metric is UNKNOWN.
    class _FakeDesk:
        def __init__(self, url, text):
            self._url, self._text = url, text
        def goto(self, *_a, **_k):
            pass
        def js(self, _expr):
            return self._url
        def text(self):
            return self._text

    cap = social_stats.measure_shopee(_FakeDesk(
        "https://shopee.co.th/verify/captcha?x=1",
        "Skip to main content\nNeed Help?\nVerify to Continue\n"
        "Drag the missing piece to restore the puzzle\nVerify"))
    check("a captcha page is not read as the dashboard",
          cap["reachable"] is False)
    real = social_stats.measure_shopee(_FakeDesk(
        "https://affiliate.shopee.co.th/dashboard",
        "Dashboard\nKey Metrics\nClicks\n7\n0%\nOrders\n1\n0%\nEst. Commission(฿)\n2.5"))
    check("a real dashboard is read, including clicks",
          real["reachable"] and real["clicks"] == 7 and real["orders"] == 1)

    # The API path: the affiliate JSON endpoints answer a plain HTTP request
    # carrying the exported cookies, so a scheduled read needs no browser. Stub
    # the HTTP calls and check the response is parsed, and that a missing
    # session degrades to None (so the caller can fall back to the desk).
    orig_hdr, orig_api = social_stats._shopee_cookie_header, social_stats._shopee_api
    try:
        social_stats._shopee_cookie_header = lambda: None
        check("no session means no API read",
              social_stats.measure_shopee_api() is None)
        social_stats._shopee_cookie_header = lambda: "SPC_F=x; SPC_U=1"
        social_stats._shopee_api = lambda path, cookie: (
            {"code": 0, "data": {"total_count": 12}} if "click_report" in path
            else {"code": 0, "data": {"total_count": 3,
                  "list": [{"commission": 1.5}, {"commission": 2}]}}
            if "report/list" in path else
            {"code": 0, "data": {"income_breakdown": {}}})
        api = social_stats.measure_shopee_api()
        check("the API read carries clicks and orders",
              api["clicks"] == 12 and api["orders"] == 3)
        check("commission is summed across orders",
              api["commission"] == 3.5 and api["source"] == "api")
        social_stats._shopee_api = lambda path, cookie: {"code": 401}
        check("a refused API call falls back (None)",
              social_stats.measure_shopee_api() is None)
    finally:
        social_stats._shopee_cookie_header = orig_hdr
        social_stats._shopee_api = orig_api
    check("no metric is left blank", "|  |" not in md)

    # The daily pass must run it, or the strategy loop still cannot see these.
    desk = (ROOT / "scripts" / "desk_daily.py").read_text()
    check("desk_daily runs the social reader", "social_stats.py" in desk)


def test_karaoke_loudness_contract() -> None:
    """flow_song._karaoke must master through make_song's two-pass loudnorm.

    The inline single-pass `loudnorm=I=-16` this replaced overshot its target
    (asked -16, delivered -14.4), so the karaoke sat at the song's level and
    could be the louder of the two — song 15 measured karaoke +0.6 dB over its
    song. A source check, because the real mixer needs ffmpeg and the stems.
    """
    section("karaoke loudness contract (WIRING: karaoke louder than song)")
    src = (ROOT / "scripts" / "flow_song.py").read_text()
    body = src.split("def _karaoke(", 1)[1].split("\ndef ", 1)[0]
    check("karaoke measures with the two-pass helper", "_measure_loudnorm" in body)
    check("karaoke applies with the two-pass helper", "_apply_loudnorm" in body)
    check("karaoke keeps the song's offset", "KARAOKE_OFFSET_DB" in body)
    check("no inline single-pass loudnorm left", "loudnorm=I=" not in body)


def test_setup_pod_ffmpeg() -> None:
    """ffmpeg must be unpacked under /workspace, not into a mktemp dir.

    The symlinks in `setup-pod.sh` point at the extracted tree. Unpacking into a
    `mktemp -d` that the script then deletes left dangling links, so the next run
    saw `-x "$BIN/ffmpeg"` as true while the binary was gone, and every render
    died on a missing ffprobe after a generation call had already been spent.
    """
    section("pod setup (WIRING: dangling ffmpeg symlink)")
    src = (ROOT / "scripts" / "setup-pod.sh").read_text()
    check("ffmpeg unpacks under /workspace", "FFDIR=/workspace/ax-tools/ffmpeg" in src)
    check("extracts into FFDIR, not the temp dir", '"$FFDIR"' in src)


def test_automation_secret_fallback() -> None:
    """A secret must resolve in an automation sandbox, not only in a session.

    An interactive session gets the user's secrets as environment variables, but
    an automation sandbox does not — so every script that read `os.environ`
    directly worked when a human ran it and failed under cron. That is exactly
    how `AX Music Marketing Daily` died with "missing secret YT_CLIENT_ID" while
    the release and market rails were "green". `ops/ax_secrets.py` adds the
    sandbox settings-API fallback; these checks pin that every credential reader
    goes through it instead of reading the environment alone.
    """
    section("automation secret fallback (WIRING: cron sees no env secrets)")
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import ax_secrets  # noqa: E402
    os.environ.pop("AX_TEST_SECRET", None)
    check("get_secret returns '' when nothing provides it",
          ax_secrets.get_secret("AX_TEST_SECRET") == "")
    os.environ["AX_TEST_SECRET"] = "from-env"
    check("get_secret prefers the environment", ax_secrets.get_secret("AX_TEST_SECRET") == "from-env")
    os.environ.pop("AX_TEST_SECRET", None)

    for rel, name in [("ops/yt_auth.py", "yt_auth"),
                      ("music938-1/scripts/market.py", "market"),
                      ("ops/ar_promo_site.py", "ar_promo_site")]:
        src = (ROOT.parent / rel).read_text()
        check(f"{name} uses ax_secrets", "ax_secrets" in src)
        check(f"{name} no longer reads os.environ for YT_CLIENT_ID",
              'os.environ["YT_CLIENT_ID"]' not in src
              and 'environ.get("YT_CLIENT_ID")' not in src)


def test_monetize_footer() -> None:
    """The affiliate footer must reach every surface, and the backfill must run
    before the day's releases.

    Two failures this pins: a link that lands in `monetization.json` but never in
    a live description earns nothing, and a replacement that runs *after* the
    release never gets an upload slot — the wrong-render backlog then sits
    forever while the log still says "0 replaced".
    """
    section("monetization footer")
    cfg = json.loads((ROOT / "channel" / "monetization.json").read_text(encoding="utf-8"))
    check("affiliate link is set", bool(cfg.get("shopee_affiliate")))
    check("link is an https url", cfg.get("shopee_affiliate", "").startswith("https://"))

    mon = (ROOT / "scripts" / "monetize.py").read_text()
    check("footer carries the affiliate link", "shopee_affiliate" in mon)
    check("footer degrades when a link is blank", "if shopee:" in mon)

    # A th.shp.ee short link strips sub_id (verified against the live redirect),
    # so per-surface attribution needs the dashboard links. They now exist
    # (minted 2026-11-02), so each surface gets its own tagged link and only an
    # unknown surface falls back to the plain affiliate link.
    import monetize
    monetize.CACHE = None
    per = cfg.get("shopee_links") or {}
    check("link() prefers the surface's own sub_id link",
          monetize.link("youtube") == per.get("youtube", cfg.get("shopee_affiliate")))
    check("an unknown surface falls back to the plain affiliate link",
          monetize.link("nope") == cfg.get("shopee_affiliate"))
    check("the footer uses the youtube surface link",
          per.get("youtube", "") and per["youtube"] in monetize.block("song"))
    monetize.CACHE = None

    apply_src = (ROOT / "scripts" / "apply_monetize.py").read_text()
    check("backfills video descriptions", "videos?part=snippet" in apply_src)
    check("backfills playlists too", "patch_playlists" in apply_src)
    check("only edits the channel's own playlists", "channelId={CHANNEL_ID}" in apply_src)
    check("backfill is quota-bounded", "--write-budget" in apply_src)
    # The backfill must actually run on the rail, or the old videos never get
    # the new link. It is invoked from daily_release.py (a plain .py file), not
    # from the workflow — the write token has no `workflow` scope.
    dl = (ROOT / "scripts" / "daily_release.py").read_text()
    check("daily release runs the backfill", "apply_monetize.py" in dl)

    plug = (ROOT.parent / "plugins" / "music-release" / "scripts" / "main.py").read_text()
    body = plug.split("def main", 1)[1]
    check("replacements run before the release",
          body.index("pending_replacements.py") < body.index("daily_release.py"))
    rep = (ROOT / "scripts" / "replace_video.py").read_text()
    check("replacement can fetch media on a fresh pod", "release.fetch_media" in rep)
    check("replacement supports Shorts", '"short"' in rep)

    # The 0-click report on 2026-11-03 traced to two shapes: the per-surface
    # links pointed at Shopee's homepage (nothing to buy), and the affiliate
    # line sat at the very bottom of the description, past YouTube's "Show
    # more" fold. A description CTA must lead with the link, and the link must
    # be a product/search page, not the storefront root.
    import release
    monetize.CACHE = None
    cta = monetize.cta("youtube")
    check("cta carries the youtube surface link",
          per.get("youtube", "") and per["youtube"] in cta)
    check("cta asks for a follow", "กดติดตาม" in cta)
    _t, desc, _tg = release.describe("01-khon-di-thi-chak-pai", "song", "")
    check("cta survives the description fold (within the first 200 chars)",
          per.get("youtube", "") and desc.index(per["youtube"]) < 200,
          f"link at {desc.index(per['youtube'])}")
    mint_src = (ROOT.parent / "ops" / "shopee_mint.py").read_text()
    check("mint tool exists for re-pointing the links",
          "custom_link" in mint_src)

    # The 20 videos already live carry the old homepage link at the bottom.
    # `refresh_description` must re-point it and lift the CTA, and be idempotent.
    old = ("🎵 เพลงเก่า\n\nเพลงผ่อนคลาย\n\n🎧 ฟังเพลิน\n\n"
           "🛒 สนับสนุนช่องผ่าน Shopee:\nhttps://s.shopee.co.th/OLDHOME")
    fixed = monetize.refresh_description(old, "youtube")
    check("refresh re-points the old homepage link",
          "OLDHOME" not in fixed and per["youtube"] in fixed)
    check("refresh lifts the cta above the fold",
          fixed.index(per["youtube"]) < 120, f"{fixed.index(per['youtube'])}")
    check("refresh is idempotent",
          monetize.refresh_description(fixed, "youtube") == fixed)
    monetize.CACHE = None


def test_studio_web_rail() -> None:
    """Analytics and comments go through the signed-in Studio, not the Data API.

    The channel's OAuth client is NATIVE_DEVICE, so Google refuses
    `youtube.force-ssl` at the device endpoint and the client cannot use a
    loopback redirect — the API rail can never read comments or analytics. Studio
    is the owner's own UI and the desktop is already signed in as the owner, so
    this is the working path and it must stay wired to the real CDP port.
    """
    section("studio web rail (analytics + comments)")
    src = (ROOT / "scripts" / "studio_web.py").read_text()
    check("drives CDP on 9222", "127.0.0.1:9222" in src)
    check("reads the channel analytics", "analytics/tab-overview" in src)
    check("reads the comment inbox", "/comments/inbox" in src)
    check("posts a reply", "ตอบกลับ" in src)
    check("uses the native textarea setter", "HTMLTextAreaElement.prototype" in src)
    check("defaults to a Thai reply", "ขอบคุณ" in src)
    # A Short earns the view; the pinned comment must carry the viewer to the full
    # song, which is what earns watch-hours. It has to be the owner's own comment
    # and it must not be re-posted on every run.
    check("pins the full-song link on Shorts", "pin-shorts" in src)
    check("the pin advertises the full song", "ฟังเพลงเต็มได้ที่นี่" in src)
    check("pinning is idempotent", "video_has_marker" in src)
    # The pinned badge is locale-dependent: this account's UI renders "Pinned
    # by", so a Thai-only check reported an already-pinned video as unpinned and
    # made pin-shorts look like it had done nothing.
    check("already-pinned is not unpinned",
          "ปักหมุดโดย" in src and "Pinned by" in src)

    # The Short->song join comes from the release state and must skip retired
    # uploads: their ids 404, so a pin would fail on every run.
    sys.path.insert(0, str(ROOT / "scripts"))
    import studio_web as sw  # noqa: E402
    targets = sw.short_pin_targets()
    state = json.loads((ROOT / "work" / "release-state.json").read_text())
    retired = {r["video_id"] for r in state["released"] if r.get("retired_at")}
    check("a target per live Short with a live song", len(targets) >= 1)
    check("no retired Short is a target", not ({v for v, _ in targets} & retired))
    check("every target links to a youtu.be song", all("youtu.be/" in u for _, u in targets))


def test_desk_daily_orchestrator() -> None:
    """One command must administer every surface that needs the browser."""
    section("desk daily orchestrator")
    src = (ROOT / "scripts" / "desk_daily.py").read_text()
    check("brings the desktop up", "bootstrap.py" in src)
    check("answers comments", "studio_web.py" in src)
    check("reads analytics", "analytics" in src)
    check("cross-posts both platforms", '"facebook", "tiktok"' in src)
    check("keeps playlists full", "fill_playlists.py" in src)
    check("pins full-song links on Shorts", "pin-shorts" in src)
    check("writes a Thai report", "desk-report.md" in src)
    # The footer must advertise every surface, or the audience cannot find them.
    cfg = json.loads((ROOT / "channel" / "monetization.json").read_text(encoding="utf-8"))
    for key in ("youtube", "facebook", "tiktok", "shopee_affiliate"):
        check(f"monetization.json carries {key}", bool(cfg.get(key)))
    # And crosspost must survive a fresh pod, where library/ is empty.
    cp = (ROOT / "scripts" / "crosspost.py").read_text()
    check("crosspost fetches media on a fresh pod", "release.fetch_media" in cp)


def test_profile_setup() -> None:
    """A bare profile reads as abandoned, so it must be fillable from the repo."""
    section("profile setup")
    src = (ROOT / "scripts" / "profile_setup.py").read_text()
    check("drives the cloud desktop", "browser as B" in src)
    check("has a TikTok path", "def tiktok(" in src)
    check("has a Facebook path", "def facebook(" in src)
    check("sets a Thai bio", "เพลงไทย" in src)
    # The Page must be entered as the Page or the cover control does not exist.
    check("switches into the Page", "_fb_switch_to_page" in src)
    # The cover's crop dialog confirms with "บันทึกการเปลี่ยนแปลง"; a bio field
    # uses a plain "บันทึก". Using the wrong one silently leaves the cover unset.
    check("confirms the FB cover crop", "บันทึกการเปลี่ยนแปลง" in src)
    # The profile picture control only opens on hover; a plain click misses it.
    check("hovers the FB photo control", "hover=True" in src)
    # The cover is derived from the banner and must exist for the script to run.
    check("ships an FB cover", (ROOT / "channel" / "cover-facebook-1640x624.png").exists())
    check("ships an avatar", (ROOT / "channel" / "avatar-800x800.png").exists())
    # The branded surface is the Page, not K's personal profile. Both the footer
    # and crosspost.py use the Page; a profile_setup that drifts back to the
    # personal id would brand the wrong account.
    import profile_setup
    check("brands the AERIS Music Page", profile_setup.FACEBOOK_ID == "61595890900382")


def test_login_vault() -> None:
    """The browser session must survive a fresh sandbox, so it round-trips.

    K has had to sign in to Google/Facebook/TikTok more than once because a new
    sandbox gets an empty /workspace. ops/login_vault.py snapshots the session
    cookies to durable storage. These checks pin the encode/decode, including the
    multi-chunk split that the KV value cap forces.
    """
    section("login vault (sign in once, not every pod)")
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import login_vault  # noqa: E402

    cookies = [
        {"name": "c_user", "value": "1", "domain": ".facebook.com", "path": "/"},
        {"name": "SID", "value": "abc", "domain": ".google.com", "path": "/"},
        {"name": "sessionid", "value": "xyz", "domain": ".tiktok.com", "path": "/"},
    ]
    index, chunks = login_vault.pack(cookies, "aerismusic8@gmail.com")
    check("round-trips the cookie set", login_vault.unpack(index, chunks) == cookies)
    check("records the account", index["account"] == "aerismusic8@gmail.com")
    check("reports the signed-in surfaces",
          set(index["surfaces"]) == {".google.com", ".facebook.com", ".tiktok.com"})

    # Incompressible data so gzip cannot collapse it below the chunk cap.
    import base64 as _b64
    import os as _os
    big = [{"name": f"c{i}", "value": _b64.b64encode(_os.urandom(400)).decode(),
            "domain": ".facebook.com", "path": "/"} for i in range(300)]
    idx2, ch2 = login_vault.pack(big)
    check("splits a large session into chunks", len(ch2) > 1)
    check("reassembles every chunk", login_vault.unpack(idx2, ch2) == big)
    # A snapshot must not carry the password store.
    src = (ROOT.parent / "ops" / "login_vault.py").read_text()
    check("never stores passwords", "Login Data" not in src)
    # Presence of a cookie is not proof of a session: Facebook kept c_user/xs
    # while serving the logged-out page, and restore reported "ok" the whole time.
    check("names the auth cookie per surface",
          login_vault.AUTH[".facebook.com"] == "c_user"
          and login_vault.AUTH[".google.com"] == "SID")
    check("probes a page per surface",
          all(d in login_vault.PROBE for d in (".facebook.com", ".google.com", ".tiktok.com")))
    check("restore verifies instead of trusting cookie presence",
          "def _signed_in" in src and "SESSION REJECTED" in src)
    # Flow Music is the song engine — losing its login stops new songs, so it is
    # watched and restored with the rest. Its landing page keeps a "Log in" link
    # even when signed in, so the probe is a negative marker.
    check("watches Flow Music", ".flowmusic.app" in login_vault.WATCH)
    check("Flow Music auth cookie is named",
          login_vault.AUTH.get(".flowmusic.app") == "sb-sb-auth-token.0")
    check("a '!' marker means signed-in-only-when-absent",
          login_vault.PROBE[".flowmusic.app"][1].startswith("!") and
          "startswith(\"!\")" in src)
    # Cookies are not the whole session: Google keeps its device-trust token in
    # localStorage, so a cookie-only restore still makes Google ask for the
    # device. The snapshot must also carry per-origin storage.
    check("snapshots per-origin storage, not just cookies",
          "def save_storage" in src and "def restore_storage" in src)
    check("save() captures storage too",
          "save_storage()" in src and "restore_storage()" in src)
    check("storage is dumped and re-applied through the page",
          "_dump_storage" in src and "_restore_storage" in src)
    check("keeps the Google device-trust origins",
          "https://accounts.google.com" in login_vault.STORAGE_ORIGINS)
    # Inactivity is a re-auth cause a snapshot cannot fix, so a heartbeat loads
    # each surface to reset the timer.
    check("has a session heartbeat", "def heartbeat" in src and '"heartbeat"' in src)


def test_operator_url() -> None:
    """The noVNC link must be built, not hand-copied, so it cannot be missed.

    The operator signs in through this URL; it was previously printed as a
    placeholder (`work-1-<work-host>`) and the real host had to be pasted from the
    session block by hand. RUNTIME_ID is the same string that appears there.
    """
    section("cloud desktop operator URL")
    sys.path.insert(0, str(ROOT.parent / ".agents/skills/ax-cloud-desktop/scripts"))
    import bootstrap  # noqa: E402

    old = os.environ.get("RUNTIME_ID")
    try:
        os.environ["RUNTIME_ID"] = "givjlzdksjoviogw"
        url = bootstrap.operator_url()
        check("builds the work-1 host from RUNTIME_ID",
              url == "https://work-1-givjlzdksjoviogw.prod-runtime.all-hands.dev"
                     "/vnc.html?autoconnect=1&resize=remote")
        # resize=remote makes the desktop take the phone's shape so the text is
        # native size; resize=scale shrinks a 1600x900 screen onto the phone and
        # that is exactly what made signing in from a phone painful.
        check("fits the phone instead of shrinking",
              "autoconnect=1" in url and "resize=remote" in url)
        os.environ.pop("RUNTIME_ID")
        check("falls back to None without RUNTIME_ID", bootstrap.operator_url() is None)
        # A fresh pod wipes /tmp, so Xvfb dies on the missing X11 socket dir; and
        # the profile on /workspace keeps a SingletonLock naming the old pod, so
        # Chrome refuses to start. Both must self-heal or the desktop is DOWN.
        src = (ROOT.parent / ".agents/skills/ax-cloud-desktop/scripts"
               / "bootstrap.py").read_text()
        check("self-heals the missing X11 socket dir", "def ensure_x11_socket" in src)
        check("self-heals a stale SingletonLock", "def clear_stale_lock" in src)
        # The wheels live on /workspace but the .pth pointing at them does not, so
        # after a recycle every script dies with "ModuleNotFoundError: numpy".
        check("re-points Python at the /workspace libs", "def ensure_pylibs" in src)
    finally:
        if old is None:
            os.environ.pop("RUNTIME_ID", None)
        else:
            os.environ["RUNTIME_ID"] = old


def test_phone_login() -> None:
    """Signing in from a phone must not mean typing a URL on a phone.

    noVNC is the only phone route to the desktop, and its address bar is a few
    pixels tall on a small screen. ops/phone_login.py serves one page of large
    buttons: a tap opens that surface in the desktop browser and drops the phone
    into noVNC already showing it.
    """
    section("phone sign-in page")
    src = (ROOT.parent / "ops" / "phone_login.py").read_text()
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import phone_login  # noqa: E402

    check("serves a phone page", "ThreadingHTTPServer" in src)
    check("has a big-button surface per service",
          {"google", "flow", "gemini", "facebook", "tiktok", "youtube", "shopee"}
          <= set(phone_login.SURFACES))
    check("names the account to use", phone_login.EXPECTED_ACCOUNT == "aerismusic8@gmail.com")
    check("opens the surface in the desktop over CDP", "/json/new?" in src)
    check("hands the phone to noVNC after a tap", "novnc_url()" in src)
    check("asks for remote resize", "resize=remote" in src)
    # The page must not carry a password field — the operator's password manager
    # fills it inside noVNC; the agent never handles a credential.
    check("never collects a password", "type=\"password\"" not in src
          and "<input" not in src)


def test_watchdog() -> None:
    """The watchdog must heal an auto-paused automation and alert a person.

    The rail had no watcher, so when the platform auto-paused the daily release
    after five `Sandbox not available` failures, nothing said so. These pin the
    decision logic: auto-pause is healed, a manual pause is left alone, and the
    alert cooldown suppresses a repeat of the same signature.
    """
    section("ax watchdog (notice a stopped automation)")
    sys.path.insert(0, str(ROOT.parent / "plugins/ax-watchdog/scripts"))
    import main as wd  # noqa: E402

    auto = {"id": "a", "name": "AX Music Daily Release", "enabled": False,
            "disabled_reason": "Paused automatically: the last 5 runs all failed",
            "disabled_detail": {"source": "consecutive_failures"}}
    manual = {"id": "b", "name": "Content Lab", "enabled": False,
              "disabled_reason": "manual", "disabled_detail": {"source": "user"}}
    live = {"id": "c", "name": "Activity Monitor", "enabled": True}

    wd.list_automations = lambda: [auto, manual, live]
    wd.recent_runs = lambda aid: [{"status": "FAILED", "error_detail": "Timed out: Sandbox not available"}]
    healed = []
    wd.re_enable = lambda aid: (healed.append(aid), True)[1]

    problems, actions = wd.audit_automations(heal=True)
    check("heals an auto-paused automation", actions == ["re-enabled AX Music Daily Release"])
    check("re-enables the right one", healed == ["a"])
    check("leaves a manual pause alone", not any("Content Lab" in p for p in problems))
    check("does not touch a running automation", not any("Activity Monitor" in p for p in problems))
    check("reports the failure that caused it", any("Sandbox not available" in p for p in problems))

    # With heal off, the same finding must be reported but nothing changed.
    healed.clear()
    problems2, actions2 = wd.audit_automations(heal=False)
    check("heal=false changes nothing", actions2 == [] and healed == [])
    check("heal=false still reports it", any("auto-paused" in p for p in problems2))

    # The alert cooldown: same signature inside the window is held, a new one fires.
    check("alert has a cooldown", "cooldown_hours" in json.dumps(
        json.load(open(ROOT.parent / "plugins/ax-watchdog/.plugin/plugin.json"))))
    src = (ROOT.parent / "plugins/ax-watchdog/scripts/main.py").read_text()
    check("runs outside the sandbox (no dependency on it)", "AUTOMATION_KV_TOKEN" in src)
    check("pushes through ntfy", "ntfy.sh" in src)


def test_fill_playlists() -> None:
    """Playlists must cover every video and stay idempotent.

    A playlist is free reach (no upload quota), so every video belongs in one.
    The classifier decides the bucket; a karaoke title also contains the song
    name, so order matters. Pinned here because a mis-bucketed video silently
    disappears from the playlist a viewer would look in.
    """
    section("playlist fill (free reach, no quota)")
    sys.path.insert(0, str(ROOT / "scripts"))
    import fill_playlists as fp  # noqa: E402

    cases = [
        ("คนดีที่จากไป (ท่อนที่ 2) #เพลงไทย #Shorts", "short"),
        ("รวมเพลงไทยเพื่อชีวิต 15 เพลง (เลือกเพลงฟังได้)", "compilation"),
        ("คนดีที่จากไป — เพลงเศร้า ที่เข้าใจความเสียใจ", "song"),
    ]
    for title, want in cases:
        check(f"{title[:28]} -> {want}", fp.classify(title) == want)
    # Karaoke and the NAVIYA artist set are retired (K, 2026-11-04: songs only),
    # so no title can classify into them and no playlist definition remains.
    check("karaoke is not a bucket", fp.classify("คนดีที่จากไป (คาราโอเกะ)") == "song")
    check("naviya is not a bucket",
          fp.classify("NAVIYA — FIRST LIGHT | Official Visualizer") == "song")
    # Every bucket a title can land in must have a playlist definition.
    defined = {k for k, *_ in fp.BUCKETS}
    check("every bucket has a playlist", {c[1] for c in cases} <= defined)

    # Mood playlists are additive: a full song joins its mood *and* the all-songs
    # playlist, unlike the exclusive buckets above. The mood comes from the lyric
    # header, so a video is matched to a mood by title containment.
    by_title = fp.song_moods()
    check("reads a mood per lyric", len(by_title) >= 20)
    check("sad song -> mood-sad", fp.moods("คนดีที่จากไป — เพลงเศร้า", by_title) == ["mood-sad"])
    check("warm song -> mood-warm", fp.moods("รักที่ไม่มีวันจบ", by_title) == ["mood-warm"])
    check("unknown title -> no mood", fp.moods("NAVIYA — FIRST LIGHT", by_title) == [])
    # A mood key must not collide with a bucket key, or one would overwrite the
    # other's title in the state map and the playlist would be misnamed.
    check("mood keys are distinct from buckets",
          not ({k for k, *_ in fp.MOODS} & {k for k, *_ in fp.BUCKETS}))


def test_outreach() -> None:
    """The Facebook growth loop (follow + invite) must be safe and paced.

    K's rule (2026-11-03): a Page grows by following suggested pages and
    inviting friends, not by waiting for real friendships. The dangerous part is
    *where* a follow lands: without switching to the Page identity first, every
    follow goes to the personal profile and the Page stays at 0. These checks
    pin the identity gate, the daily cap and the pace, without a browser.
    """
    section("outreach (follow suggested pages, invite friends)")
    sys.path.insert(0, str(ROOT.parent / "aeris938-2" / "scripts"))
    import outreach  # noqa: E402

    src = (ROOT.parent / "aeris938-2" / "scripts" / "outreach.py").read_text()

    # Identity: the switch must happen before the grid navigation, because the
    # grid does not offer the switch and switching after it is a silent no-op.
    check("switches to the Page identity before following",
          "_switch_to_page(page)" in src and
          src.index("_switch_to_page(page)") < src.index("page.goto(SUGGEST"))
    check("proves the switch stuck (จัดการเพจ marker)",
          "จัดการเพจ" in src and "_acting_as_page" in src)
    check("aborts rather than following as the personal profile",
          "would land on the personal profile" in src)
    check("verifies the Page follow count rose",
          "_page_following_count" in src and "did not rise" in src)

    # Pace: a burst gets the Page rate-limited, so a cap and a gap are enforced.
    check("has a daily cap", "DAILY_CAP" in src and outreach.DAILY_CAP <= 100)
    check("has a minimum gap between actions", outreach.MIN_GAP_SECONDS >= 3)

    # State: a page is never followed twice, and a re-run resumes.
    import tempfile
    from pathlib import Path as _P
    with tempfile.TemporaryDirectory() as d:
        outreach.STATE = _P(d) / "outreach-state.json"
        st = {"followed": {}, "invited": {}}
        outreach.save_state(st)
        check("state round-trips", outreach.load_state() == st)
        today = outreach._today()
        st["followed"]["X"] = {"at": today + "T00:00:00Z"}
        outreach.save_state(st)
        check("counts today's follows", outreach._follows_today(outreach.load_state()) == 1)
        st["followed"]["Y"] = {"at": "2000-01-01T00:00:00Z"}
        check("ignores older follows in the daily count",
              outreach._follows_today(st) == 1)

    # The identity probe is a real predicate, not a constant.
    class _FakePage:
        def __init__(self, text):
            self._t = text
        def inner_text(self, _sel):
            return self._t

    check("acting-as-Page is true on the manage shell",
          outreach._acting_as_page(_FakePage("จัดการเพจ AERIS Music")))
    check("acting-as-Page is false on the personal shell",
          not outreach._acting_as_page(_FakePage("Aeris-Ak Akath ผู้ติดตาม 0 คน")))


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
    test_provenance()
    test_genres()
    test_thumb_contrast()
    test_titles()
    test_compilation()
    test_flow_extend_kinds()
    test_market_report()
    test_market_plugin_wiring()
    test_market_root_resolution()
    test_automation_secret_fallback()
    test_karaoke_loudness_contract()
    test_crosspost_engine()
    test_browser_ci_storage_state()
    test_crosspost_uses_committed_queue()
    test_crosspost_pace_and_captions()
    test_social_stats_parser()
    test_setup_pod_ffmpeg()
    test_monetize_footer()
    test_studio_web_rail()
    test_desk_daily_orchestrator()
    test_profile_setup()
    test_login_vault()
    test_outreach()
    test_operator_url()
    test_phone_login()
    test_watchdog()
    test_fill_playlists()
    test_affiliate_short()
    test_outputs()
    print(f"\n{PASS} passed, {FAIL} failed")
    if FAILURES:
        print("failed: " + ", ".join(FAILURES[:10]))
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
