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
import subprocess
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

def test_playlist_patch_is_idempotent() -> None:
    """`apply_monetize.patch_playlists` must not stack its footer on every run.

    A playlist already carries our CTA (added by `refresh_description`) but not
    the full footer block, so `new == desc` was true and the code appended the
    footer unconditionally — each run grew the description by another copy. The
    dry run reported "6 to update" forever, and an apply run would have grown the
    live descriptions without bound. The append is now gated on the affiliate
    link being absent.
    """
    section("playlist patch is idempotent (no footer stacking)")
    src = (ROOT / "scripts" / "apply_monetize.py").read_text()
    body = src.split("def patch_playlists(", 1)[1].split("\ndef ", 1)[0]
    check("append is gated on the affiliate link being absent",
          "link and link in desc" in body and "continue" in body)
    check("the unconditional append is gone",
          'if new == desc:\n            new = (desc.rstrip()' not in body)


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
        # Search-first packaging: the card must name the real query it answers,
        # or the funnel's title/hashtags fall back to the wrong-intent tag.
        check(f"{p['id']}: names its search query", bool(p.get("search")),
              str(p.get("search")))
        check(f"{p['id']}: search query is Thai", has_thai(p.get("search", "")))

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


def test_surreal_lane() -> None:
    """The absurdist FB/TK identity must be intentional, safe and varied.

    K's directive (2026-11-09) was to make the Facebook + TikTok surfaces a
    deliberately unhinged art project — "สุดโต่งแต่ไม่ผิดกฏ". The advisor panel
    named the two failure modes this test pins:

      * randomness with no rule reads as noise, so the identity must carry one
        recognisable, repeated ritual;
      * a caption that drifts into a real-world claim, or a wall of identical
        clips, is what gets a new account limited — so the premise comes from a
        closed vocabulary with a banned-substring guard, and the art recipe
        differs per song.
    """
    section("surreal lane (absurd FB/TK identity)")
    import surreal
    import make_surreal_short as ms

    # The identity itself: Thai, and a rule a stranger can recognise.
    for name, val in (("slogan", surreal.SLOGAN), ("project", surreal.PROJECT),
                      ("ritual", surreal.RITUAL), ("ask", surreal.RITUAL_ASK),
                      ("ai note", surreal.AI_NOTE)):
        check(f"identity {name} is Thai", has_thai(val), val)
    check("vocabulary is non-empty",
          len(surreal.ORDINARY) >= 8 and len(surreal.IMPOSSIBLE) >= 8)
    check("every ordinary thing is Thai",
          all(has_thai(x) for x in surreal.ORDINARY))
    check("every impossible feeling is Thai",
          all(has_thai(x) for x in surreal.IMPOSSIBLE))

    slugs = ["01-khon-di-thi-chak-pai", "02-rak-thi-mai-mi-wan-chop",
             "07-huachai-si-thao", "11-dao-nai-mueang", "29-takorn-kong-fa"]
    for slug in slugs:
        thing, feeling = surreal.pair(slug)
        check(f"{slug}: pair comes from the closed vocabulary",
              thing in surreal.ORDINARY and feeling in surreal.IMPOSSIBLE)
        check(f"{slug}: pair is deterministic",
              surreal.pair(slug) == surreal.pair(slug))
        check(f"{slug}: exhibit number is stable",
              surreal.exhibit_no(slug) == surreal.exhibit_no(slug))

    # The caption is the same project on both surfaces, disclosed and safe.
    for slug in slugs[:2]:
        for platform in ("facebook", "tiktok"):
            cap = surreal.caption(slug, platform, "เพลงทดสอบ")
            check(f"{slug}/{platform}: caption is Thai", has_thai(cap))
            check(f"{slug}/{platform}: caption discloses AI",
                  surreal.AI_NOTE in cap)
            check(f"{slug}/{platform}: caption carries the ritual ask",
                  surreal.RITUAL_ASK in cap)
            check(f"{slug}/{platform}: caption is rule-safe",
                  surreal.claim_problem(cap) is None)
    # Cross-promo must differ by surface, or the two feeds read as one duplicate.
    check("facebook and tiktok captions differ",
          surreal.caption(slugs[0], "facebook") != surreal.caption(slugs[0], "tiktok"))

    # The guard actually guards.
    check("a banned over-claim is refused",
          surreal.claim_problem("รวยแน่นอน กับเพลงนี้") == "รวยแน่นอน")
    check("a clean line passes the guard",
          surreal.claim_problem("ตู้เย็น : ความคิดถึงที่ไม่เคยส่งถึง") is None)

    # The art varies per song, or the grid is the look-alike pattern the panel
    # warned about. Five recipes exist and the songs must not all draw one.
    check("recipes are defined", len(ms.RECIPES) >= 4, f"{len(ms.RECIPES)}")
    used = {ms.recipe_for(s) for s in slugs}
    check("recipe varies across songs", len(used) >= 3, f"{used}")
    check("every chosen recipe exists",
          all(ms.recipe_for(s) in ms.RECIPES for s in slugs))

    # The burned label is positioned (or libass overprints), emoji-free (the
    # bundled Thai font has no emoji glyph) and inside the frame.
    ass = ms.build_ass(slugs[0], "เพลงทดสอบ", 28.0)
    dialogue = [ln for ln in ass.splitlines() if ln.startswith("Dialogue:")]
    check("label draws number + title + feeling + ask + note",
          len(dialogue) >= 5, f"{len(dialogue)}")
    check("every label line is positioned", all("\\pos(" in ln for ln in dialogue))
    ys = [int(re.search(r"\\pos\(\d+,(\d+)\)", ln).group(1)) for ln in dialogue]
    check("label lines do not share a y", len(set(ys)) == len(ys), f"{ys}")
    check("label lines are inside the frame", all(0 < y < ms.H for y in ys))
    check("no emoji in the burned text",
          not any(0x1F300 <= ord(c) <= 0x1FAFF for c in ass))
    check("clip stays short", ms.MAX_SECONDS <= 30.0, f"{ms.MAX_SECONDS}")


def test_affiliate_release() -> None:
    """The affiliate lane must exist on the YouTube rail, not only the card renderer.

    The card renderer (`make_affiliate_short`) could already build a clip, but
    nothing put one on the channel: `release.plan` knew only `song`, `short` and
    `karaoke`. So every Short stayed a song and the purchase-intent funnel had no
    content of its own — the exact gap the 2026-11-05 advisor gate named. This
    pins the lane: the cards are read from the tracked work file (they went
    missing once because that file was gitignored), the description carries the
    surface's link above the fold with the mandatory disclosure, and the title
    fits YouTube's shape.
    """
    section("affiliate release lane")
    import release
    import monetize

    cards = release.affiliate_cards()
    check("product cards are readable from the tracked file", len(cards) >= 5,
          f"{len(cards)}")
    title, _desc = release.playlist_for("affiliate")
    check("affiliate playlist names the category", "หูฟัง" in title, title)

    if not cards:
        return
    monetize.CACHE = None
    t, d, tags = release.describe_affiliate(cards[0])
    # Search-first packaging (2026-11-09): `ของน่าซื้อ` is a souvenir/gift term in
    # Google Suggest, not a headphone-buying term, so the title must carry the
    # card's real query instead. Search matches on the query's terms, so every
    # token of `search` must appear in the title; a title that dropped one would
    # silently stop matching the funnel's only free discovery path.
    q_tokens = [w for w in cards[0].get("search", "").split() if w]
    missing = [w for w in q_tokens if w not in t]
    check("affiliate title covers the card's search query", not missing,
          f"missing {missing} from {t}")
    check("affiliate title fits 60 chars", len(t) <= 60, f"{len(t)}: {t}")
    check("affiliate title is a Short", "#Shorts" in t, t)
    check("affiliate description carries the youtube link",
          monetize.link("youtube") in d)
    check("affiliate description discloses the affiliate link",
          "ลิงก์พันธมิตร" in d)
    # A Short's description URL is not tappable (2026-11-05 advisor panel, 3/3),
    # so the above-the-fold block must carry the *disclosure* and a CTA pointing
    # at the profile link; the tracked URL stays as a copyable fallback.
    head = "\n".join(d.splitlines()[:2])
    check("affiliate disclosure is above the fold", "ลิงก์พันธมิตร" in head,
          repr(head))
    check("affiliate CTA points at the profile link",
          "โปรไฟล์" in head, repr(head))
    check("affiliate link is above the fold", monetize.link("youtube") in head,
          repr(head))
    check("affiliate description is Thai", has_thai(d))
    check("affiliate tags are present", bool(tags))


def test_affiliate_render_rail() -> None:
    """The product cards must have a *producer*, not only consumers.

    `release.py` and `crosspost.py` both read `library/affiliate/short-aff-*.mp4`,
    but nothing ever rendered those clips, so the directory stayed empty and the
    funnel published nothing — the consumers were wired to a producer that did
    not exist. This pins the rail that closes the loop: a workflow that renders
    the cards and pushes them to the media store before the posting rails run.
    """
    section("affiliate render rail")
    wf = (ROOT.parent / ".github" / "workflows" / "ax-music-affiliate-render.yml")
    check("the affiliate render rail exists", wf.exists(), str(wf))
    if not wf.exists():
        return
    src = wf.read_text(encoding="utf-8")
    check("the rail renders the cards", "make_affiliate_short.py --all" in src)
    check("the rail pulls the song masters", "pull_media.py --only songs" in src)
    check("the rail pushes the clips to the media store",
          "publish_media.py" in src)
    check("the rail feeds the crosspost queue",
          "crosspost.py --merge-queue" in src)

    # The consumers point at the same directory the producer writes, or the loop
    # is still broken in a way a passing render would not reveal.
    import release
    import crosspost
    check("release reads the affiliate clips", release.AFF_DIR.name == "affiliate",
          str(release.AFF_DIR))
    check("crosspost reads the affiliate clips",
          crosspost.AFF_SHORTS.name == "affiliate", str(crosspost.AFF_SHORTS))


def test_plan_rotates_songs() -> None:
    """Consecutive Shorts must come from *different* songs.

    The 2026-11-05 advisor panel (3/3) on the growth stall: three numbered
    choruses of one song uploaded back to back read as the same clip three times
    and give a viewer no reason to follow. The plan interleaves one chorus per
    song per round, so a day's song Shorts are distinct songs. This pins that,
    because the old plan appended every hook of one song before moving on.
    """
    section("release plan rotation")
    import release

    plan = release.plan(2)
    song_shorts = [i["slug"] for i in plan if i["kind"] == "short"]
    if len(song_shorts) < 2:
        print("  skip (fewer than two Shorts planned)")
        return
    consecutive = [a for a, b in zip(song_shorts, song_shorts[1:]) if a == b]
    check("no two consecutive Shorts are the same song", not consecutive,
          f"repeats: {sorted(set(consecutive))}")

    # --kind / --slug select the pending queue. A loop variable named `slug`
    # shadowed the `slug` argument and filtered on the last song in the list, so
    # `--slug X` returned nothing at all. Assert the selectors match what they
    # claim to, not just that they run.
    songs = release.plan(0, kind="song")
    check("kind=song returns only song items",
          songs and all(i["kind"] == "song" for i in songs), f"{len(songs)} items")
    if songs:
        one = release.plan(0, kind="song", slug=songs[0]["slug"])
        check("slug selects exactly that one song",
              len(one) == 1 and one[0]["slug"] == songs[0]["slug"],
              f"got {[i['slug'] for i in one]}")
        check("a slug that is not pending returns nothing",
              release.plan(0, kind="song", slug="no-such-song") == [])


def test_priority_pin() -> None:
    """A pinned song's release leads the plan, without breaking the rotation.

    K hands over one finished song and says "post it now"; the normal rotation
    would put it days behind the catalogue. The pin promotes that song's main
    release and its first Short to the front, and leaves the rest of the queue in
    order. Pin *only* reorders — it must not change the item count.
    """
    section("release priority pin")
    import release

    pins = release.pinned_songs()
    base = release.plan(0)
    if not pins:
        print("  skip (no pinned song right now)")
        return
    pinned = pins[0]
    # A pin is only live while the song's main release is still pending: once it
    # is uploaded the file is inert and the song's remaining Shorts fall back
    # into their rotation slots (see `_pin_front` / `plan`). The automation can
    # publish the pinned song between runs, so check which state is current
    # instead of assuming the pin is still pending.
    if not any(i["slug"] == pinned and i["kind"] == "song" for i in base):
        print(f"  skip ({pinned} already released — the pin is inert)")
        return
    first = base[0]
    check("a pinned song leads the plan",
          first["slug"] == pinned, f"head is {first['slug']}")
    check("the pinned song's main release is first",
          first["kind"] == "song", f"head kind is {first['kind']}")
    check("the pinned song's first Short is second",
          base[1]["slug"] == pinned and base[1]["kind"] == "short",
          f"second is {base[1]['slug']}/{base[1]['kind']}")
    shorts = [i["slug"] for i in base if i["kind"] == "short"]
    consecutive = [a for a, b in zip(shorts, shorts[1:]) if a == b]
    check("the pin does not put two same-song Shorts in a row",
          not consecutive, f"repeats: {sorted(set(consecutive))}")

    # The pin is a reorder, never an add or a drop: same items, same order
    # otherwise. Compare against a plan built with the pin file hidden.
    saved = release.PRIORITY
    try:
        release.PRIORITY = release.ROOT / "work" / "no-such-priority.json"
        unpinned = release.plan(0)
    finally:
        release.PRIORITY = saved
    check("the pin does not change how many items are planned",
          len(base) == len(unpinned), f"{len(base)} vs {len(unpinned)}")
    check("the pin does not change which items are planned",
          sorted((i["slug"], i["kind"], i.get("variant", "")) for i in base)
          == sorted((i["slug"], i["kind"], i.get("variant", "")) for i in unpinned))


def test_affiliate_reserve() -> None:
    """The replacement queue must not eat the product clips' slots.

    `pending_replacements.py` runs before `release.py` in the daily workflow and
    the two share one 6-upload ledger, so without a floor the 8-video backlog
    spends the whole day and no product clip is ever published — the funnel test
    never starts, which reads as "product clips don't work". The reserve holds
    AFFILIATE_RESERVE slots while any card is pending and releases them once
    every card is live, so a finished backlog is not starved either.
    """
    section("affiliate slot reserve")
    import release

    check("the reserve is set", release.AFFILIATE_RESERVE >= 2,
          f"{release.AFFILIATE_RESERVE}")
    check("every card is pending on an empty ledger",
          release.affiliate_pending({"released": []}) >= 5)
    live = {"released": [{"slug": c["id"], "kind": "affiliate"}
                         for c in release.affiliate_cards()]}
    check("the reserve releases once every card is live",
          release.affiliate_pending(live) == 0)
    # The replacement guard is what actually holds the slots; it must read the
    # reserve and the pending count, not just UPLOADS_PER_DAY.
    rv = (ROOT / "scripts" / "replace_video.py").read_text()
    check("replacements stop at the reserve", "AFFILIATE_RESERVE" in rv)
    check("the reserve is dynamic, not a fixed wall",
          "affiliate_pending" in rv)


