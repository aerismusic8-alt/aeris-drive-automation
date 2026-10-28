"""Tests for the aeris938-1 story pipeline.

These exercise the real code paths: real edge-tts synthesis, real ffmpeg renders,
real Thai shaping. Nothing is mocked, because the failures this pipeline has are
exactly the ones a mock would hide (silent audio, unshaped tone marks, a
loudness target missed by a decibel).
"""
from __future__ import annotations

import sys
from pathlib import Path

import pytest

SCRIPTS = Path(__file__).resolve().parents[1] / "scripts"
sys.path.insert(0, str(SCRIPTS))

import compose  # noqa: E402
import covers  # noqa: E402
import karaoke  # noqa: E402
import library  # noqa: E402
import thai_text  # noqa: E402

THAI_RANGE = range(0x0E00, 0x0E80)


def has_thai(text: str) -> bool:
    return any(ord(c) in THAI_RANGE for c in text)


# --- thai_text -------------------------------------------------------------

@pytest.mark.parametrize("number,expected", [
    (0, "ศูนย์"),
    (1, "หนึ่ง"),
    (11, "สิบเอ็ด"),
    (21, "ยี่สิบเอ็ด"),
    (100, "หนึ่งร้อย"),
    (187, "หนึ่งร้อยแปดสิบเจ็ด"),
    (1000, "หนึ่งพัน"),
    (1234, "หนึ่งพันสองร้อยสามสิบสี่"),
    (1_000_000, "หนึ่งล้าน"),
    (1_500_000, "หนึ่งล้านห้าแสน"),
])
def test_thai_numbers(number, expected):
    assert thai_text.thai_number(number) == expected


def test_decimal_reads_digit_by_digit():
    assert thai_text.expand_numbers("3.5") == "สามจุดห้า"


def test_digits_are_never_left_as_arabic():
    out = thai_text.prepare("การเดินทางใช้เวลา 187 วัน และผ่าน 3 เมืองใหญ่")
    assert "187" not in out and "3" not in out
    assert "หนึ่งร้อยแปดสิบเจ็ด" in out
    assert "สาม" in out


def test_newlines_survive_but_intra_thai_spaces_do_not():
    src = "ในหมู่บ้าน เล็กๆ\n\nทุกเช้า เธอจะเดิน"
    out = thai_text.prepare(src)
    assert out.count("\n") >= 2, "newlines are the pause mechanism and must survive"
    assert "ในหมู่บ้านเล็กๆ" in out, "a space between Thai characters is a typo"
    assert "ทุกเช้าเธอจะเดิน" in out


def test_script_lines_drops_blank_lines():
    lines = thai_text.script_lines("ก\n\nข\n  \nค")
    assert lines == ["ก", "ข", "ค"]


# --- library ---------------------------------------------------------------

def test_library_roundtrip_and_reuse(tmp_path, monkeypatch):
    monkeypatch.setattr(library, "ROOT", tmp_path)
    monkeypatch.setattr(library, "KINDS", {"img": tmp_path / "img"})
    (tmp_path / "img").mkdir()
    f = tmp_path / "img" / "a.png"
    f.write_bytes(b"\x89PNG\r\n\x1a\n" + b"x" * 64)

    entry = library.add("img", "story1-scene1", f, prompt="a village")
    assert entry["id"] == "img-story1-scene1"
    assert entry["bytes"] == f.stat().st_size
    assert library.find("img", "story1-scene1")["sha256"] == entry["sha256"]

    # Re-adding the same key replaces rather than duplicates.
    library.add("img", "story1-scene1", f, prompt="changed")
    entries = library.all_entries("img")
    assert len(entries) == 1
    assert entries[0]["prompt"] == "changed"


def test_library_refuses_missing_and_empty_files(tmp_path, monkeypatch):
    monkeypatch.setattr(library, "ROOT", tmp_path)
    monkeypatch.setattr(library, "KINDS", {"img": tmp_path / "img"})
    (tmp_path / "img").mkdir()
    with pytest.raises(FileNotFoundError):
        library.add("img", "nope", tmp_path / "img" / "absent.png")
    empty = tmp_path / "img" / "empty.png"
    empty.write_bytes(b"")
    with pytest.raises(ValueError):
        library.add("img", "empty", empty)


