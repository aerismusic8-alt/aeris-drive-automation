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