def test_daily_release_saves_ledger_on_early_stop() -> None:
    """A batch that stops early must still write the ledger back.

    `daily_release.py` calls `release.py --next --count N`; `release.py` returns
    3 as soon as the day's upload slots are spent. The driver used to `return 0`
    on rc 3 *before* writing the ledger, so the items the batch had just
    uploaded were dropped — and the next run planned them again. The live
    symptom was the same affiliate product card uploaded on four consecutive
    runs (the channel carried the title 4 times) while the ledger on `main` held
    zero affiliate rows. The fix moves the write above the rc check, so the
    order of "save" and "decide what to report" is what this pins.
    """
    section("daily release saves the ledger on an early stop")
    src = (ROOT / "scripts" / "daily_release.py").read_text(encoding="utf-8")
    save = src.find("write_ledger(tok, after,")
    early = src.find("if rc == 3:")
    check("the driver writes the ledger at all", save != -1)
    check("the ledger write is before the rc==3 early return",
          save != -1 and early != -1 and save < early,
          f"save@{save} early@{early}")
    # The old code returned on rc 3 before the write; assert that exact shape is
    # gone, because a reorder that keeps both would pass the position check
    # above only by accident.
    check("rc==3 no longer returns before the ledger write",
          "if rc == 3:\n        print(\"quota already spent today" not in src)


def test_batch_survives_a_missing_asset() -> None:
    """A transient CDN error on one item must not end the whole batch.

    The 2026-11-08 release run died mid-item on a 504 from the media CDN while
    fetching a thumbnail: `fetch_media` had no retry, the traceback escaped
    `release_one`, and the batch uploaded nothing. The fix retries the fetch and
    treats a still-missing asset as rc 2, which the batch loop now skips rather
    than stops on. Pin both, because either half alone leaves the failure.
    """
    section("release batch survives a missing asset")
    src = (ROOT / "scripts" / "release.py").read_text(encoding="utf-8")
    fm = src[src.find("def fetch_media"):src.find("def release_one")]
    check("fetch_media retries the download", "for attempt in range" in fm)
    check("a failed fetch returns a missing path, not an exception",
          "return path" in fm and "raise" not in fm)
    loop = src[src.find("for i, item in enumerate(batch)"):]
    check("the batch loop skips an item with no media (rc 2)",
          "if rc == 2:" in loop and "continue" in loop)


def test_release_tolerates_transient_errors() -> None:
    """Transient API/CDN errors must not turn a live video into a lost one.

    A 409 SERVICE_UNAVAILABLE on the playlist insert and an
    `uploadLimitExceeded` from the channel cap are both things the rail sees in
    production. Neither is a defect: the first should be retried (the video is
    already uploaded), the second means the day is done and the workflow must
    stay green.
    """
    section("release tolerates transient errors")
    src = (ROOT / "scripts" / "release.py").read_text(encoding="utf-8")
    pl = src[src.find("def add_to_playlist"):src.find("def plan(")]
    check("a transient playlist error is retried",
          "for attempt in range" in pl and "409, 500, 502, 503, 504" in pl)
    check("a real quota 403 is not retried",
          "transient = e.code in" in pl)
    check("uploadLimitExceeded stops the day cleanly (rc 3)",
          "uploadLimitExceeded" in src and "return 3" in src)


def test_ledger_write_merges_instead_of_clobbering() -> None:
    """A ledger writer must union with `main`, never overwrite a stale snapshot.

    On 2026-11-08 the repair step's checkout predated the release step's write,
    so its whole-file PUT dropped songs 06/07/08 minutes after they were
    recorded. `merge_ledger_rows` is the fix: the union of rows, local winning on
    a shared id, remote keeping fields the local copy never saw.
    """
    section("ledger write merges instead of clobbering")
    import daily_release
    remote = {"released": [
        {"slug": "a", "kind": "short", "video_id": "AAA", "at": "t1"},
        {"slug": "b", "kind": "short", "video_id": "BBB", "at": "t2",
         "retired_at": "t3"},
    ], "playlists": {"ch3": "P1"}}
    local = {"released": [
        {"slug": "b", "kind": "short", "video_id": "BBB", "at": "t2"},
        {"slug": "c", "kind": "song", "video_id": "CCC", "at": "t4"},
    ], "playlists": {"ch3": "P1", "ch4": "P2"}}
    m = daily_release.merge_ledger_rows(local, remote)
    ids = {r["video_id"] for r in m["released"]}
    check("the remote-only row survives", "AAA" in ids)
    check("the local-only row is added", "CCC" in ids)
    check("a shared row is kept once", len(m["released"]) == 3)
    row_b = next(r for r in m["released"] if r["video_id"] == "BBB")
    check("the remote's extra field (retired_at) is kept",
          row_b.get("retired_at") == "t3")
    check("playlists are unioned",
          m["playlists"].get("ch4") == "P2" and m["playlists"].get("ch3") == "P1")
    src = (ROOT / "scripts" / "daily_release.py").read_text(encoding="utf-8")
    check("write_ledger calls the merge", "merge_ledger_rows(" in src)
    check("a sha race is retried", "for attempt in range(4)" in src)


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
    import release
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
    # The first two seconds decide the scroll, and the file used to open on the
    # cover art with no words. Every hook must now open on the *actual first sung
    # line* of that hook — not a generic question — so the frame every viewer
    # sees gives them something to read and sing along with (2026-11-07 panel:
    # lyric-led first, do not delay the song).
    meta, lines = make_short.load_lyrics("01-khon-di-thi-chak-pai")
    for hook in (1, 2, 3):
        ass = make_short.build_ass("01-khon-di-thi-chak-pai", lines, meta,
                                   20.0, 30.0, 178.7, hook=hook)
        card_lines = [ln for ln in ass.splitlines()
                      if "HookCard,,0,0,0,," in ln]
        check(f"hook {hook} opens with a card", len(card_lines) == 1)
        check(f"hook {hook} card starts at t=0",
              any(ln.startswith("Dialogue: 0,0.00,") for ln in card_lines))
        # The card is a real lyric line, not the generic hook title.
        body = card_lines[0].split(",,", 1)[1] if card_lines else ""
        check(f"hook {hook} card is a lyric, not a template",
              release.hook_title(hook) not in body and len(body) > 4)
    check("the card is short enough to earn the chorus",
          make_short.HOOK_CARD_SECONDS <= 3.0, f"{make_short.HOOK_CARD_SECONDS}")
    # K, 2026-11-07: a karaoke clip whose words do not match the song is worse
    # than none. The gate must refuse a missing mix, a mismatched length, and a
    # lyric with no chorus — and must accept a well-formed song.
    import tempfile, pathlib
    with tempfile.TemporaryDirectory() as td:
        lib = pathlib.Path(td) / "library"
        (lib / "songs").mkdir(parents=True)
        (lib / "covers").mkdir(parents=True)
        (lib / "songs" / "song-zz-test.mp3").write_bytes(b"x")
        (lib / "songs" / "karaoke-zz-test.mp3").write_bytes(b"x")
        (lib / "covers" / "cover-zz-test.jpg").write_bytes(b"x")
        (pathlib.Path(td) / "lyrics").mkdir()
        (pathlib.Path(td) / "lyrics" / "zz-test.txt").write_text(
            "[verse]\na\n[chorus]\nb\n", encoding="utf-8")
        old_root, old_dur = make_short.ROOT, make_short._duration
        try:
            make_short.ROOT = pathlib.Path(td)
            make_short._duration = lambda p: 200.0
            ok, why = make_short.karaoke_ok("zz-test")
            check("karaoke gate accepts a matched song", ok, why)
            make_short._duration = lambda p: 200.0 if p.name.startswith("song-") else 150.0
            ok, why = make_short.karaoke_ok("zz-test")
            check("karaoke gate refuses a length mismatch",
                  not ok and "length" in why, why)
            make_short._duration = lambda p: 200.0
            (pathlib.Path(td) / "lyrics" / "zz-test.txt").write_text(
                "[verse]\na\n", encoding="utf-8")
            ok, why = make_short.karaoke_ok("zz-test")
            check("karaoke gate refuses lyrics with no chorus",
                  not ok and "chorus" in why, why)
        finally:
            make_short.ROOT, make_short._duration = old_root, old_dur



def test_follow_end_card() -> None:
    section("follow ask (the only on-screen follow prompt)")
    import make_short
    import release

    # Shorts are the channel's only reach tool and their description sits below
    # the fold, so until 2026-11-09 a viewer was never asked to follow anywhere
    # they would see it. The fix is a short end card. Two things must stay true:
    # the ask exists, and it sits at the END so it cannot cost the first-two-
    # seconds decision that decides whether the clip is watched at all (the
    # 2026-11-09 panel: a whole-length button clutters the song and can pull
    # retention down, and retention is reach).
    check("there is a follow ask", bool(release.FOLLOW_ASK.strip()))
    check("the ask is Thai", has_thai(release.FOLLOW_ASK))
    check("the ask names the channel", "AERIS" in release.FOLLOW_ASK)
    # The card also carries the reason to return. Both advisors on the 2026-11-09
    # panel put "a clear reason to come back" first among the things that turn a
    # first-time viewer into a follower, so the ask is not a bare command.
    check("the card promises what is next", bool(release.FOLLOW_PROMISE.strip()))
    check("the promise is Thai", has_thai(release.FOLLOW_PROMISE))
    check("the promise has no emoji (burned font cannot render one)",
          not any(ord(c) > 0x2000 and not (0x0E00 <= ord(c) <= 0x0E7F)
                  for c in release.FOLLOW_PROMISE))

    meta, lines = make_short.load_lyrics("01-khon-di-thi-chak-pai")
    length = 58.0
    ass = make_short.build_ass("01-khon-di-thi-chak-pai", lines, meta,
                               20.0, length, 178.7)
    follow = [ln for ln in ass.splitlines() if "Follow,,0,0,0,," in ln]
    check("the end card is drawn", len(follow) == 1)
    if follow:
        fields = follow[0].split(",", 3)
        start_s = fields[1]
        parts = start_s.split(":")[2].split(".")
        secs = int(parts[0]) + int(parts[1]) / 100.0
        check("the ask lands in the last seconds", secs >= length - 3.5,
              f"{start_s} of {length:.1f}s")
        check("the ask carries the copy", release.FOLLOW_ASK in follow[0])
    promise = [ln for ln in ass.splitlines() if "FollowSub,,0,0,0,," in ln]
    check("the promise line is drawn with the ask", len(promise) == 1)
    if promise:
        check("the promise carries the copy",
              release.FOLLOW_PROMISE in promise[0])
    check("the ask is held briefly, not the whole clip",
          make_short.FOLLOW_CARD_SECONDS <= 3.0,
          f"{make_short.FOLLOW_CARD_SECONDS}")
    # No emoji: the burned font is Noto Sans Thai, which has no emoji glyph.
    check("the ask has no emoji (burned font cannot render one)",
          not any(ord(c) > 0x2000 and not (0x0E00 <= ord(c) <= 0x0E7F)
                  for c in release.FOLLOW_ASK))
    # A clip too short to hold the card must simply omit it, not clip it.
    short = make_short.build_ass("01-khon-di-thi-chak-pai", lines, meta,
                                 20.0, 2.0, 178.7)
    check("a 2s clip omits the card rather than cramming it",
          "Follow,,0,0,0,," not in short)


def test_ambient_loop() -> None:
    section("ambient/sleep lane (the million-view container)")
    import ambient_loop as A

    # The 2026-11-09 scan: sleep/ambient loops of 8-12 hours do 100-221M views
    # while a 4-minute single does ~500. This lane builds that container from a
    # keyless synth bed, so it must not need a login and must not stretch runtime
    # by re-encoding audio for hours.
    for pname, preset in A.PRESETS.items():
        check(f"{pname}: title is Thai", has_thai(preset["title"]))
        check(f"{pname}: title states the length", "{hours}" in preset["title"])
        check(f"{pname}: has a mood preset", preset["mood"] in ("calm", "warm", "mystic"))

    # An 8-hour plan, built without rendering.
    p = A.plan("sleep", mood="calm", key="C", minutes=480, rain=True,
               title_tmpl=A.PRESETS["sleep"]["title"],
               use_case=A.PRESETS["sleep"]["use_case"], stem="ambient-sleep")
    check("the plan names an 8-hour title", "8 ชั่วโมง" in p["title"], p["title"])
    check("the plan targets the requested length",
          f"{480 * 60:.3f}" in " ".join(p["cmd"]), "missing -t 28800")
    # The bed is a short loop tiled to length, not an 8-hour synthesis.
    check("the bed is stream-looped, not re-rendered long",
          "-stream_loop" in p["cmd"])
    check("one bed is looped when there is no rain",
          A.plan("sleep", mood="calm", key="C", minutes=480, rain=False,
                 title_tmpl=A.PRESETS["sleep"]["title"],
                 use_case="x", stem="ambient-sleep")["cmd"].count("-stream_loop") == 1)
    check("rain adds a second looped bed", p["cmd"].count("-stream_loop") == 2)
    check("the picture is a single held still", "-loop" in p["cmd"])
    # The still does not need 25 fps; a held frame at 1 fps keeps an 8-hour
    # encode to minutes and the file to a few hundred MB.
    check("the still is held at 1 fps", "1" == str(A.FPS))
    check("the description says what it is", has_thai(p["desc"]))
    check("the stem keys the output path", p["out"].name == "ambient-sleep.mp4")
    # A stem mismatch here is exactly the bug that made the CLI report success
    # while checking a file it never wrote.
    p2 = A.plan("เพลงกล่อมนอน", mood="calm", key="C", minutes=480, rain=True,
                title_tmpl=A.PRESETS["sleep"]["title"], use_case="x",
                stem="ambient-sleep")
    check("a Thai display name does not change the output path",
          p2["out"].name == "ambient-sleep.mp4")

    # The title counts hours, and the renderer must say a whole number for 8h.
    check("8h renders as '8', not '8.0'", A._hours_label(480) == "8")
    check("a 90-min loop still reads honestly", A._hours_label(90) == "1.5")

    # The bed is real instruments now, not a sine drone. K (2026-11-09) rejected
    # the ffmpeg synth as "fake"; `soundfont` renders a SoundFont of recorded
    # instruments through fluidsynth. The plan must loop *that* bed.
    check("the plan loops the instrument bed, not the old synth bed",
          "instrument-" in " ".join(p["cmd"]), "instrument bed not in plan")
    # A looping bed must not fade per tile, or the volume dips once a loop. The
    # fade belongs on the finished video, so the plan carries one in/out at the
    # very ends and the bed renderer (checked below) carries none.
    check("the finished video fades at its ends",
          "afade" in " ".join(p["cmd"]))
    # Seamless loop: the wrap is crossfaded (tail blended into head). The stitch
    # is now exact arithmetic in `soundfont.crossfade_loop`, so check that the
    # wrap joins adjacent samples instead of a filter string.
    import soundfont as SF
    import numpy as _np
    _take = _np.sin(_np.linspace(0, 40, 44100 * 8, dtype="<f4"))[:, None]
    _loop = SF.crossfade_loop(_take, 1.5)
    _seam = abs(float(_loop[0, 0] - _loop[-1, 0]))
    check("the crossfade makes the wrap seamless", _seam < 1e-4, f"seam={_seam:.6f}")
    check("the crossfade shortens the loop by the xfade",
          abs(_loop.shape[0] - (44100 * 8 - int(1.5 * 44100))) <= 1)
    # The bed is loud enough to actually be heard: the first version sat at
    # -32 LUFS, which is barely audible. The normaliser target must be in the
    # source, not only in a docstring.
    import inspect
    check("the bed is normalised to a real target",
          "loudnorm=I=-20" in inspect.getsource(SF.render_bed))
    check("the bed renderer does not fade per tile",
          "afade" not in inspect.getsource(SF.render_bed))

    try:
        A.plan("x", mood="calm", key="C", minutes=0, rain=False,
               title_tmpl="{hours}", use_case="", stem="s")
        check("a zero-length plan is refused", False)
    except ValueError:
        check("a zero-length plan is refused", True)