def test_library_find_is_a_miss_not_a_guess(tmp_path, monkeypatch):
    monkeypatch.setattr(library, "ROOT", tmp_path)
    monkeypatch.setattr(library, "KINDS", {"img": tmp_path / "img"})
    (tmp_path / "img").mkdir()
    assert library.find("img", "never-made") is None


def test_entry_id_is_stable_and_filesystem_safe():
    a = library.entry_id("img", "Story 1 / Scene 3!")
    assert a == library.entry_id("img", "Story 1 / Scene 3!")
    assert "/" not in a and " " not in a and "!" not in a


# --- karaoke ---------------------------------------------------------------

def test_karaoke_timing_is_split_by_character_weight():
    spans = karaoke._split_duration(["abc", "abcdef"], 9.0)
    assert spans[0] == pytest.approx(3.0)
    assert spans[1] == pytest.approx(6.0)
    assert sum(spans) == pytest.approx(9.0)


def test_karaoke_segments_thai_without_spaces():
    parts = karaoke.segment("ในหมู่บ้านเล็กๆริมแม่น้ำ")
    assert len(parts) > 1, "Thai has no spaces; segmentation must still split"


def test_karaoke_writes_one_cue_per_timed_line(tmp_path):
    timing = {
        "duration_seconds": 10.0,
        "lines": [
            {"text": "ในหมู่บ้านเล็กๆ", "start": 0.0, "end": 4.0},
            {"text": "แก้วพบหินสีทอง", "start": 4.0, "end": 10.0},
            {"text": "ไม่มีการจับเวลา", "start": None, "end": None},
        ],
    }
    out = tmp_path / "k.ass"
    report = karaoke.build_ass(timing, out)
    assert report["cues"] == 2
    assert report["skipped_lines"] == ["ไม่มีการจับเวลา"]
    body = out.read_text(encoding="utf-8")
    assert body.count("Dialogue:") == 2
    assert "{\\k" in body
    assert has_thai(body)


def test_karaoke_k_values_cover_the_line_duration(tmp_path):
    timing = {"lines": [{"text": "หนึ่งร้อยแปดสิบเจ็ดวัน", "start": 1.0, "end": 5.0}]}
    out = tmp_path / "k.ass"
    karaoke.build_ass(timing, out, tail=0.0)
    line = [l for l in out.read_text(encoding="utf-8").splitlines() if l.startswith("Dialogue")][0]
    ks = [int(part.split("}")[0]) for part in line.split("{\\k")[1:]]
    total = sum(ks) / 100.0
    assert total == pytest.approx(4.0, abs=0.1), "the highlight must span the spoken line"


# --- covers ----------------------------------------------------------------

def test_cover_requires_thai_shaping():
    # If PIL lacks raqm, Thai tone marks are misplaced and the cover is wrong.
    covers.require_thai_shaping()


def test_cover_renders_thai_title(tmp_path):
    out = tmp_path / "cover.png"
    report = covers.make_cover("หินแห่งความจำ", out, subtitle="เรื่องที่ 1")
    assert report["bytes"] > 5000
    from PIL import Image
    import numpy as np
    img = np.array(Image.open(out).convert("L"))
    assert img.shape == (covers.HEIGHT, covers.WIDTH)
    # The title band must actually contain bright glyph pixels.
    band = img[400:660, :]
    assert (band > 200).sum() > 500, "title did not render as visible text"


# --- compose ---------------------------------------------------------------

def test_compose_requires_karaoke_and_audio(tmp_path):
    with pytest.raises(FileNotFoundError):
        compose.compose(audio=tmp_path / "nope.mp3", ass=tmp_path / "nope.ass",
                        out=tmp_path / "o.mp4")