def test_soundfont_renderer() -> None:
    section("soundfont (real-instrument bed, K rejected the tone synth)")
    import soundfont as SF

    # Every mood the ambient lane offers must have a preset, or a preset that
    # asks for a mood the renderer does not know dies mid-render.
    for mood in ("calm", "warm", "sad", "hopeful", "mystic", "epic"):
        check(f"mood {mood} has an instrument preset", mood in SF.MOODS)

    # The timbres must be real GM programs, not a raw oscillator. A program of
    # 0 (Acoustic Grand) is fine; what is NOT fine is a preset that names a
    # synth lead/effect, which is the "fake" sound K asked us to stop using.
    SYNTHY = {80, 81, 82, 83, 84, 85, 86, 87, 88, 89, 90, 91, 92, 93, 94, 95,
              96, 97, 98, 99, 100, 101, 102, 103}
    for mood, preset in SF.MOODS.items():
        progs = [preset[k] for k in ("melody", "pad", "bass", "arp") if k in preset]
        check(f"{mood} uses only real-instrument programs",
              all(p not in SYNTHY for p in progs), f"{progs}")

    # A SoundFont must be discoverable, or every render fails at the sampler.
    sf = SF.find_soundfont()
    check("a SoundFont is installed and found", bool(sf) and Path(sf).exists(), sf)

    # build_midi is pure (no fluidsynth) and its reported length must match the
    # requested bar count, or a bed comes out the wrong length.
    import tempfile
    with tempfile.TemporaryDirectory() as td:
        info = SF.build_midi("calm", bars=4, path=Path(td) / "t.mid")
        check("build_midi reports 4 bars", info["bars"] == 4)
        beat = 60.0 / info["bpm"]
        check("build_midi length matches the bars", abs(info["seconds"] - 16 * beat) < 1e-6)
        check("the midi file was written", (Path(td) / "t.mid").stat().st_size > 0)

    # The crossfade is the seamless-loop fix: the wrap must join adjacent
    # samples, and the loop must be shorter than the source by exactly the xfade.
    x = np.sin(np.linspace(0, 40, 44100 * 6, dtype="<f4"))[:, None]
    loop = SF.crossfade_loop(x, 1.5)
    seam = abs(float(loop[0, 0] - loop[-1, 0]))
    check("the crossfade wrap is seamless", seam < 1e-4, f"seam={seam:.6f}")
    check("the crossfade trims exactly the xfade",
          abs(loop.shape[0] - (44100 * 6 - int(1.5 * 44100))) <= 1)

    # render_bed must not fade per tile (a fade dips the volume once a loop) and
    # must normalise to a real, audible target.
    import inspect
    src = inspect.getsource(SF.render_bed)
    check("render_bed does not fade per tile", "afade" not in src)
    check("render_bed normalises to a real target", "loudnorm=I=-20" in src)


def test_refresh_sleep_video() -> None:
    section("refresh sleep video (replace the old synth render once)")
    import refresh_sleep_video as R

    # Nothing live yet -> the once-step owns it, the refresh must not act.
    check("no state -> skip",
          R.decide(None, 480, True)["action"] == "skip")
    # Already replaced -> skip, so a retry never double-uploads.
    check("already soundfont -> skip",
          R.decide({"video_id": "x", "instrument": "soundfont"}, 480, True)["action"]
          == "skip")
    # The old synth render -> replace.
    check("old synth + render present -> replace",
          R.decide({"video_id": "gmsfqVjSsTo"}, 480, True)["action"] == "replace")
    # A missing or too-short render must never trigger an upload.
    check("no render on disk -> skip",
          R.decide({"video_id": "x"}, 0, False)["action"] == "skip")
    check("a short render -> skip",
          R.decide({"video_id": "x"}, 30, True)["action"] == "skip")
    # The decision carries the id it means to delete.
    check("the decision names the old id",
          R.decide({"video_id": "gmsfqVjSsTo"}, 480, True)["old"] == "gmsfqVjSsTo")


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


def test_youtube_quota_ledger() -> None:
    section("YouTube shared quota (WIRING: an upload must never ship thumbnail-less)")
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import importlib
    import yt_quota
    importlib.reload(yt_quota)
    from datetime import datetime, timezone

    # The pool is 10,000 units/day and the shared calls are priced from the
    # official table. A wrong price here is what let the pool be mis-budgeted.
    check("the shared pool is 10,000 units", yt_quota.POOL == 10_000)
    check("a thumbnail costs 50 units", yt_quota.COST["thumbnails.set"] == 50)
    check("a playlist insert costs 50 units",
          yt_quota.COST["playlistItems.insert"] == 50)
    check("videos.insert is not priced against the shared pool",
          "videos.insert" not in yt_quota.COST)
    # One release = six videos x (thumbnail + playlist) with margin.
    check("a release reserves at least 100 units per video",
          yt_quota.UNITS_PER_RELEASE >= 100)

    # The day key must roll over on Pacific midnight, not UTC: a UTC key
    # overcounts by the offset and refuses a legal upload.
    day = yt_quota.pac_day(datetime(2026, 11, 7, 6, 30, tzinfo=timezone.utc))
    check("06:30 UTC is still the previous Pacific day", day == "2026-11-06")
    day2 = yt_quota.pac_day(datetime(2026, 11, 7, 8, 30, tzinfo=timezone.utc))
    check("08:30 UTC is the new Pacific day", day2 == "2026-11-07")

    # A fresh day can afford a batch; a spent day cannot. This is the whole gate.
    d = {"days": {}}
    check("an empty ledger can afford a release",
          yt_quota.can_afford(600, d, "2026-11-07"))
    spent = {"days": {"2026-11-07": {"units": 9_800, "calls": {}}}}
    check("a nearly spent pool refuses a release",
          not yt_quota.can_afford(600, spent, "2026-11-07"))
    check("a reserve on a spent pool fails",
          not yt_quota.reserve(600, "x", commit_it=False, data=spent, day="2026-11-07"))

    # record() prices a call at the official cost and never double-counts a
    # reservation (reserve is a pre-flight, not a counter).
    d = {"days": {}}
    yt_quota.reserve(600, "batch", commit_it=False, data=d, day="2026-11-07")
    check("a reservation does not spend the pool",
          yt_quota.used(d, "2026-11-07") == 0)
    yt_quota.record("thumbnails.set", data=d, day="2026-11-07")
    yt_quota.record("playlistItems.insert", data=d, day="2026-11-07")
    check("recording two shared calls costs 100 units",
          yt_quota.used(d, "2026-11-07") == 100)
    check("remaining reflects the spend",
          yt_quota.remaining(d, "2026-11-07") == 9_900)

    # The release must reserve before it uploads, and refuse when it cannot.
    rel = (ROOT / "scripts" / "release.py").read_text(encoding="utf-8")
    check("release reserves the pool before uploading",
          "yt_quota.reserve(" in rel and rel.index("yt_quota.reserve(") < rel.index("for i, item in enumerate(batch)"))
    check("release refuses a batch it cannot cover", "return 3" in rel)
    check("release prices the thumbnail it set", 'yt_quota.record("thumbnails.set")' in rel)
    check("release prices the playlist insert",
          'yt_quota.record("playlistItems.insert")' in rel)

    # The repair is gated on the same pool, or it just re-fails on a spent day.
    fix = (ROOT / "scripts" / "fix_thumbnails.py").read_text(encoding="utf-8")
    check("the repair checks the pool before it runs",
          "yt_quota.remaining()" in fix)
    check("the repair prices its thumbnail", 'yt_quota.record("thumbnails.set")' in fix)

    # The ledger is worthless if git cannot carry it between workers. `check-ignore`
    # returns 0 when the *last* matching rule is a negation, so read the rule text,
    # not the exit code: the file must be re-included and not caught by work/*.
    gi = (ROOT.parent / ".gitignore").read_text(encoding="utf-8")
    check("the quota ledger is tracked", "!music938-1/work/yt-quota.json" in gi)
    out = subprocess.run(
        ["git", "check-ignore", "-v", "--no-index",
         "music938-1/work/yt-quota.json"],
        cwd=str(ROOT.parent), capture_output=True, text=True)
    check("the last gitignore rule for the ledger is the re-include",
          "!music938-1/work/yt-quota.json" in out.stdout, out.stdout.strip()[:100])


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
    # A `# GENRE:` id alone is not a writing brief — Gemini returns the same
    # generic เพื่อชีวิต lyric. A genre with a brief must actually reach the
    # prompt, and a genre without one must not gain a stray line.
    import ai_lyrics
    lt = ai_lyrics.build_prompt({"TITLE": "t", "GENRE": "lukthung"})
    check("lukthung brief reaches the prompt",
          "แนวนำทาง" in lt and "ลูกทุ่งไทย" in lt)
    rock = ai_lyrics.build_prompt({"TITLE": "t", "GENRE": "rock"})
    check("rock brief reaches the prompt",
          "แนวนำทาง" in rock and "ร็อกไทย" in rock)
    plain = ai_lyrics.build_prompt({"TITLE": "t", "MOOD": "sad"})
    check("a mood-only song gets no genre brief", "แนวนำทาง" not in plain)


def test_arrangement_no_repeat() -> None:
    section("arrangement (WIRING: 'ดนตรีห้ามซ้ำกัน' + pentatonic)")
    import arrangement as A
    import flow_song as F

    cat = A.slugs()
    # K, 2026-11-06: no two songs may share the same music. Every song gets its
    # own signature and the check must pass, or two songs ship identical.
    used: dict[str, list[str]] = {}
    for s in cat:
        used.setdefault(A.signature_for(s, cat)["id"], []).append(s)
    dupes = {k: v for k, v in used.items() if len(v) > 1}
    check("every song has its own arrangement", not dupes, str(dupes))

    # The arrangement must be coherent with the genre: a rock song must never be
    # handed a khaen loop, which is what a global round-robin produced.
    for s in cat:
        g = (A.header(s).get("genre") or "").lower()
        if not g:
            continue
        a = A.signature_for(s, cat)
        check(f"{s}: arrangement matches its genre", a.get("genre") == g,
              f"{g} -> {a.get('genre')}")

    # Every arrangement needs all three parts or the Flow prompt is thin.
    for a in A.signatures():
        check(f"{a['id']}: has instruments", bool(a.get("instruments")))
        check(f"{a['id']}: has groove", bool(a.get("groove")))
        check(f"{a['id']}: has mix", bool(a.get("mix")))
    ids = [a["id"] for a in A.signatures()]
    check("arrangement ids are unique", len(ids) == len(set(ids)))
    # Every planned genre must own arrangements, or a new genre silently borrows
    # another genre's sound (which is how a lofi song came out lukthung).
    import genres as G
    planned = {g["id"] for g in G.genres()}
    have = {a.get("genre") for a in A.signatures()}
    check("every planned genre has its own arrangements",
          planned <= have, str(sorted(planned - have)))

    # Pentatonic: every song resolves to a scale and it reaches the style prompt.
    for s in cat:
        scale = A.scale_for(s)
        check(f"{s}: has a pentatonic scale", scale in A.PENTATONIC)
        style = F.style_for(F.parse_lyric(ROOT / "lyrics" / f"{s}.txt")["meta"], s)
        check(f"{s}: style asks for pentatonic", "pentatonic" in style.lower())
        a = A.signature_for(s, cat)
        # The mix phrase is always appended and never collides with a genre
        # style, so it proves the song's own arrangement reached the prompt.
        check(f"{s}: style carries its arrangement", a["mix"].lower() in style.lower())
    # A mood-only song (no genre) still gets a scale from its mood.
    check("sad -> minor pentatonic", A.scale_for("01-khon-di-thi-chak-pai") == "minor")
    check("hopeful -> major pentatonic",
          A.scale_for("04-saeng-chao-wan-mai") == "major")
    # The dedupe must not leave a doubled clause in the prompt.
    style = F.style_for(F.parse_lyric(ROOT / "lyrics" / "24-yut-mai-yom.txt")["meta"],
                        "24-yut-mai-yom")
    parts = [p.strip().lower() for p in style.split(", ")]
    check("no duplicated clause in the style prompt",
          len(parts) == len(set(parts)), str([p for p in parts if parts.count(p) > 1]))


def test_song_analysis() -> None:
    section("song analysis (WIRING: the measured songbook)")
    import analyze_songs as S

    rows = [S.analyse(S.parse(p)) for p in sorted((ROOT / "lyrics").glob("*.txt"))]
    check("analysis covers the catalogue", len(rows) >= 20, str(len(rows)))
    for r in rows:
        check(f"{r['slug']}: has a structure", bool(r["structure"]))
        check(f"{r['slug']}: hook measured", bool(r["hook"]))
        check(f"{r['slug']}: syllable count is sane", 3 <= r["syl_mean"] <= 12,
              f"{r['syl_mean']}")
    # The measured problem K is reacting to: the old catalogue had no genre tag,
    # so the fix must show up as genre coverage, not as a claim in a doc. The five
    # already-released songs keep their original headerless form (their audio
    # cannot be re-rendered), so the bar is the 17 unreleased songs.
    import rework_catalog as R
    pending = [r for r in rows if r["slug"] not in R.RELEASED]
    tagged = [r for r in pending if r["genre"] != "(none)"]
    check("every unreleased song is genre-tagged", len(tagged) == len(pending),
          f"{len(tagged)}/{len(pending)} tagged")
    # The floor, not a frozen number: the produce loop adds songs, and a test
    # that pins the count turns every new song into a false failure.
    check("the unreleased catalogue has 17+ songs", len(pending) >= 17, str(len(pending)))


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


def test_ai_covers() -> None:
    """The AI cover path: the model paints, Pillow writes the Thai title.

    The rule that matters is the one the advisor panel gave: never let the image
    model spell the title, because it gets Thai wrong and the spelling is the one
    thing a cover must not fumble. So the prompt must *forbid* text and must not
    contain the title, and the title must instead be composited by PIL.
    """
    section("ai covers (prompt forbids text; PIL draws the title)")
    import ai_covers

    names = [n for n, _ in ai_covers.ART_DIRECTIONS]
    check("at least 6 art directions", len(names) >= 6, f"have {len(names)}")
    check("art directions are unique", len(set(names)) == len(names))

    suffix = ai_covers.PROMPT_SUFFIX.lower()
    for bad in ("no text", "no letters", "no words"):
        check(f"prompt forbids {bad!r}", bad in suffix)
    check("prompt asks for 16:9", "16:9" in suffix)

    # Deterministic, and the title is never handed to the model.
    a = ai_covers._direction("24-yut-mai-yom", None)[0]
    b = ai_covers._direction("24-yut-mai-yom", None)[0]
    check("direction is deterministic per slug", a == b, f"{a} != {b}")
    check("direction is one of the known scenes", a in names)
    meta = {"mood": "calm", "genre": "lukthung"}
    prompt = ai_covers._prompt("24-yut-mai-yom", meta, "portal")
    check("genre reaches the prompt", "lukthung" in prompt)
    check("Thai title is NOT in the prompt", "หยุด" not in prompt)

    # The default backend must be the free, key-less one: Gemini's free image
    # quota runs out mid-batch and then it answers in prose. Pin the host so a
    # refactor cannot quietly make a login-only service the default.
    import inspect
    sig = inspect.signature(ai_covers.build)
    check("default backend is pollinations",
          sig.parameters["backend"].default == "pollinations")
    check("pollinations host is image.pollinations.ai",
          "image.pollinations.ai" in inspect.getsource(ai_covers._fetch_pollinations))

    # _compose must produce a real 16:9 frame with Thai text on it.
    from PIL import Image, ImageDraw, ImageStat
    bg = Image.new("RGB", (1024, 572), (10, 12, 30))
    d = ImageDraw.Draw(bg)
    for x in range(0, 1024, 8):
        d.line([(x, 0), (x, 572)], fill=(x % 255, 40, 120))
    out = ai_covers._compose(bg, "หยุดไม่อยู่", kind="song", subtitle="ทดสอบ")
    check("cover is 1280x720", out.size == (1280, 720), f"{out.size}")
    sd = ImageStat.Stat(out.convert("L").resize((64, 36))).stddev[0]
    check("composed cover has contrast", sd >= 21.7, f"std={sd:.1f}")


def test_thumbnail_repair() -> None:
    """A thumbnail lost to a spent quota must be repaired, and only those.

    `videos.insert` has its own bucket but `thumbnails.set` shares the 10,000-unit
    pool, so a late upload succeeds and its thumbnail 403s. Nothing retried it, so
    the video kept YouTube's auto frame forever. `release.py` now records
    `thumb_ok`, and `fix_thumbnails.py` repairs the false ones — assert it picks
    exactly those and leaves a good one alone.
    """
    section("thumbnail repair")
    import fix_thumbnails
    import release
    import yt_auth
    import yt_quota

    entries = [
        {"slug": "a", "kind": "song", "variant": "", "video_id": "V1", "thumb_ok": False},
        {"slug": "b", "kind": "song", "variant": "", "video_id": "V2", "thumb_ok": True},
        {"slug": "c", "kind": "short", "variant": "s", "video_id": "V3"},
        {"slug": "d", "kind": "song", "variant": "", "video_id": "V4",
         "thumb_ok": True, "playlist_ok": False},
    ]
    seen, saved, added = [], [], []
    real = (release.load_state, release.save_state, fix_thumbnails.thumb_for,
            yt_auth.access_token, fix_thumbnails.set_thumbnail, sys.argv,
            fix_thumbnails.in_playlist, release.add_to_playlist,
            yt_quota.remaining, yt_quota.record, yt_quota.commit)
    try:
        state = {"released": [dict(e) for e in entries],
                 "playlists": {"ch3:song": "PL1"}}
        release.load_state = lambda: state
        release.save_state = lambda s: saved.append(s)
        fix_thumbnails.thumb_for = lambda e: Path("/tmp/thumb.png")
        yt_auth.access_token = lambda ch: "tok"
        fix_thumbnails.set_thumbnail = lambda vid, path, tok: (seen.append(vid), (200, {}))[1]
        fix_thumbnails.in_playlist = lambda pid, vid, tok: False
        release.add_to_playlist = lambda pid, vid, ch: (added.append((pid, vid)), True)[1]
        # The quota gate must not depend on the live ledger, or the test would
        # pass or fail with whatever the day's real spend happens to be.
        yt_quota.remaining = lambda *a, **k: 10_000
        yt_quota.record = lambda *a, **k: 0
        yt_quota.commit = lambda *a, **k: True
        sys.argv = ["fix_thumbnails.py"]
        fix_thumbnails.main()
    finally:
        (release.load_state, release.save_state, fix_thumbnails.thumb_for,
         yt_auth.access_token, fix_thumbnails.set_thumbnail, sys.argv,
         fix_thumbnails.in_playlist, release.add_to_playlist,
         yt_quota.remaining, yt_quota.record, yt_quota.commit) = real

    check("only the entry with thumb_ok=False is repaired", seen == ["V1"], f"{seen}")
    check("an entry with no thumb_ok is left alone", "V3" not in seen, f"{seen}")
    check("the repaired entry is marked ok", saved and
          saved[-1]["released"][0]["thumb_ok"] is True)
    check("a lost playlist slot is refilled", added == [("PL1", "V4")], f"{added}")
    check("the refilled entry is marked ok", saved and
          saved[-1]["released"][3]["playlist_ok"] is True)


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
    # The compilation is the most-watched video, so its description must carry
    # the revenue ask. Before 2026-11-09 it had none, which is where the 0-click
    # affiliate funnel went wrong. The ask leads with the subscribe (the 1,000-sub
    # gate) and carries the Shopee link.
    check("description carries the subscribe ask",
          "sub_confirmation=1" in desc, desc[:120])
    check("description carries the Shopee link", "shopee" in desc.lower(),
          desc[:120])
    # render() used to rewrite the description as a bare tracklist, which
    # silently dropped the timestamps the title promises. It must keep chapters.
    render_body = (ROOT / "scripts" / "compile_album.py").read_text().split(
        "def render(", 1)[1].split("\ndef ", 1)[0]
    check("render keeps the chaptered description",
          "compilation_description" in render_body)


def test_compilation_cta_repair() -> None:
    """The live compilation's missing revenue ask must be repairable, safely.

    The compilation is the channel's most-watched video and the only long-form
    one whose description is clickable in-feed, but it shipped with no subscribe
    and no Shopee ask (found 2026-11-09, $500 funnel at 0 clicks). The repair
    inserts the CTA above the chapter list without disturbing the timestamps the
    `(เลือกเพลงฟังได้)` title promises, and it must be idempotent so the daily
    workflow step is a no-op once the video is healed.
    """
    section("compilation CTA repair")
    import importlib.util
    spec = importlib.util.spec_from_file_location(
        "fix_cta", ROOT / "scripts" / "fix_compilation_cta.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    bare = ("🎵 รวมเพลงไทย — รวม 16 เพลงไทย\n\n"
            "🤖 AERIS Music — ค่ายเพลง AI\n\n"
            "👉 กดเลือกเพลงที่อยากฟังได้จากรายการด้านล่าง\n\n"
            "⏱️ รายการเพลง\n00:00 01. คนดีที่จากไป\n03:48 02. รักที่ไม่มีวันจบ\n")
    check("a description without the link is flagged", mod._needs_cta(bare), "bare")
    import monetize
    healed = mod._insert_cta(bare, monetize.cta("youtube"))
    check("repair adds the Shopee link", "shopee" in healed.lower(), healed[:80])
    check("repair adds the subscribe ask",
          "sub_confirmation=1" in healed, healed[:80])
    check("repair keeps the 00:00 chapter", "\n00:00 " in healed, healed[:200])
    check("repair is idempotent", not mod._needs_cta(healed), "healed")
    # A second insert must not duplicate the block.
    twice = mod._insert_cta(healed, monetize.cta("youtube"))
    check("repair does not double-insert",
          twice.lower().count("shopee") == healed.lower().count("shopee"),
          str(twice.lower().count("shopee")))


def test_themed_compilations() -> None:
    """Themed albums must be disjoint and lead with a search intent.

    The 2026-11-08 competitor scan (10 real Thai channels, no API quota) found
    the winning channels publish many long-form compilations, each titled for a
    search intent. The lever only holds if the albums are genuinely different:
    if two themes share songs, we are re-titling one tracklist, which is what the
    advisor panel warned a channel-level originality review would punish. So the
    mood sets must not overlap, each theme must reach the honest track floor, and
    the title must carry the listening occasion.
    """
    section("themed compilations (competitor lever)")
    import compile_album
    check("at least three themes are defined", len(compile_album.THEMES) >= 3,
          str(list(compile_album.THEMES)))
    picked = {t: set(compile_album.pick(60, t)) for t in compile_album.THEMES}
    for a in compile_album.THEMES:
        for b in compile_album.THEMES:
            if a < b:
                overlap = picked[a] & picked[b]
                check(f"themes {a} and {b} share no song", not overlap,
                      str(sorted(overlap)))
    for t, slugs in picked.items():
        check(f"theme {t} reaches the honest floor",
              len(slugs) >= compile_album.MIN_THEME_TRACKS, f"{len(slugs)}")
    title = compile_album.compilation_title(
        compile_album.THEMES["chill"]["name"], 9,
        compile_album.THEMES["chill"]["use_case"])
    check("themed title leads with the occasion",
          title.startswith(compile_album.THEMES["chill"]["use_case"]), title)
    check("themed title keeps the honest promise",
          "เลือกเพลงฟังได้" in title, title)
    check("themed title fits 100 chars", len(title) <= 100, f"{len(title)}")


def test_song_title_search_intent() -> None:
    """A song title must name a search intent, not just a mood adjective.

    The scan's winners title for the listening moment ("ขับรถ ทำงาน ..."). The
    intent tail carries the genre keyword and the occasion; the mood tagline
    stays in the description. It must always fit the ~60-char truncation, falling
    back to the tagline when it would not.
    """
    section("song titles (search intent)")
    import release
    for slug in ("01-khon-di-thi-chak-pai", "05-fon-tok-nai-chai",
                 "06-doen-khon-diao", "09-phleng-khong-khon-nueai"):
        h = release.parse_lyrics(slug)
        mood = h.get("MOOD", "calm")
        title, _desc, _tags = release.describe(slug, "song", "")
        check(f"{slug}: title <= 60 chars", len(title) <= 60, f"{len(title)}: {title}")
        want = release.TITLE_INTENT.get(mood, "")
        check(f"{slug}: title carries the search intent", want in title, title)
    # A very long title keeps the tagline rather than truncating.
    long_th = "ก" * 55
    t = release.song_title(long_th, "เพลงเศร้า ที่เข้าใจความเสียใจ", "sad")
    check("long title falls back to the tagline", t.endswith("เพลงเศร้า ที่เข้าใจความเสียใจ"), t)


def test_competitor_scanner_parsers() -> None:
    """The no-quota channel scanner must parse the numbers real pages carry.

    Three bugs cost a debug cycle each on the first live run (2026-11-08) and
    none of them raised: a non-greedy regex truncated `ytInitialData`, the
    `videos` tab had moved to `lockupViewModel` so every renderer lookup came
    back empty, and the subscriber label is Thai so a leading-`\\d+` parse read
    "1.3 หมื่น" (13,000) as 1. This pins the parser behaviour on the exact strings
    the pages return.
    """
    section("competitor scanner (no-quota parsers)")
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import yt_public_scan as scan
    check("Thai พัน scales to thousands", scan._parse_int("ผู้ติดตาม 8.8 พัน คน") == 8800,
          str(scan._parse_int("ผู้ติดตาม 8.8 พัน คน")))
    check("Thai หมื่น scales to ten-thousands",
          scan._parse_int("ผู้ติดตาม 1.3 หมื่น คน") == 13000,
          str(scan._parse_int("ผู้ติดตาม 1.3 หมื่น คน")))
    check("Thai ล้าน scales to millions",
          scan._parse_int("ผู้ติดตาม 2.5 ล้าน คน") == 2500000,
          str(scan._parse_int("ผู้ติดตาม 2.5 ล้าน คน")))
    check("plain Thai count parses", scan._parse_int("ผู้ติดตาม 7 คน") == 7,
          str(scan._parse_int("ผู้ติดตาม 7 คน")))
    check("Latin M scales", scan._parse_int("1.2M subscribers") == 1200000,
          str(scan._parse_int("1.2M subscribers")))
    check("view count parses", scan._parse_int("1,234 views") == 1234)
    check("h:mm:ss converts to seconds", scan._hms("1:02:03") == 3723)
    check("m:ss converts to seconds", scan._hms("4:00") == 240)
    check("empty duration is None", scan._hms("") is None)
    # Brace matching must survive a nested object followed by a `};</script>`.
    html = 'var ytInitialData = {"a":{"b":1},"c":"};</script>"};</script>'
    data = scan.initial_data(html)
    check("brace-matched ytInitialData keeps the nested object",
          data.get("a", {}).get("b") == 1, str(data))


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
    sur = list((ROOT / "library" / "surreal").glob("surreal-*.mp4"))
    if not shorts:
        print("  skip (no shorts rendered yet)")
        return
    # Every song Short, affiliate card and surreal exhibit is queued on both
    # platforms; the Facebook-only photo and link formats are added on top of
    # that pair, so the count is the video items times two plus those extras.
    extras = [it for it in q if it.get("kind") in ("photo", "link")]
    check("every short is queued on both platforms",
          len(q) == (len(shorts) + len(aff) + len(sur)) * 2 + len(extras),
          f"{len(q)} vs ({len(shorts)}+{len(aff)}+{len(sur)})*2+{len(extras)}")
    check("ids are unique", len({it["id"] for it in q}) == len(q))

    # The Facebook-only formats exist and only on Facebook: a photo is a feed
    # post and a link post is a Shopee card, neither of which the TikTok video
    # API can publish, so neither may appear on the TikTok surface.
    photos = [it for it in q if it.get("kind") == "photo"]
    links = [it for it in q if it.get("kind") == "link"]
    check("cover-art photos are queued", len(photos) > 0, f"{len(photos)}")
    check("Shopee link posts are queued", len(links) > 0, f"{len(links)}")
    check("photo/link formats are Facebook-only",
          all(it["platform"] == "facebook" for it in photos + links))
    check("a photo item carries an image, not a video",
          all(it.get("image") and not it.get("video") for it in photos))
    check("a link item carries a link, not a file",
          all(it.get("link") and not it.get("video") for it in links))
    check("link caption carries the Shopee link and the ad disclosure",
          all("s.shopee.co.th" in it["caption"] and "โฆษณา" in it["caption"]
              for it in links))
    check("photo caption differs from that song's Reel caption",
          all(it["caption"] != crosspost.caption(it["slug"], "facebook", 1)
              for it in photos if not it["slug"].startswith("compilation")))

    # A karaoke Short must resolve to its song slug, not its whole stem, or the
    # caption reads "short-karaoke-01-..." and every link/lyric line is wrong.
    check("karaoke short resolves to its slug",
          crosspost._slug_of(Path("short-karaoke-01-khon-di-thi-chak-pai.mp4"))
          == "01-khon-di-thi-chak-pai")
    check("karaoke short carries no hook index",
          crosspost._hook_of("short-karaoke-01-khon-di-thi-chak-pai") == 0)

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
          len(left) == len(shorts) + len(aff) + len(sur) - 1,
          f"{len(left)}")

    # The absurdist exhibits (K's FB/TK rebrand) are captioned by the surreal
    # identity module: Thai, rule-safe, and AI-disclosed. They must be the same
    # project on both surfaces, so the caption comes from one function.
    sur_items = [it for it in q if it.get("kind") == "surreal"]
    if sur:
        check("surreal exhibits are queued on both platforms",
              len(sur_items) == len(sur) * 2, f"{len(sur_items)}")
        check("surreal caption carries the AI disclosure",
              all("AI" in it["caption"] for it in sur_items))
        check("surreal caption is Thai",
              all(any("\u0e00" <= ch <= "\u0e7f" for ch in it["caption"])
                  for it in sur_items))

    # A product card must not sit behind the whole song backlog: at the daily cap
    # a surface would not reach one for over a week. The build folds a card pair
    # in after every 6 items, and the later photo/link passes shift it by a few
    # slots, so it must still land in the first dozen.
    if aff_items:
        first_aff = min(i for i, it in enumerate(q) if it.get("kind") == "affiliate")
        check("the first affiliate card is near the front of the queue",
              first_aff <= 12, f"index {first_aff}")
        # Interleaving must not drop or duplicate anything.
        check("interleaving keeps every item exactly once",
              len({it["id"] for it in q}) == len(q))

    # The three Facebook formats must be spread through the queue, not bunched at
    # the front or the back: a run of Reels with all photos at the tail would
    # read as a wall of the same format.
    if photos:
        idx = [i for i, it in enumerate(q) if it.get("kind") == "photo"]
        check("photos are spread through the queue",
              idx[0] < len(q) // 3 and idx[-1] > len(q) * 2 // 3,
              f"{idx[0]}..{idx[-1]} of {len(q)}")

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

    # Facebook is API-only: with no token the rail must park, never open a browser
    # to a cookie session that dies and needs K. This is the guard that keeps K out.
    check("facebook is an API-only surface", "facebook" in crosspost.API_ONLY)
    check("api_poster returns None for facebook without a token",
          crosspost.api_poster("facebook") is None or
          crosspost.fb_graph.available())
    parked = src.split("if platform in API_ONLY and api is None:", 1)
    check("post() parks an API-only surface before opening any browser",
          len(parked) == 2 and "return 3" in parked[1].split("print(f\"posting", 1)[0])
    probe_body = src.split("def probe(", 1)[1].split("\ndef ", 1)[0]
    check("probe reports a parked surface instead of a dead session",
          "parked" in probe_body and "return 3 if parked else 0" in probe_body)


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