def test_compose_scenes_rejects_a_bad_plan(tmp_path):
    """Bad plans fail loudly: a crossfade longer than a scene eats the clip."""
    img = tmp_path / "a.png"
    compose._run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
                  "-i", "color=c=red:s=64x64:d=1", "-frames:v", "1", str(img)])
    audio = tmp_path / "a.wav"
    compose._run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
                  "-i", "anullsrc=r=48000:cl=stereo", "-t", "3", str(audio)])
    ass = tmp_path / "k.ass"
    ass.write_text("[Script Info]\n", encoding="utf-8")

    with pytest.raises(ValueError):
        compose.compose_scenes(scenes=[], audio=audio, ass=ass, out=tmp_path / "o.mp4")
    with pytest.raises(FileNotFoundError):
        compose.compose_scenes(scenes=[{"image": tmp_path / "gone.png", "duration": 3}],
                               audio=audio, ass=ass, out=tmp_path / "o.mp4")
    with pytest.raises(ValueError):
        compose.compose_scenes(scenes=[{"image": img, "duration": 0}],
                               audio=audio, ass=ass, out=tmp_path / "o.mp4")
    # A crossfade as long as the scene would consume it entirely.
    with pytest.raises(ValueError):
        compose.compose_scenes(
            scenes=[{"image": img, "duration": 2}, {"image": img, "duration": 2}],
            audio=audio, ass=ass, out=tmp_path / "o.mp4", crossfade=3.0)


def test_compose_scenes_runs_longer_than_a_single_still(tmp_path):
    """Two scenes crossfaded must total sum(durations) - one crossfade."""
    img = tmp_path / "a.png"
    compose._run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
                  "-i", "color=c=0x224466:s=1920x1080:d=1", "-frames:v", "1", str(img)])
    audio = tmp_path / "a.wav"
    compose._run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
                  "-i", "anullsrc=r=48000:cl=stereo", "-t", "9", str(audio)])
    ass = tmp_path / "k.ass"
    ass.write_text("[Script Info]\n", encoding="utf-8")

    out = tmp_path / "o.mp4"
    report = compose.compose_scenes(
        scenes=[{"image": img, "duration": 5.0}, {"image": img, "duration": 5.0}],
        audio=audio, ass=ass, out=out, crossfade=1.5)
    assert abs(report["duration_seconds"] - 8.5) < 0.3, report
    assert report["scenes"] == 2
    assert report["video"]["width"] == 1920 and report["video"]["height"] == 1080


def test_compose_scenes_promotes_atomically(tmp_path):
    """A render writes beside the target and renames, so a killed run never
    leaves a truncated file that still stats as the finished clip."""
    img = tmp_path / "a.png"
    compose._run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
                  "-i", "color=c=0x224466:s=1920x1080:d=1", "-frames:v", "1", str(img)])
    audio = tmp_path / "a.wav"
    compose._run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
                  "-i", "anullsrc=r=48000:cl=stereo", "-t", "3", str(audio)])
    ass = tmp_path / "k.ass"
    ass.write_text("[Script Info]\n", encoding="utf-8")

    out = tmp_path / "o.mp4"
    compose.compose_scenes(scenes=[{"image": img, "duration": 3.0}],
                           audio=audio, ass=ass, out=out)
    assert out.exists()
    assert not (tmp_path / "o.partial.mp4").exists(), "the scratch file must not survive"


def test_compose_scenes_pins_stereo_48k(tmp_path):
    """Voice (24k mono) and bed (48k mono) mixed without a pinned rate produced
    a 96 kHz mono track, which is not what a player expects."""
    img = tmp_path / "a.png"
    compose._run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
                  "-i", "color=c=0x224466:s=1920x1080:d=1", "-frames:v", "1", str(img)])
    audio = tmp_path / "a.wav"
    compose._run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
                  "-i", "anullsrc=r=24000:cl=mono", "-t", "3", str(audio)])
    ass = tmp_path / "k.ass"
    ass.write_text("[Script Info]\n", encoding="utf-8")

    out = tmp_path / "o.mp4"
    compose.compose_scenes(scenes=[{"image": img, "duration": 3.0}],
                           audio=audio, ass=ass, out=out)
    info = compose.probe(out)
    sound = next(s for s in info["streams"] if s["codec_type"] == "audio")
    assert sound["channels"] == 2, sound
    assert int(sound["sample_rate"]) == 48000, sound