def test_merge_queue_keeps_the_backlog() -> None:
    """Adding newly rendered clips must never drop the pending backlog.

    A rebuild enumerates `library/shorts/` and would replace the committed queue,
    silently losing the pending posts. `merge_queue` appends only new
    (platform, video) ids, so the backlog survives and the new karaoke clips join
    the rotation behind it.
    """
    section("merge_queue keeps the backlog (new-format safety)")
    import crosspost
    import tempfile

    real = crosspost.QUEUE
    try:
        with tempfile.TemporaryDirectory() as d:
            crosspost.QUEUE = Path(d) / "q.json"
            existing = [{"id": "tiktok:short-song-x", "platform": "tiktok",
                         "video": "a.mp4", "caption": "old"}]
            crosspost.QUEUE.write_text(json.dumps(existing), encoding="utf-8")
            fresh = existing + [{"id": "tiktok:short-karaoke-x",
                                 "platform": "tiktok",
                                 "video": "b.mp4", "caption": "new"}]
            n = crosspost.merge_queue(fresh)
            check("merge adds only the new item", n == 1, str(n))
            got = json.loads(crosspost.QUEUE.read_text(encoding="utf-8"))
            ids = [it["id"] for it in got]
            check("the old backlog item is still there",
                  "tiktok:short-song-x" in ids)
            check("the new item was appended",
                  ids[-1] == "tiktok:short-karaoke-x")
            check("re-merging the same list adds nothing",
                  crosspost.merge_queue(fresh) == 0)
    finally:
        crosspost.QUEUE = real


def test_state_files_are_addable() -> None:
    """Every durable state file must survive `git add` in a fresh checkout.

    A bare `music938-1/work/` line in .gitignore ignores the whole *directory*,
    and git cannot re-include a file inside an ignored directory — so the `!`
    rules that keep the ledgers tracked were dead. `git add` then exits 1 with
    "The following paths are ignored", which is how the crosspost rail failed to
    record its state after every post (run 42317640960, step 8). Guard both the
    rule and the effect.
    """
    section("durable state files are not gitignored (crosspost commit fix)")
    ignore = (ROOT.parent / ".gitignore").read_text()
    check("no bare directory ignore that swallows the re-includes",
          not any(l.strip() == "music938-1/work/" for l in ignore.splitlines()))

    repo = ROOT.parent
    files = ["music938-1/work/crosspost-state.json",
             "music938-1/work/crosspost-queue.json",
             "music938-1/work/release-state.json",
             "music938-1/work/playlist-state.json"]
    for rel in files:
        try:
            r = subprocess.run(["git", "check-ignore", "-q", "--no-index", rel],
                               cwd=str(repo), capture_output=True)
        except (OSError, FileNotFoundError):
            return  # no git here; the source check above still stands
        check(f"{Path(rel).name} is addable", r.returncode != 0,
              "git check-ignore says it is ignored")


def test_crosspost_blocked_vs_empty() -> None:
    """A dead session with work waiting must fail; an empty queue must not.

    For weeks the crosspost rail ended `success` while posting nothing, because
    both Facebook and TikTok sessions had died and the post step just skipped
    them. That is indistinguishable to K from a healthy no-op run, so the outage
    was silent. The rail now counts the pending posts of a blocked surface and
    fails only when that count is above zero.
    """
    section("crosspost: blocked vs empty (false-green fix)")
    import crosspost

    src = (ROOT / "scripts" / "crosspost.py").read_text()
    check("crosspost exposes --pending-count", '"--pending-count"' in src)
    check("pending-count is handled", "args.pending_count" in src)

    wf = (ROOT.parent / ".github" / "workflows" / "ax-music-crosspost.yml").read_text()
    check("workflow records the blocked surface's pending count",
          "--pending-count" in wf and "blocked-pending" in wf)
    check("workflow fails the run when work is pending", "exit 1" in wf)
    check("failure step is keyed off a pending total", "total" in wf and "-gt 0" in wf)
    # The healthy no-op path must not fail: no blocked file means exit 0.
    check("empty/healthy run exits clean",
          "no blocked surface with pending work" in wf)

    # The ledger must be committed *before* the gate can fail the run. The gate
    # exits 1, and a non-zero exit skips every later step, so a run that posted to
    # TikTok and was then blocked on Facebook lost its TikTok record and reposted
    # it next time. `if: always()` on the commit step plus the gate after it is
    # what keeps the ledger safe.
    commit_at = wf.find("Commit the crosspost state")
    gate_at = wf.find("Fail if a surface was blocked")
    check("the state is committed before the blocked-gate can fail",
          0 < commit_at < gate_at, f"commit@{commit_at} gate@{gate_at}")
    commit_block = wf[commit_at:gate_at]
    check("the commit step runs even when a surface is blocked",
          "if: always()" in commit_block)

    # Behaviour: the count the rail reads is real, and zero once posted.
    q = crosspost.build_queue()
    empty_state = {"posted": {}}
    full_state = {"posted": {it["id"]: {"at": "2026-11-05T00:00:00Z", "url": ""}
                             for it in q}}
    if q:
        check("pending count is positive with an empty state",
              len(crosspost.pending(q, empty_state, "tiktok")) > 0)
        check("pending count is zero once everything is posted",
              len(crosspost.pending(q, full_state, "tiktok")) == 0)


def test_api_posting_route() -> None:
    """The API route that removes K from the loop must be present and inert.

    Advisors (2026-11-07, 6 channels / 4 vendors) ranked the Meta Graph API with
    a System User token the most durable way to post without K, and the TikTok
    Content Posting API second. The code is wired but has no token yet, so the
    invariant that matters is: with no token, nothing changes and nothing breaks.
    """
    section("crosspost: API posting route (K out of the loop)")
    import crosspost

    # The modules exist and are importable from the rail.
    check("fb_graph module is wired into crosspost", crosspost.fb_graph is not None)
    check("tiktok_api module is wired into crosspost", crosspost.tiktok_api is not None)

    ops = ROOT.parent / "ops"
    for f in ("fb_graph.py", "tiktok_api.py", "token_heartbeat.py"):
        check(f"ops/{f} exists", (ops / f).is_file())

    # api_poster follows credential availability: a configured token selects the
    # headless API poster, its absence falls back to the browser. Pinning the
    # decision to `available()` keeps this true whether or not a token exists.
    check("fb poster follows fb_graph.available()",
          (crosspost.api_poster("facebook") is not None) == crosspost.fb_graph.available())
    check("tiktok poster follows tiktok_api.available()",
          (crosspost.api_poster("tiktok") is not None) == crosspost.tiktok_api.available())

    # A Reel is a three-call flow; the finish call must PUBLISH, not just upload.
    fb = (ops / "fb_graph.py").read_text()
    check("fb_graph starts a reel upload", "upload_phase" in fb and '"start"' in fb)
    check("fb_graph publishes (not drafts) the reel", "PUBLISHED" in fb)
    check("fb_graph can refresh a 60-day token", "fb_exchange_token" in fb)

    # TikTok: the honest limit — an unaudited app may only post SELF_ONLY, and the
    # code must refuse to silently replace a public post with a private one.
    tt = (ops / "tiktok_api.py").read_text()
    check("tiktok_api uses the official publish endpoint", "publish/video/init" in tt)
    check("tiktok_api detects the SELF_ONLY (unaudited) cap", "SELF_ONLY" in tt)
    check("tiktok_api refuses a private-only post by default", "allow_private" in tt)

    # The heartbeat must not be able to burn the rotating refresh token in CI.
    hb = (ops / "token_heartbeat.py").read_text()
    check("heartbeat defaults to check-only", 'refresh = "--refresh" in argv' in hb)
    check("heartbeat explains why CI must not refresh",
          "cannot write a new secret" in hb)
    # The agent is the only component that can write the vault, so the one
    # command that renews *and* publishes the rotated token to CI is what keeps
    # the rail alive after the one-time setup. Without it TikTok's rotating
    # refresh token leaves the next CI run holding a spent token.
    check("heartbeat can push the rotated token back to CI",
          "--push-secrets" in hb and "gh-put-secrets.py" in hb)

    # Token rotation burns TikTok's stored refresh token, so it may only happen
    # where the new value can be written back. `_put` returns False with no vault
    # (CI), so every rotation site must be guarded by it.
    check("tiktok rotation is guarded by a vault write",
          tt.count("_put(") >= 3 and "access_token() or refresh()" not in tt)

    # CI has no vault: ax_vault.ensure_anchor() raises SystemExit (a BaseException)
    # when the OpenHands API rejects the runner. The 2026-11-07 heartbeat run died
    # on exactly that — a secret lookup must never kill a GitHub job.
    for name in ("fb_graph.py", "tiktok_api.py"):
        src = (ops / name).read_text()
        check(f"{name} survives a vault SystemExit",
              "except BaseException" in src)

    wf = (ROOT.parent / ".github" / "workflows" / "ax-token-heartbeat.yml").read_text()
    check("a scheduled heartbeat workflow exists", "cron:" in wf)
    check("the heartbeat alerts K only on failure", "if: failure()" in wf)

    # The crosspost workflow must forward the API secrets, or the route is dead.
    cp = (ROOT.parent / ".github" / "workflows" / "ax-music-crosspost.yml").read_text()
    check("crosspost forwards FB_PAGE_TOKEN", "FB_PAGE_TOKEN" in cp)
    check("crosspost forwards the TikTok tokens", "TT_REFRESH_TOKEN" in cp)

    # The admin rail reads the Page's growth numbers; the Graph API must be able
    # to supply them when K's cookie session is dead.
    adm = (ROOT.parent / "aeris938-2" / "scripts" / "admin.py").read_text()
    check("admin has a Graph API snapshot path", "def page_snapshot_via_graph(" in adm)
    check("admin prefers Graph over the browser",
          "graph = page_snapshot_via_graph()" in adm)


def test_crosspost_pace_and_captions() -> None:
    """The two defects found on 2026-11-01 must not come back.

    The first run posted 60 clips in 98 minutes (median gap 26 s) and gave the
    three chorus hooks of one song a byte-identical caption. Both are pinned
    here; the real posting path needs the signed-in desktop, so these are the
    offline halves of the contract.
    """
    section("crosspost cadence + hook captions (2026-11-01 burst)")
    import crosspost
    import release
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
    h1 = next((it for it in q if it["hook"] == 1), None)
    h2 = next((it for it in q if it["hook"] == 2), None)
    # The 2026-11-05 advisor panel (3/3) replaced the "(ท่อน N)" part-number with
    # the series label and a *different answerable prompt* per chorus, so the
    # three files of one song are three distinct posts. Pin that: no part-number
    # reads as "part N of the same clip", and each chorus asks something else.
    # Product cards (hook 0) are captioned by the affiliate module, not here.
    song_items = [it for it in q if it.get("hook", 0) > 0]
    check("hook captions carry no part number",
          all("ท่อน 2" not in it["caption"] and "ท่อน 3" not in it["caption"]
              for it in song_items))
    check("each hook caption carries its own series title",
          all(release.hook_title(it["hook"]) in it["caption"]
              for it in song_items))
    check("hook 1 and hook 2 ask different things",
          h1 is not None and h2 is not None and h1["caption"] != h2["caption"])
    check("hook number is carried on the queue item",
          all("hook" in it for it in q))

    # A karaoke clip of a song used to caption exactly like that song's first-hook
    # Short — same title, tagline and ask — so the pair read as a duplicate post.
    # It is a different offer (sing along, not listen), so it must carry its own
    # series label and ask, and `kind` must be on the item for refresh_captions.
    kara = [it for it in q if it.get("kind") == "karaoke"]
    if kara:
        check("karaoke captions carry the sing-along label",
              all("คาราโอเกะ" in it["caption"] for it in kara))
        check("karaoke caption differs from the song's hook-1 caption",
              all(it["caption"] != crosspost.caption(it["slug"], it["platform"], 1)
                  for it in kara))
    check("kind is carried on the queue item",
          all("kind" in it for it in q))

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

    # Newest post just over an hour old, so the minimum-gap rule passes and the
    # daily cap is what refuses the run.
    burst = {"posted": {f"tiktok:s{i}": {"at": at(3700 + i * 90)} for i in range(60)}}
    ok, why = crosspost.pace_ok(burst, "tiktok", now)
    check("a 60-post burst is held back", not ok, why)
    check("the daily cap is named in the reason", "cap" in why)

    recent = {"posted": {"tiktok:x": {"at": at(300)}}}
    ok, why = crosspost.pace_ok(recent, "tiktok", now)
    check("a post 5 minutes old is inside the minimum gap", not ok, why)

    spaced = {"posted": {"tiktok:x": {"at": at(crosspost.MIN_GAP_SECONDS + 60)}}}
    check("a post past the minimum gap is allowed",
          crosspost.pace_ok(spaced, "tiktok", now)[0])

    check("an empty state is allowed", crosspost.pace_ok({"posted": {}}, "tiktok", now)[0])

    # A link post is the format that reads as an ad, so it is capped at one a
    # day on top of the surface cap: a link already posted today blocks the next
    # one, while a non-link post at the same age is still allowed.
    link_day = {"posted": {"facebook-page:link-x": {"at": at(7200)}}}
    check("a second link post in a day is held back",
          not crosspost.pace_ok(link_day, "facebook", now, kind="link")[0])
    check("a non-link post is not blocked by the link cap",
          crosspost.pace_ok(link_day, "facebook", now, kind="song")[0])

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

    # Facebook carries the extra photo/link formats, so its total ceiling now
    # matches TikTok's; what still differs is the per-format guard: at most one
    # link post a day, which is what keeps the feed from reading as an ad wall.
    check("Facebook allows the full daily cap",
          crosspost.FACEBOOK_DAILY_CAP >= 2)
    check("at most one link post a day",
          crosspost.LINK_DAILY_CAP <= 1)
    two_pages = {"posted": {f"facebook-page:s{i}": {"at": at(3700 + i * 90)}
                            for i in range(crosspost.FACEBOOK_DAILY_CAP)}}
    check("Page posts at the Facebook cap are held back",
          not crosspost.pace_ok(two_pages, "facebook", now)[0])

    # The post URL must come from the platform's own list, never `page.url`.
    # Two routes now build it: the browser path reads it back with
    # `newest_post_url`, and the API path composes it from the returned video id.
    # Pin the behaviour (a real URL on each route), not one literal line.
    src = (ROOT / "scripts" / "crosspost.py").read_text()
    check("a post-list reader exists", "def newest_post_url(" in src)
    check("the browser route reads the URL back from the platform",
          "newest_post_url(pg, it[\"platform\"]" in src)
    check("the API route composes the URL from the returned id",
          "facebook.com/reel/" in src and "/video/" in src)
    check("the ledger stores the resolved URL, not the composer page",
          '"url": real' in src)


def test_api_post_formats() -> None:
    """The Facebook mix (Reel + photo + link) must dispatch by format.

    `ops/fb_graph.py` gained `post_photo` and `post_link` so the Page feed is not
    wall-to-wall Reels. This pins the two facts that make the rail work without a
    network: the format dispatcher routes each kind to the right call and builds a
    URL, and the module actually offers both new entry points with the same
    "None means not configured" contract as `post_reel`.
    """
    section("facebook mix: format dispatch (reel/photo/link)")
    import crosspost
    import fb_graph

    # The module exposes both formats, each returning None (not raising) when
    # there is no token — the same contract the parking logic relies on.
    check("fb_graph offers post_photo", callable(getattr(fb_graph, "post_photo", None)))
    check("fb_graph offers post_link", callable(getattr(fb_graph, "post_link", None)))

    calls = []
    class _FakeGraph:
        PAGE_ID = "1349201551618019"
        def post_photo(self, image, caption, **kw):
            calls.append(("photo", str(image), caption))
            return "1349201551618019_999"
        def post_link(self, message, link, **kw):
            calls.append(("link", link, message))
            return "1349201551618019_888"
    real = crosspost.fb_graph
    try:
        crosspost.fb_graph = _FakeGraph()
        video_api = lambda media, caption: "vid123"  # noqa: E731
        # A photo item: routed to post_photo, URL built from the page id.
        u = crosspost._publish_api("facebook", {"kind": "photo", "caption": "cap"},
                                   Path("/tmp/x.jpg"), video_api)
        check("a photo item calls post_photo", calls[-1][0] == "photo", str(calls[-1]))
        check("a photo URL is a page post permalink",
              u == "https://www.facebook.com/1349201551618019/posts/999", str(u))
        # A link item: routed to post_link, no file involved.
        u = crosspost._publish_api(
            "facebook", {"kind": "link", "caption": "msg", "link": "https://s.shopee.co.th/x"},
            None, video_api)
        check("a link item calls post_link", calls[-1][0] == "link", str(calls[-1]))
        check("a link URL is a page post permalink",
              u == "https://www.facebook.com/1349201551618019/posts/888", str(u))
        # A song Reel still goes through the video api and yields a /reel/ URL.
        u = crosspost._publish_api("facebook", {"kind": "song", "caption": "c"},
                                   Path("/tmp/v.mp4"), video_api)
        check("a song item still posts a Reel",
              u == "https://www.facebook.com/reel/vid123", str(u))
    finally:
        crosspost.fb_graph = real

    # A source guard: the post loop must pick the media field by kind, or a photo
    # post would try to read `it["video"]` and KeyError.
    src = (ROOT / "scripts" / "crosspost.py").read_text()
    check("the loop reads an image for a photo and no file for a link",
          'it["image"] if kind == "photo"' in src and 'if kind == "link":' in src)


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

    # The insights route serves the *acting* account's numbers, so the reader
    # must switch to the Page first. Reading it as the person reported the
    # person's figures and made the Page look dead (0 views) for four days.
    check("the profile dashboard is not the Page identity",
          not social_stats._acting_as_page("สถานะโปรไฟล์\nAeris-Ak Akath\nสลับไปใช้เพจ"))
    check("the switch banner means still the person",
          not social_stats._acting_as_page("AERIS Music\nสลับไปใช้เพจ\nผู้ติดตาม 1 คน"))
    check("the Page dashboard is the Page identity",
          social_stats._acting_as_page("AERIS Music\nแดชบอร์ดครีเอเตอร์\nการวิเคราะห์"))

    # The views dashboard prints the tab labels before the total, so the total
    # must come from the "28 วันที่ผ่านมา" range line, not the first "ยอดดู".
    dash = ("ยอดดูทั้งหมด\nReels\nโพสต์\nสตอรี่\n"
            "28 วันที่ผ่านมา: 9 ต.ค. - 5 พ.ย.\n861\n100%\nยอดดู\n71\n")
    check("the Page views total is read, not the label row",
          social_stats._fb_page_views(dash) == 861)
    check("a dashboard with no range line is UNKNOWN",
          social_stats._fb_page_views("ยอดดู\n0\n") == "UNKNOWN")

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

    # The paid offer (2026-11-07 advisor panel, action #1): before the follower
    # gates there was no way for an interested viewer to pay. It must reach the
    # long-form descriptions and must NOT be pushed into every Short.
    offer = monetize.commission_block()
    check("a paid commission offer is configured", bool(offer.strip()))
    check("the offer names a price", "990" in offer)
    check("the offer gives a way to contact", "facebook.com" in offer)
    import release as _rel
    _, song_desc, _ = _rel.describe("01-khon-di-thi-chak-pai", "song")
    _, short_desc, _ = _rel.describe("01-khon-di-thi-chak-pai", "short")
    check("a song description carries the offer",
          "รับทำเพลงไทยสั่งทำ" in song_desc)
    check("a Short description does not carry the offer",
          "รับทำเพลงไทยสั่งทำ" not in short_desc)
    monetize.CACHE = None

    apply_src = (ROOT / "scripts" / "apply_monetize.py").read_text()
    # The backfill decides long-form from the duration, so the API call must ask
    # for contentDetails or every upload looks like a Short and gets no offer.
    check("the backfill reads the duration to pick long-form",
          "contentDetails" in apply_src and "_is_longform" in apply_src)
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
    #
    # 2026-11-08: the fold test passed but the goal did not move — the only ask
    # above the fold sent the viewer off-platform to the Facebook Page, so the
    # channel never asked for the one action that advances the 1,000-sub gate.
    # The advisors (2/2, duck + pollinations) put the YouTube subscribe first;
    # the Page and the product link follow. Order is the invariant, not one
    # literal position.
    import release
    monetize.CACHE = None
    cta = monetize.cta("youtube")
    check("cta carries the youtube surface link",
          per.get("youtube", "") and per["youtube"] in cta)
    check("cta asks for a follow", "กดติดตาม" in cta)
    page = json.loads((ROOT / "channel" / "monetization.json").read_text(encoding="utf-8")).get("facebook", "")
    channel = json.loads((ROOT / "channel" / "monetization.json").read_text(encoding="utf-8")).get("youtube", "")
    check("cta leads with the YouTube subscribe, not the Page",
          channel and channel in cta and (not page or cta.index(channel) < cta.index(page)),
          "subscribe must come first")
    check("cta keeps the Page after the subscribe",
          page and page in cta)
    _t, desc, _tg = release.describe("01-khon-di-thi-chak-pai", "song", "")
    check("the subscribe ask survives the description fold (within the first 200 chars)",
          channel and channel in desc and desc.index(channel) < 200,
          f"subscribe at {desc.index(channel)}" if channel in desc else "no channel link")
    check("the Page link follows the subscribe",
          page and page in desc and (not channel or desc.index(page) > desc.index(channel)))
    # The product link is no longer the lead CTA, but it must still sit high in
    # the description — before the hashtag block — not buried under the socials
    # footer as it was before 2026-11-03.
    check("the product link still sits above the hashtags",
          per.get("youtube", "") in desc and desc.index(per["youtube"]) < desc.index("#AERISMusic"),
          f"product at {desc.index(per['youtube'])}")
    mint_src = (ROOT.parent / "ops" / "shopee_mint.py").read_text()
    check("mint tool exists for re-pointing the links",
          "custom_link" in mint_src)

    # The 20 videos already live carry the old homepage link at the bottom.
    # `refresh_description` must re-point it, drop the old channel-only CTA and
    # lift the new CTA above the fold, and be idempotent.
    old = ("🎵 เพลงเก่า\n\nเพลงผ่อนคลาย\n\n"
           "🎧 ฟังเพลิน ๆ แล้วกดติดตามช่องนะครับ · ของน่าซื้อ 👉 https://s.shopee.co.th/8pn3G4alfI\n\n"
           "🛒 สนับสนุนช่องผ่าน Shopee:\nhttps://s.shopee.co.th/OLDHOME")
    fixed = monetize.refresh_description(old, "youtube")
    check("refresh re-points the old homepage link",
          "OLDHOME" not in fixed and per["youtube"] in fixed)
    check("refresh drops the old channel-only CTA",
          "กดติดตามช่องนะครับ" not in fixed)
    check("refresh lifts the cta above the fold",
          fixed.index(channel) < 160, f"{fixed.index(channel)}")
    check("refresh keeps the subscribe ahead of the Page",
          fixed.index(channel) < fixed.index(page),
          f"sub {fixed.index(channel)} page {fixed.index(page)}")
    check("refresh is idempotent",
          monetize.refresh_description(fixed, "youtube") == fixed)

    # A video live between 2026-11-05 and 2026-11-08 carries the Page-first
    # block, not the old channel-only line. `refresh_description` must replace it
    # with the subscribe-first block, exactly once, and stay idempotent — the
    # Page and product lines are adjacent in the new block too, so an unguarded
    # second pass would strip them and duplicate the subscribe ask.
    pagefirst = (f"🎵 เพลงเก่า\n\nเพลงผ่อนคลาย\n\n"
                 f"❤️ กดติดตามเพจ Facebook 👉 {page}\n"
                 f"🛒 ของน่าซื้อ 👉 {per['youtube']}\n\n"
                 f"#AERISMusic #Shorts")
    migrated = monetize.refresh_description(pagefirst, "youtube")
    check("refresh adds the subscribe to a Page-first description",
          channel in migrated)
    check("refresh puts the subscribe ahead of the Page",
          migrated.index(channel) < migrated.index(page))
    check("refresh does not duplicate the subscribe ask",
          migrated.count("กดติดตามช่อง") == 1, f"{migrated.count('กดติดตามช่อง')}")
    check("refresh does not duplicate the Page ask",
          migrated.count("กดติดตามเพจ") == 1, f"{migrated.count('กดติดตามเพจ')}")
    check("refresh of a Page-first description is idempotent",
          monetize.refresh_description(migrated, "youtube") == migrated)
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
    check("no retired Short is a target", not ({v for v, _, _ in targets} & retired))
    check("a song target links to its youtu.be song",
          all("youtu.be/" in t for _, t, m in targets if m == sw._PIN_MARKERS["song"]))
    # The product clip's description link may not be tappable, so its pin is the
    # click path and must carry the tracked Shopee link plus the disclosure.
    aff_state = {"released": [
        {"slug": "hp-budget-01", "kind": "affiliate", "video_id": "AFF0000001"}]}
    aff = [(v, t, m) for v, t, m in sw.short_pin_targets(aff_state)
           if m == sw._PIN_MARKERS["affiliate"]]
    check("a product Short is a pin target too", bool(aff))
    check("the product pin carries the affiliate link",
          all("s.shopee.co.th" in t for _, t, _ in aff))
    check("the product pin discloses the affiliate link",
          all("ลิงก์พันธมิตร" in t for _, t, _ in aff))
    check("a retired product Short is not pinned",
          sw.short_pin_targets({"released": [
              {"slug": "hp-budget-01", "kind": "affiliate", "video_id": "AFF0000001",
               "retired_at": "2026-11-05T00:00:00+00:00"}]}) == [])


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
    # The channel avatar has no API, so the Studio UI is the only route; the
    # script must (a) drive it and (b) click the final Publish, or the upload
    # looks done and never lands.
    check("has a YouTube avatar path", "def youtube(" in src)
    check("youtube path publishes the staged branding change",
          "เผยแพร่" in src and "publish" in src)
    check("youtube path is wired into main", '"youtube"' in src)
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
    # A bio is where a view can still become a click after the caption scrolls
    # away, so each surface's bio must carry *that surface's* affiliate link and
    # the disclosure. The first affiliate Reels went out with no link in the bio.
    cfg = json.loads((ROOT / "channel" / "monetization.json").read_text(encoding="utf-8"))
    check("TikTok bio carries its own affiliate link",
          cfg["shopee_links"]["tiktok"] in profile_setup.TIKTOK_BIO)
    check("Facebook bio carries its own affiliate link",
          cfg["shopee_links"]["facebook"] in profile_setup.FACEBOOK_BIO)
    for name, bio in (("TikTok", profile_setup.TIKTOK_BIO),
                      ("Facebook", profile_setup.FACEBOOK_BIO)):
        check(f"{name} bio discloses the affiliate link", "ลิงก์พันธมิตร" in bio)
    # The bio must answer "what do I get if I follow?" (the four-advisor panel's
    # #1 fix) and the pinned welcome post must carry the same follow ask.
    check("Facebook bio leads with the benefit, not the brand",
          profile_setup.FACEBOOK_BIO.splitlines()[0].startswith("🎵"))
    check("Facebook bio asks for the follow",
          "กดติดตาม" in profile_setup.FACEBOOK_BIO)
    check("welcome post names the four content types",
          all(k in profile_setup.WELCOME_POST for k in ("เพลงเศร้า", "เพื่อชีวิต", "ลูกทุ่ง", "คาราโอเกะ")))
    check("welcome post asks for the follow", "กดติดตามเพจ" in profile_setup.WELCOME_POST)
    # The Page composer drops execCommand input (1 char lands); only the CDP
    # Input.insertText works, so the welcome path must use it.
    psrc = (ROOT / "scripts" / "profile_setup.py").read_text()
    check("welcome post types via CDP insertText", "Input.insertText" in psrc)
    check("welcome path is idempotent (detects an existing pin)", "เลิกปักหมุด" in psrc)
    # The channel description is a discovery surface; its Facebook line must be a
    # real Page link, and a copy change must not drag the banner along with it.
    brand_src = (ROOT / "scripts" / "apply_brand.py").read_text()
    check("channel description can change without re-uploading the banner",
          "--description-only" in brand_src)


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
        # The restore used to be gated on OPENHANDS_API_KEY, which is not part of
        # the vault's auth path, so a normal pod skipped the restore and K signed
        # in again for nothing. The gate must not come back.
        check("restores the saved login without an API-key gate",
              "def restore_login" in src
              and 'environ.get("OPENHANDS_API_KEY")' not in src)
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
    # Each button must carry K's own experience of what the sign-in takes, or the
    # page sends them into a slide puzzle they did not expect.
    hints = {k: v[2] for k, v in phone_login.SURFACES.items()}
    check("Shopee warns about the slide puzzle", "สไลด์" in hints["shopee"])
    # Facebook is now a one-time token job, not a recurring sign-in. The account
    # has no Business Portfolio and is not a developer, so the button starts at
    # the developer registration (the first of two gates) and the hint names the
    # whole path, ending in a never-expiring token.
    check("Facebook starts at developer registration",
          "developers.facebook.com" in phone_login.SURFACES["facebook"][1])
    check("Facebook hint describes the one-time token path",
          "System User" in hints["facebook"] and "Never" in hints["facebook"])
    check("the easy surfaces say so", "กดปุ๊บ" in hints["flow"])
    # The pack uses two Google accounts (music/Drive = aerismusic8, Shopee =
    # kongkeat.p3), so the page must let K pick one without the agent ever typing
    # a password: the switch button only opens Google's own account chooser.
    check("offers an account switch", "switch" in phone_login.SURFACES)
    check("switch opens Google's own chooser, no password",
          "AccountChooser" in phone_login.SURFACES["switch"][1])
    check("names the music account on Drive",
          phone_login.SURFACES["drive"][3] == "aerismusic8@gmail.com")
    check("names the Shopee account",
          phone_login.SURFACES["shopee"][3] == "kongkeat.p3@gmail.com")
    # Tapping a surface must reuse the open tab (as the bookmark bar does), not
    # stack a duplicate — otherwise a signed-in surface reloads and loses nothing
    # but the operator gets a pile of tabs.
    check("reuses the open tab", "/json/activate/" in src)
    check("opens the surface in the desktop over CDP", "/json/new?" in src)
    check("hands the phone to noVNC after a tap", "novnc_url()" in src)
    check("asks for remote resize", "resize=remote" in src)
    # K's standing instruction (2026-11-07): the Facebook password is the same as
    # the mail password and is typed ONCE. The page may collect it, but only into
    # the durable vault (never the repo), and the agent still never reads it out.
    check("collects the password once into the vault", 'action="/fb-pass"' in src
          and "_vault_kv" in src and "ax_vault" in src)
    check("the password only reaches the vault, never a file",
          "kv_put" in src and "open(" not in src.split("def _vault_kv")[1].split("def ")[0])
    check("can retype the vaulted password", "/fb-type" in src
          and "type_password_into_dialog" in src)
    check("does not print the vaulted password", "print(pw" not in src
          and "print(password" not in src)
    # The one-time Facebook token: K pastes it once, the page verifies it against
    # the real Page and writes the Actions secret itself. This is the whole point
    # — K does one action and is never asked again.
    check("has a Facebook token form", 'action="/fb-token"' in src)
    check("verifies the token before storing it", "_verify_token" in src
          and "graph.facebook.com" in src)
    check("writes the Actions secret itself", "_set_actions_secret" in src
          and "gh" in src and "secret" in src)
    check("stores the secret the rail reads", 'FB_PAGE_TOKEN' in src)
    # The no-copy path: the agent reads the token off the desktop screen so K does
    # not have to copy a long string out of noVNC into a phone form.
    check("can grab the token off the desktop", "/fb-grab" in src
          and "grab_fb_token" in src and "connect_over_cdp" in src)