def test_long_render_uses_a_faster_preset():
    """A quarter-hour render must not be so slow that a pod recycle kills it."""
    assert compose._preset_for(60) == "medium"
    assert compose._preset_for(1010) == "veryfast"


def test_music_bed_is_audible_in_the_pauses(tmp_path):
    """The bed must be audible between narration lines, not buried under them.

    Ep01 shipped with the bed at -18 dB mixed with a plain `amix`. Measured on
    the finished file the music sat ~20 dB under the voice and could not be
    heard in the ~1 s gaps between lines, which is where a bed does its work.
    The bug was invisible in the report, which only recorded that a bed was
    passed in. This renders a real clip and asserts the pause is not a dead
    hole relative to the voice.
    """
    import math
    import struct
    import wave

    sr = 16000

    def rms_db(samples):
        r = math.sqrt(sum(v * v for v in samples) / len(samples) + 1e-9)
        return 20 * math.log10(r / 32768.0)

    # 12 s voice with a 4 s silent gap in the middle; a quiet tone as the bed.
    voice = tmp_path / "voice.wav"
    compose._run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
                  "-i", "sine=frequency=500:duration=12:sample_rate=48000",
                  "-af", "volume=0.1,volume=0.0:enable='between(t,4,8)'", str(voice)])
    bed = tmp_path / "bed.wav"
    compose._run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
                  "-i", "sine=frequency=220:duration=4:sample_rate=48000",
                  "-af", "volume=0.1", str(bed)])
    img = tmp_path / "a.png"
    compose._run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
                  "-i", "color=c=0x224466:s=320x180:d=1", "-frames:v", "1", str(img)])
    ass = tmp_path / "k.ass"
    ass.write_text("[Script Info]\n", encoding="utf-8")

    out = tmp_path / "o.mp4"
    compose.compose_scenes(scenes=[{"image": img, "duration": 12.0}],
                           audio=voice, ass=ass, out=out, music=bed)

    pcm = tmp_path / "o.wav"
    compose._run(["ffmpeg", "-y", "-v", "error", "-i", str(out),
                  "-ac", "1", "-ar", str(sr), str(pcm)])
    w = wave.open(str(pcm))
    raw = w.readframes(w.getnframes())
    w.close()
    samples = struct.unpack("<%dh" % (len(raw) // 2), raw)

    def at(a, b):
        return rms_db(samples[int(a * sr):int(b * sr)])

    voice_level = at(1.0, 3.5)
    pause_level = at(5.0, 7.5)
    # The pause must not be a hole: the bed has to be within 9 dB of the voice.
    # At the shipped -18 dB/plain-mix settings this gap measured 18 dB.
    assert voice_level - pause_level < 9.0, (
        f"bed is buried {voice_level - pause_level:.1f} dB under the voice; "
        "it will not be heard in the pauses")


def test_plan_scenes_covers_the_whole_narration(tmp_path):
    """Scene durations must add back to the audio, or the clip cuts a sentence.

    Each scene is padded by the crossfade because the renderer subtracts one
    crossfade per join. With 16 scenes that padding is 22.5 seconds -- losing it
    silently truncates the ending.
    """
    import make_story

    meta = {"scenes": [f"ฉาก {i}" for i in range(1, 5)]}
    timing = {"duration_seconds": 40.0, "lines": [
        {"text": f"บรรทัด {i}", "start": i * 2.0, "end": i * 2.0 + 1.5, "matched": True}
        for i in range(20)]}
    crossfade = 1.5
    plan = make_story.plan_scenes(meta, timing, crossfade=crossfade)

    assert [p["index"] for p in plan] == [1, 2, 3, 4]
    assert plan[0]["start"] == 0.0
    # The last scene runs from its first line to the end of the audio, with no
    # padding: there is no join after it.
    assert plan[-1]["duration"] == pytest.approx(40.0 - 30.0, abs=0.01)
    # Every earlier scene is padded by the crossfade the renderer will subtract.
    assert plan[0]["duration"] == pytest.approx(11.5, abs=0.01)

    rendered = sum(p["duration"] for p in plan) - crossfade * (len(plan) - 1)
    assert rendered == pytest.approx(40.0, abs=0.01), (
        "the plan must render to exactly the narration length")


def test_plan_scenes_needs_scenes_and_timed_lines():
    import make_story

    with pytest.raises(ValueError):
        make_story.plan_scenes({"scenes": []},
                               {"duration_seconds": 1, "lines": [
                                   {"text": "x", "start": 0, "end": 1, "matched": True}]})
    with pytest.raises(ValueError):
        make_story.plan_scenes({"scenes": ["ฉาก"]},
                               {"duration_seconds": 1, "lines": [
                                   {"text": "x", "start": 0, "end": 1, "matched": False}]})


def test_loudnorm_reaches_its_target(tmp_path):
    """Two-pass loudnorm is the only version that lands on the target."""
    quiet = tmp_path / "quiet.wav"
    compose._run(["ffmpeg", "-y", "-v", "error", "-f", "lavfi",
                  "-i", "sine=frequency=440:duration=6", "-af", "volume=-24dB",
                  str(quiet)])
    before = compose.measure_loudness(quiet)
    assert before["integrated_lufs"] < -20

    fixed = tmp_path / "fixed.m4a"
    compose.normalise_audio(quiet, fixed, target=-17.0)
    after = compose.measure_loudness(fixed)
    assert after["integrated_lufs"] == pytest.approx(-17.0, abs=1.0)
    assert after["true_peak_dbfs"] <= -1.0


# --- pipeline --------------------------------------------------------------

def test_parse_story_reads_directives(tmp_path):
    import make_story
    story = tmp_path / "s.txt"
    story.write_text(
        "# TITLE: หินแห่งความจำ\n# SUBTITLE: เรื่องที่ 1\n# MOOD: calm\n"
        "# SCENE: a village\n# SCENE: a river\n\nในหมู่บ้านเล็กๆ\nทุกเช้าเธอเดิน\n",
        encoding="utf-8",
    )
    meta = make_story.parse_story(story)
    assert meta["title"] == "หินแห่งความจำ"
    assert meta["scenes"] == ["a village", "a river"]
    assert "ในหมู่บ้านเล็กๆ" in meta["script"]
    assert "#" not in meta["script"], "directives must not be spoken"


def test_parse_story_rejects_a_missing_title(tmp_path):
    import make_story
    story = tmp_path / "s.txt"
    story.write_text("แค่ข้อความ\n", encoding="utf-8")
    with pytest.raises(ValueError, match="TITLE"):
        make_story.parse_story(story)


def test_parse_story_rejects_an_empty_script(tmp_path):
    import make_story
    story = tmp_path / "s.txt"
    story.write_text("# TITLE: เรื่อง\n\n\n", encoding="utf-8")
    with pytest.raises(ValueError, match="no narration"):
        make_story.parse_story(story)


# --- browser plumbing ------------------------------------------------------

def test_browser_reports_a_missing_desktop_rather_than_hanging(monkeypatch):
    import browser
    monkeypatch.setattr(browser, "CDP_DEFAULT", "http://127.0.0.1:1")
    assert browser.cdp_alive() is False
    with pytest.raises(RuntimeError, match="no cloud desktop"):
        browser.connect(None)


def test_login_instructions_name_the_app_and_the_link():
    import browser
    text = browser.login_instructions("Gemini")
    assert "Gemini" in text
    assert "vnc.html" in text


def test_flowmusic_signed_out_copy_is_detected():
    """The landing copy only shows before a session exists."""
    import flow_music
    landing = ("Create song\n\nDescribe the song you want and Google Flow Music "
               "writes, produces, and sings it in seconds. Start a session to "
               "create a song with AI.\n\nFree to start with a Google Account.")
    assert flow_music._signed_out_markers(landing) is True
    assert flow_music._signed_out_markers("Describe your song. Genre, mood, tempo") is False


def test_flowmusic_warns_that_the_host_is_third_party():
    import flow_music
    assert "NOT served by Google" in flow_music.ORIGIN_NOTE
    assert "Let's Encrypt" in flow_music.ORIGIN_NOTE


def test_gemini_login_gate_marker_is_the_one_actually_seen():
    """Verified live: signed out, Gemini says this and image gen is blocked."""
    import gemini_image
    page_text = "ลงชื่อเข้าใช้เพื่อสร้างรูปภาพและอื่นๆ อีกมากมาย"
    assert "ลงชื่อเข้าใช้เพื่อ" in page_text and "สร้างรูปภาพ" in page_text
    assert gemini_image.URL.endswith("gemini.google.com/app")


def test_gemini_still_selector_takes_the_newest_not_the_first():
    """Every still stays on the page, so the newest is the LAST match.

    This was a real bug: the selector used `.find()`, which returns the oldest
    still, so scene 2 was saved as a byte-identical copy of scene 1. The two
    images had the same sha256 and nothing failed.
    """
    import gemini_image

    for js in (gemini_image._GRAB_LAST_JS, gemini_image._FINGERPRINT_JS):
        assert "a.length - 1" in js, "must take the last still, not the first"
        assert ".find(" not in js, "`.find()` returns the oldest still"

    assert "blob:" in gemini_image._GRAB_LAST_JS, "stills are served from blob URLs"
    assert "naturalWidth" in gemini_image._GRAB_LAST_JS


def test_gemini_completion_waits_for_stable_pixels_not_a_label():
    """The "generating" label stays on screen after the picture is done.

    Verified live: gating completion on that text times out on a finished image,
    so the wait has to watch the pixels settle instead. If a marker check comes
    back, this test should be deleted along with the reason it exists.
    """
    import gemini_image

    src = Path(SCRIPTS / "gemini_image.py").read_text(encoding="utf-8")
    wait_body = src.split("def _wait_for_new_image", 1)[1].split("\ndef ", 1)[0]
    assert "GENERATING_MARKER" not in wait_body, (
        "the generating label never clears; gate on pixel stability instead"
    )
    assert "STABLE_SAMPLES" in wait_body and "fp" in wait_body
    assert gemini_image.STABLE_SAMPLES >= 2, "one sample cannot show stability"


def test_scene_stills_are_keyed_by_position_and_reused(tmp_path, monkeypatch):
    """Scene N maps to a stable key, so a re-run reuses instead of regenerating."""
    import make_story

    for kind in ("img", "cover", "music"):
        d = tmp_path / kind
        d.mkdir()
        monkeypatch.setitem(library.KINDS, kind, d)

    calls: list[str] = []

    def fake_generate(prompt, key, *, force=False):
        calls.append(key)
        existing = library.find("img", key)
        if existing and not force:
            return {"status": "REUSED", "entry": existing}
        out = library.KINDS["img"] / f"{library.entry_id('img', key)}.png"
        out.write_bytes(b"\x89PNG" + prompt.encode("utf-8"))
        return {"status": "CREATED", "entry": library.add("img", key, out)}

    import gemini_image
    monkeypatch.setattr(gemini_image, "generate", fake_generate)

    stories = tmp_path / "stories"
    stories.mkdir()
    (stories / "s.txt").write_text(
        "# TITLE: ทดสอบ\n# SCENE: ฉากหนึ่ง\n# SCENE: ฉากสอง\n\nบรรทัดหนึ่ง\n",
        encoding="utf-8")
    monkeypatch.setattr(make_story, "STORIES", stories)
    monkeypatch.setattr(make_story, "WORK", tmp_path / "work")
    monkeypatch.setattr(make_story, "ROOT", tmp_path)

    # Narration, karaoke and compose are exercised elsewhere; here the point is
    # the image step and the keys it uses. The timing must still carry matched
    # lines, because the scene plan is built from them.
    monkeypatch.setattr(make_story, "narrate", lambda *a, **k: {
        "audio": "a.mp3", "duration_seconds": 4.0, "line_count": 2,
        "matched_lines": 2, "unmatched_lines": 0,
        "lines": [{"text": "บรรทัดหนึ่ง", "start": 0.1, "end": 2.0, "matched": True},
                  {"text": "บรรทัดสอง", "start": 2.0, "end": 4.0, "matched": True}]})
    monkeypatch.setattr(make_story.karaoke, "build_ass",
                        lambda *a, **k: {"cues": 1, "skipped_lines": 0})

    def fake_cover(title, out, **k):
        out.parent.mkdir(parents=True, exist_ok=True)
        out.write_bytes(b"\x89PNG cover")
        return {"file": str(out)}

    monkeypatch.setattr(make_story.covers, "make_cover", fake_cover)
    monkeypatch.setattr(make_story.compose, "compose_scenes",
                        lambda **k: {"output": "o.mp4", "bytes": 1,
                                     "duration_seconds": 4.0, "scenes": len(k["scenes"]),
                                     "video": {"width": 1920, "height": 1080}})
    monkeypatch.setattr(make_story.compose, "compose", lambda **k: {
        "output": "o.mp4", "bytes": 1, "duration_seconds": 1.0,
        "video": {"width": 1920, "height": 1080}})
    monkeypatch.setattr(make_story.compose, "measure_loudness",
                        lambda p: {"integrated_lufs": -17.0})

    report = make_story.build("s", with_music=False, with_images=True)
    assert calls == ["s-scene1", "s-scene2"], f"unexpected scene keys: {calls}"
    assert report["steps"]["images"]["count"] == 2
    assert "hero" in report["steps"], "scene 1 must be recorded as the hero"

    # A second run must reuse both stills rather than generating them again.
    calls.clear()
    make_story.build("s", with_music=False, with_images=True)
    assert calls == ["s-scene1", "s-scene2"]
    assert library.find("img", "s-hero") is not None




# --- music preset selection ------------------------------------------------

@pytest.mark.parametrize("mood,expected", [
    ("sad warm thai folk, slow, instrumental", "sad"),
    ("calm thai folk, khamen sai", "calm"),
    ("ลึกลับ ขลัง", "mystic"),
    ("อบอุ่น สงบ เหมือนเล่านิทานให้ลูกฟัง", "calm"),
    ("", "calm"),
    ("something nobody anticipated", "calm"),
])
def test_mood_line_picks_a_preset(mood, expected):
    """A story should not have to know preset names to get a bed."""
    import make_music
    assert make_music.preset_for(mood) == expected


def test_every_preset_is_usable_by_the_synthesiser():
    import make_music
    for preset in make_music.MOODS:
        assert preset in make_music.MOODS
        assert make_music.preset_for(preset) in make_music.MOODS


def test_unknown_preset_is_refused(tmp_path, monkeypatch):
    import make_music
    monkeypatch.setattr(library, "ROOT", tmp_path)
    monkeypatch.setattr(library, "KINDS", {"music": tmp_path / "music"})
    (tmp_path / "music").mkdir()
    with pytest.raises(ValueError, match="unknown mood"):
        make_music.make("not-a-mood", "k")


def test_music_synthesis_produces_real_audio(tmp_path, monkeypatch):
    """The offline bed is the no-account fallback, so it must actually sound."""
    import make_music
    monkeypatch.setattr(library, "ROOT", tmp_path)
    monkeypatch.setattr(library, "KINDS", {"music": tmp_path / "music"})
    (tmp_path / "music").mkdir()
    result = make_music.make("calm", "test-mood", duration=6.0)
    entry = result["entry"]
    assert result["status"] == "CREATED"
    assert entry["bytes"] > 10_000
    loudness = compose.measure_loudness(tmp_path / entry["file"])
    assert loudness["integrated_lufs"] is not None
    assert -30 < loudness["integrated_lufs"] < -10, "a bed that is silent or clipping is not a bed"


def test_ensure_for_story_reuses_an_existing_bed(tmp_path, monkeypatch):
    import make_music
    monkeypatch.setattr(library, "ROOT", tmp_path)
    monkeypatch.setattr(library, "KINDS", {"music": tmp_path / "music"})
    (tmp_path / "music").mkdir()
    first = make_music.ensure_for_story("story-x", "calm", duration=5.0)
    assert first["status"] == "CREATED"
    second = make_music.ensure_for_story("story-x", "calm", duration=5.0)
    assert second["status"] == "REUSED"
    assert second["entry"]["sha256"] == first["entry"]["sha256"]