def test_heartbeat_repair_signal() -> None:
    """The board must notice a release that went up without its art.

    A spent quota makes `videos.insert` succeed (its own 100/day bucket) while
    `thumbnails.set` and `playlistItems.insert` return 403, so the run is green
    and the defect is invisible. The heartbeat has to read the ledger flags, not
    the run history, and an unreadable ledger must not page the phone.
    """
    section("heartbeat (a green run can still hide a defect)")
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import base64
    import heartbeat  # noqa: E402

    rows = {"released": [
        {"slug": "a", "thumb_ok": False},
        {"slug": "b", "playlist_ok": False},
        {"slug": "c", "thumb_ok": True, "playlist_ok": True},
        {"slug": "d"},
    ]}
    body = base64.b64encode(json.dumps(rows).encode()).decode()
    heartbeat._get = lambda url: {"content": body}
    check("counts a false thumbnail and a false playlist",
          heartbeat._pending_repairs() == 2)

    def boom(url):
        raise RuntimeError("offline")

    heartbeat._get = boom
    check("an unreadable ledger is zero, not an alert", heartbeat._pending_repairs() == 0)

    src = (ROOT.parent / "ops/heartbeat.py").read_text()
    check("the board reports the pending count",
          "waiting on a thumbnail/playlist repair" in src)


def test_brand_identity() -> None:
    """The channel identity must obey the two rules the advisors set.

    The 2026-11-07 consult (4 channels / 2 vendors) said to keep the indigo
    A-wave mark but warm it, to keep headphones a prop and not the icon, and to
    put only the mark, the wordmark and one Thai tagline inside the banner's
    guaranteed-visible strip. Those are geometry facts, so they are testable:
    if the mark drifts out of the strip, or a headphone is drawn into the
    avatar, this fails instead of shipping.
    """
    section("brand identity (safe strip + warm evolution)")
    import brand_pro as bp
    from PIL import Image

    check("indigo field kept from v2", bp.INK == (32, 42, 70))
    src = (ROOT / "scripts" / "brand_pro.py").read_text()
    # The avatar call is the one that must be bold; a thin stroke vanishes at 88px.
    check("avatar draws the mark bolder than the banner",
          "color=CREAM, width_frac=0.075" in src)
    check("the avatar has no headphone", "_headphone" not in src.split("def make_avatar")[1]
          .split("def make_youtube_banner")[0])

    x0, y0, x1, y1 = bp.SAFE_STRIP
    check("safe strip is the 1546x423 YouTube area",
          (x1 - x0, y1 - y0) == (1546, 423), f"{(x1 - x0, y1 - y0)}")
    check("safe strip is centred", abs((x0 + x1) / 2 - 1280) <= 1
          and abs((y0 + y1) / 2 - 720) <= 1)

    banner = ROOT / "channel" / "banner-pro-2560x1440.png"
    avatar = ROOT / "channel" / "avatar-pro-800x800.png"
    if not banner.exists() or not avatar.exists():
        skip("brand assets not rendered yet")
        return
    b = np.asarray(Image.open(banner).convert("RGB")).astype(int)
    check("banner is 2560x1440", b.shape[:2] == (1440, 2560))
    # Bright = text. The corners may glow (the morning window) but no glyph may
    # sit there, so only near-white counts as a violation outside the strip.
    def white(a):
        return int((a.min(axis=2) > 210).sum())
    outside = (white(b[:y0]), white(b[y1:]), white(b[y0:y1, :x0]), white(b[y0:y1, x1:]))
    check("no wordmark outside the safe strip", sum(outside) == 0, str(outside))
    check("the strip carries the wordmark", white(b[y0:y1, x0:x1]) > 20000)

    a = Image.open(avatar).convert("RGB")
    check("avatar is square 800", a.size == (800, 800))
    small = np.asarray(a.convert("L").resize((88, 88))).astype(float)
    contrast = np.percentile(small, 95) - np.percentile(small, 5)
    check("the mark still reads at 88px", contrast >= 100, f"contrast {contrast:.0f}")

    # The banner writer is a full-replace PUT, so it must read the current
    # brandingSettings first and refuse to write one with no description.
    art = (ROOT.parent / "ops" / "apply_channel_art.py").read_text()
    check("banner writer reads settings before it writes",
          'api_get("channels"' in art and 'part="brandingSettings"' in art)
    check("banner writer refuses a stripped PUT", "no description" in art)


def test_produce_loop() -> None:
    """The production loop must be able to run with no login and no quota.

    K: "งานเพลงต้องสร้างต่อเนื่องไว้เป็นวัตถุดิบให้ ai เอาไปสร้างคลิปด้วยแล้วล่ะ".
    The thing that stops a song from being made is a login, so the loop must
    have a keyless lane that never blocks (Duck.ai lyric -> ffmpeg master -> PIL
    cover) and treat a Flow Music render as a bonus, not a requirement. This pins
    that shape plus the two ways it could silently do the wrong thing: produce an
    identical song every run, or file a vocal render as an instrumental.
    """
    section("produce loop (continuous, keyless)")
    src = (ROOT / "scripts" / "produce_loop.py").read_text()
    check("drafts the lyric on a keyless channel",
          '"duck"' in src and '"pollinations"' in src and "for drafter in" in src)
    check("a browser-less channel is available (CI has no desktop)",
          "_drive_pollinations" in (ROOT / "scripts" / "ai_lyrics.py").read_text())
    check("makes the master offline before trying Flow",
          src.index("--offline") < src.index('"--force"]'))
    check("a Flow render is opt-in, not required", "--flow" in src)
    check("writes the lyric before spending any render", "render_file" in src)
    check("refreshes the share pack for other AIs", "make_share_pack.py" in src)
    check("needs no credential to run", "get_secret" not in src and "secrets." not in src)

    sys.path.insert(0, str(ROOT / "scripts"))
    import produce_loop as pl  # noqa: E402

    # A theme pool, not one hard-coded song: a loop that always makes the same
    # song is a loop that produces nothing new.
    check("has a theme pool", len(pl.THEMES) >= 8)
    check("the pool spans several moods",
          len({t[3] for t in pl.THEMES}) >= 4)
    # Every theme must name a genre the plan knows, or the style prompt is blank.
    known = {g["id"] for g in pl.G.genres()}
    check("every theme names a planned genre",
          all(t[0] in known for t in pl.THEMES))
    # Rotation: a used title must not be picked again.
    first = pl.pick_theme(set())
    second = pl.pick_theme({first[2]})
    check("the picker skips a title already used", first[2] != second[2])
    # The pool is themes x variants; it must exhaust (not repeat) only once every
    # combination is used, so the loop can run for weeks without a duplicate.
    all_titles = {f"{t[2]}{s}" for t in pl.THEMES for s, _ in pl.VARIANTS}
    check("the picker exhausts rather than repeats",
          pl.pick_theme(all_titles) is None)
    check("the pool is deeper than the theme count",
          len(all_titles) > len(pl.THEMES))
    # Slugs must be filename-safe and stable (a save/playlist keys off them).
    s1, s2 = pl._slugify("ไฟนีออนกับใจที่ล้า"), pl._slugify("ไฟนีออนกับใจที่ล้า")
    check("a Thai title yields a stable slug", s1 == s2 and s1.isascii())
    check("the slug has no path characters", "/" not in s1 and " " not in s1)


def test_share_pack() -> None:
    """The pack must let another AI pick a track, so it must carry the *why*.

    K asked to share the songs so another AI can use them as a soundtrack. A
    folder of .mp3 tells an agent nothing — it cannot tell a 52 BPM funeral
    ballad from an 84 BPM battle theme, so it picks at random and the cut feels
    wrong. This pins the fields that make the choice possible (mood + bpm), that
    every song on disk is in the catalog, that each carries an instrumental path,
    and that the license is stated in the pack itself rather than assumed.
    """
    section("share pack (music another AI can use)")
    src = (ROOT / "scripts" / "make_share_pack.py").read_text()
    check("the pack is keyed by mood and tempo", '"mood"' in src and "tempo_bpm" in src)
    check("Thai search words are included", "mood_th" in src)
    check("the pack states its license", "CC0" in src)
    check("the pack ships a prompt for another AI", "PROMPT-TH.md" in src)
    check("instrumental beds are offered", "beds" in src)

    # The catalog must be buildable from the library without network or login.
    sys.path.insert(0, str(ROOT / "scripts"))
    import make_share_pack as msp  # noqa: E402

    rows = msp.catalogue()
    disk = sorted(p.name for p in (ROOT / "library" / "songs").glob("song-*.mp3"))
    check("every song on disk is in the catalog", len(rows) == len(disk))
    check("every entry carries a mood", all(r["mood"] for r in rows))
    check("every entry has a duration", all(r["duration_seconds"] for r in rows))
    check("every entry points at an instrumental path",
          all(r["instrumental"].startswith("music/karaoke-") for r in rows))
    check("the karaoke files actually exist for most songs",
          sum(1 for r in rows if r["has_instrumental"]) >= len(rows) - 2)
    # A "song" that is really the ffmpeg bed must say so: K was served a bed as a
    # song and only found out by listening (2026-11-07). Every row carries a
    # provenance label, and it is derived from the audio, not from a file's name.
    check("every entry states whether it is a real song or a bed",
          all(r.get("audio") in ("flow", "synth-bed", "unknown") for r in rows))
    check("every entry states whether it has vocals",
          all("has_vocals" in r for r in rows))
    check("provenance comes from the audio, not a filename",
          "mono_duplicated" in src or "provenance" in src)
    # A soundtrack picker needs a fast/slow spread, not 22 identical tempos.
    tempos = {r["tempo_bpm"] for r in rows if r["tempo_bpm"]}
    check("the catalog spans more than one tempo", len(tempos) >= 3)
    check("the catalog spans more than one mood",
          len({r["mood"] for r in rows}) >= 3)
    # No secrets, no K: this is what makes it shareable.
    blob = src.lower()
    # The release listing may use a token, but it must be *optional*: a run with
    # no credential must still build the pack from the disk.
    check("the release listing is optional, not required",
          'AX_GH_TOKEN", ""' in src and "get_secret" not in blob)
    check("the audio is gitignored (only the small files commit)",
          "share/aeris-music/music/" in (ROOT.parent / ".gitignore").read_text())


def test_k_free_status() -> None:
    """The K-free audit must be honest, and must not need a live secret.

    K asked to cut K out 100%. The truthful answer (consult 2026-11-07, both
    vendors) is that every platform requires the owner to authorize *once*; what
    can be driven to zero is the *recurring* need. So the audit reports three
    things per rail — k_free, needs K once, needs K repeatedly — and the invariant
    that matters is `needs_k == 0`. This pins the rules that make it trustworthy:
    a browser fallback is not a K-dependency while its api primary is present, a
    keyless rail is K-free with no secrets, and with no tokens the fallbacks do
    become recurring. The secret lookup is stubbed so the suite never touches a
    live token.
    """
    section("k-free status (is K still in the loop?)")
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import k_free_status as kfs  # noqa: E402

    real = kfs.get_secret
    try:
        # Every credential present: the api primaries are K-free, so the browser
        # fallbacks are covered and nothing needs K again.
        kfs.get_secret = lambda name: "x"
        rep = kfs.audit()
        by = {(r["surface"], r["rail"]): r for r in rep["rails"]}
        check("an api rail with its token is K-free",
              by[("facebook", "Page Reels")]["k_free"])
        check("a covered browser fallback is not recurring",
              by[("tiktok", "Short posting (fallback)")]["covered"]
              and not by[("tiktok", "Short posting (fallback)")]["needs_k"])
        check("the Flow render is covered by the keyless synth bed",
              by[("music", "song beds (Flow render)")]["covered"])
        check("the avatar is a one-time K action, not recurring",
              by[("youtube", "channel avatar")]["one_time"]
              and not by[("youtube", "channel avatar")]["needs_k"])
        check("with tokens present, nothing needs K again", rep["needs_k"] == 0)
        check("k_free_all means no recurring need", rep["k_free_all"] is True)
        check("with every token present, only the avatar is a one-time action",
              rep["needs_k_once"] == 1)

        # Nothing present: no *api* rail can claim K-free, but a keyless rail has
        # no credential to lose, so it stays K-free. With no tokens the browser
        # fallbacks have no primary, so K is pulled back in — the honest failure.
        kfs.get_secret = lambda name: ""
        rep0 = kfs.audit()
        by0 = {(r["surface"], r["rail"]): r for r in rep0["rails"]}
        check("with no secrets, no api rail is K-free",
              not any(r["k_free"] for r in rep0["rails"] if r["auth"] == "api"))
        check("a keyless rail is K-free with no secrets at all",
              by0[("lyrics", "Thai lyrics")]["k_free"]
              and by0[("music", "song beds (offline)")]["k_free"])
        check("with no tokens, an unprovisioned api rail is a one-time need",
              by0[("facebook", "Page Reels")]["one_time"])
        check("with no tokens, every api/oneshot rail is a one-time need",
              rep0["needs_k_once"] == 6)
        # Facebook has no browser fallback any more: it parks instead of opening a
        # browser, so a missing token is a one-time setup, never a recurring need.
        # TikTok still has its browser fallback (its API needs an app audit first),
        # so with no tokens that one is the only recurring K-dependency.
        check("a parked API-only surface is never recurring",
              not by0[("facebook", "Page Reels")]["needs_k"])
        check("with no tokens, only the tiktok fallback is recurring",
              rep0["needs_k"] == 1 and rep0["k_free_all"] is False)
        check("facebook is reported as a one-time setup, not a blocker",
              ("facebook", "Page Reels") not in
              {(b["surface"], b["rail"]) for b in rep0["blocked"]})
    finally:
        kfs.get_secret = real


def test_vault_key_fallback() -> None:
    """ax_vault must resolve the API key through ax_secrets, not only os.environ.

    The sandbox injects a secret into the environment only when the command text
    names the key, so a fresh session that never types OPENHANDS_API_KEY gets a
    401 that reads as "the vault is gone". The fallback is what stops that.
    """
    section("vault key resolution")
    src = (ROOT.parent / "ops" / "ax_vault.py").read_text()
    check("ax_vault falls back to ax_secrets for the key",
          "from ax_secrets import get_secret" in src and "_get_secret(\"OPENHANDS_API_KEY\")" in src)


def test_keyless_lyric_drafter() -> None:
    """The lyric rail must not depend on K's Google session.

    The drafting step used to need the signed-in ChatGPT/Gemini web app, so a
    signed-out desktop meant no new song at all — a K-dependency in the content
    engine itself. Duck.ai needs no login and no key, so it is now the drafter,
    with the lint as the quality gate. Two things make that safe and are pinned
    here: Duck.ai's "Nth opinion" chrome must be stripped or the last lyric line
    fails the Latin-text lint, and both drafters must share the same prompt/parse
    /lint path so a weaker channel costs a retry rather than a bad render.
    """
    section("keyless lyric drafter (no Google session needed)")
    sys.path.insert(0, str(ROOT / "scripts"))
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import ai_lyrics as A  # noqa: E402

    check("duck is a registered drafter", "duck" in A.DRAFTERS)
    check("chatgpt stays as the fallback drafter", "chatgpt" in A.DRAFTERS)
    # The chrome is stripped where every answer is read, not just for lyrics.
    check("duck_ask strips the 'Nth opinion' marker",
          "opinion" in (ROOT.parent / "ops" / "duck_ask.py").read_text()
          and re.search(r"st\|nd\|rd\|th", (ROOT.parent / "ops" / "duck_ask.py").read_text())
          is not None)
    # A draft carrying the marker fails the lint — which is why the strip matters.
    bad = [("chorus", ["คิดถึงบ้านยามฝนตกทุกครา", "2nd opinion"])]
    check("the marker would fail the lint",
          any("Latin" in p for p in A.lint_sections(bad)))
    forge = (ROOT / "scripts" / "forge_song.py").read_text()
    check("the forge tries the keyless drafter first",
          forge.index('for drafter in ("duck", "chatgpt")') > 0)

    # The song master itself must not depend on Flow Music's login either.
    flow = (ROOT / "scripts" / "flow_song.py").read_text()
    check("flow_song has a keyless offline master path",
          "--offline" in flow and "def _offline_bed" in flow)
    check("the offline path uses the offline synth, not Flow",
          "make_music" in flow and 'status": "OFFLINE_BED' in flow)
    check("the offline path reads the lyric header",
          'parse_lyric(lyric)["meta"]' in flow)
    # A normal run must never silently downgrade a Flow render to a synth bed.
    check("the offline master is opt-in, not automatic",
          "if args.offline" in flow and "except B.LoginRequired" in flow)


def test_consult_gate() -> None:
    """K's standing rule: consult the advisors BEFORE acting.

    A written rule gets skipped under time pressure, so the rule is also a gate:
    `require()` raises unless a recent, actually-answered consultation for the
    same brief is on disk. This test pins the gate's behaviour, not just its
    existence.
    """
    section("consult-before-acting gate")
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import consult  # noqa: E402
    import tempfile

    src = (ROOT.parent / "ops" / "consult.py").read_text()
    check("chatgpt/gemini/duck stay available via --only",
          all(v in consult.VENDORS for v in ("chatgpt", "gemini", "duck")))
    # K cut the slow advisors (2026-11-07): the default panel is the keyless
    # channels only. The web apps stay reachable but are out of the default,
    # because they need the Google session and mostly added latency.
    check("the default panel is small (K: cut the slow ones)",
          len(consult.PANEL) <= 3, f"{len(consult.PANEL)}")
    check("every default channel is keyless (no login, no API key)",
          set(consult.PANEL) == {"duck", "pollinations"})
    check("the default panel names two distinct vendors",
          len({consult.family(c) for c in consult.PANEL}) >= 2)
    # A keyless HTTP channel keeps the panel at quorum on the days the browser
    # channels die together (Gemini signs out, ChatGPT free throttles, a Duck tab
    # wedges), so it is a first-class vendor, not a fallback script.
    check("a keyless HTTP channel is in the panel", "pollinations" in consult.VENDORS)
    check("that channel is a distinct vendor family",
          consult.family("pollinations") == "pollinations")
    # The quorum counts *vendors*, not channels: several Duck.ai models are one
    # page, so counting channels let one page pass for a panel (the 2026-11-06 FB
    # brief "10/10 agreed" while 8 were the same page).
    check("duck channels collapse to one vendor",
          consult.family("duck-luna") == consult.family("duck-oss") == "duck")
    check("chatgpt and gemini are their own vendors",
          consult.family("chatgpt") == "chatgpt"
          and consult.family("gemini") == "gemini")
    check("the floor is measured in families", consult.MIN_FAMILIES >= 2,
          f"{consult.MIN_FAMILIES}")
    check("the floor matches the two-channel default",
          consult.MIN_ADVISORS == len(consult.PANEL),
          f"{consult.MIN_ADVISORS} vs {len(consult.PANEL)}")
    check("duck needs no login", "duck" in consult.VENDORS)
    check("records the problem and answers", "consult-log.jsonl" in src)
    check("records what was applied, not just what was asked",
          "applied" in src and "def note_applied" in src)
    check("retries a failed channel", "retries" in src)

    with tempfile.TemporaryDirectory() as tmp:
        consult.LOG = Path(tmp) / "consult-log.jsonl"
        brief = "how do we get the first Shopee order"
        # Nothing recorded yet -> the gate must refuse.
        try:
            consult.require(brief)
            check("gate refuses an unconsulted brief", False)
        except consult.NotConsulted:
            check("gate refuses an unconsulted brief", True)
        check("gate reports not consulted", consult.consulted(brief) is None)

        # A consultation where nobody answered is not a consultation.
        consult.record(brief, {"chatgpt": {"ok": False, "error": "timeout"}})
        check("an unanswered consultation does not satisfy the gate",
              consult.consulted(brief) is None)

        # One family under three names is still one opinion — the exact shape the
        # old channel count passed.
        consult.record(brief, {"duck": {"ok": True, "answer": "a"},
                               "duck-claude": {"ok": True, "answer": "b"},
                               "duck-oss": {"ok": True, "answer": "c"}})
        check("one vendor echoing itself is not a quorum",
              consult.consulted(brief) is None)

        # A single channel is not a panel either.
        consult.record(brief, {"chatgpt": {"ok": True, "answer": "x"}})
        check("one answer does not satisfy the gate",
              consult.consulted(brief) is None)

        # Two vendors across three channels satisfies it.
        consult.record(brief, {"chatgpt": {"ok": True, "answer": "x"},
                               "duck": {"ok": True, "answer": "y"},
                               "duck-oss": {"ok": True, "answer": "z"}})
        row = consult.require(brief)
        check("gate passes after a real quorum (2 vendors / 3 channels)",
              row is not None)
        check("the quorum reason names the vendors",
              "chatgpt" in consult.quorum(row["answers"])[1]
              and "duck" in consult.quorum(row["answers"])[1])
        check("the digest is stable across whitespace",
              consult.digest(brief) == consult.digest("  " + brief + "  "))
        check("a different brief is a different gate",
              consult.consulted("some other brief") is None)
        # Staleness: an old consultation must not authorise today's action.
        check("gate rejects a stale consultation",
              consult.consulted(brief, max_age_hours=-1) is None)

        # "Which advice did we use" must be answerable after the fact.
        n = consult.note_applied(brief, ["raise FACEBOOK_DAILY_CAP to 2",
                                         "read each Reel's insights"])
        check("note_applied records on the matching row", n >= 1)
        got = [r for r in consult.consulted(brief, max_age_hours=48)["applied"]]
        check("the applied list is stored", len(got) == 2)


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
    # The K-free audit is reported but must never be an alert: the avatar and the
    # song beds have no API, so "not all K-free" is the steady state and alerting
    # on it every hour would train K to ignore the watchdog.
    check("reports the k-free audit", "k_free_status" in src)
    check("the k-free audit is not an alert", "problems.append" not in src.split("k_free_status")[1].split("now = datetime")[0])


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

    # The identity probe must not be fooled by the personal profile's own
    # "จัดการเพจ" rail entry, and must reject the switch banner. It needs the
    # Page-only edit anchor, which the personal shell never shows.
    check("acting-as-Page rejects the personal shell that lists จัดการเพจ",
          not outreach._acting_as_page(
              _FakePage("จัดการเพจ AERIS Music Aeris-Ak Akath ผู้ติดตาม 0 คน")))
    check("acting-as-Page rejects the switch-to-Page banner",
          not outreach._acting_as_page(
              _FakePage("สลับไปใช้เพจ AERIS Music เพื่อดำเนินการเพิ่มเติม แก้ไขรูปภาพหน้าปก")))
    check("acting-as-Page is true only on the Page shell",
          outreach._acting_as_page(_FakePage("จัดการเพจ AERIS Music แก้ไขรูปภาพหน้าปก")))


def test_promo_site_converts_to_the_page() -> None:
    """The landing page's job is to turn a visitor into a Page follower.

    It used to be a YouTube hub: the only social link in the footer was YouTube,
    so the one page we control end to end sent nobody to the Page (verified live
    2026-11-06 — the deployed HTML had zero facebook.com links). A four-advisor
    panel ranked this the #3 fix, after the Page profile and a pinned post, but it
    is the part AR owns outright, so it is pinned here.
    """
    section("promo site converts to the Page")
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import ar_promo_site as P  # noqa: E402

    html = P.render([{"id": "abc123", "title": "เพลงทดสอบ"}],
                    "https://www.youtube.com/@aerismusicth")
    check("links to the Facebook Page", "facebook.com/profile.php?id=" in html)
    check("has more than one follow link", html.count("facebook.com/profile.php?id=") >= 2)
    check("the follow button names the Page",
          "ติดตาม AERIS Music บน Facebook" in html)
    check("links TikTok too", "tiktok.com/@aeris.music4" in html)
    check("keeps the YouTube subscribe link", "sub_confirmation=1" in html)
    check("the first button is the Page, not YouTube",
          html.index("facebook.com/profile.php?id=") < html.index("sub_confirmation=1"))
    check("says what a follower gets", "คาราโอเกะ" in html)
    # Search-first (2026-11-09): the page carries a buying-guide section whose
    # headings/FAQ answer the real Thai queries, each linking the affiliate URL.
    # Social reach is tiny; a search-indexable page needs no audience, so this is
    # where the affiliate funnel can actually get found. A page that lost the
    # section or the links would silently stop being a revenue surface.
    for g in P.GUIDES:
        check(f'guide covers "{g["q"]}"', g["q"] in html)
    check("guides link the affiliate URL", P.SHOPEE_URL in html)
    check("the affiliate link is nofollow+sponsored",
          'rel="nofollow sponsored noopener"' in html)
    check("FAQ structured data is present",
          '"@type": "FAQPage"' in html or '"@type":"FAQPage"' in html)


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
    test_follow_end_card()
    test_ambient_loop()
    test_soundfont_renderer()
    test_refresh_sleep_video()
    test_provenance()
    test_genres()
    test_arrangement_no_repeat()
    test_song_analysis()
    test_thumb_contrast()
    test_ai_covers()
    test_thumbnail_repair()
    test_titles()
    test_compilation()
    test_compilation_cta_repair()
    test_themed_compilations()
    test_song_title_search_intent()
    test_competitor_scanner_parsers()
    test_flow_extend_kinds()
    test_market_report()
    test_market_plugin_wiring()
    test_market_root_resolution()
    test_automation_secret_fallback()
    test_karaoke_loudness_contract()
    test_crosspost_engine()
    test_browser_ci_storage_state()
    test_crosspost_uses_committed_queue()
    test_merge_queue_keeps_the_backlog()
    test_state_files_are_addable()
    test_crosspost_blocked_vs_empty()
    test_api_posting_route()
    test_crosspost_pace_and_captions()
    test_api_post_formats()
    test_social_stats_parser()
    test_setup_pod_ffmpeg()
    test_monetize_footer()
    test_studio_web_rail()
    test_desk_daily_orchestrator()
    test_profile_setup()
    test_login_vault()
    test_outreach()
    test_promo_site_converts_to_the_page()
    test_operator_url()
    test_phone_login()
    test_heartbeat_repair_signal()
    test_consult_gate()
    test_produce_loop()
    test_share_pack()
    test_k_free_status()
    test_vault_key_fallback()
    test_keyless_lyric_drafter()
    test_brand_identity()
    test_watchdog()
    test_fill_playlists()
    test_playlist_patch_is_idempotent()
    test_affiliate_short()
    test_surreal_lane()
    test_affiliate_release()
    test_affiliate_render_rail()
    test_plan_rotates_songs()
    test_priority_pin()
    test_affiliate_reserve()
    test_daily_release_saves_ledger_on_early_stop()
    test_batch_survives_a_missing_asset()
    test_release_tolerates_transient_errors()
    test_ledger_write_merges_instead_of_clobbering()
    test_youtube_quota_ledger()
    test_outputs()
    print(f"\n{PASS} passed, {FAIL} failed")
    if FAILURES:
        print("failed: " + ", ".join(FAILURES[:10]))
    return 1 if FAIL else 0


if __name__ == "__main__":
    raise SystemExit(main())
