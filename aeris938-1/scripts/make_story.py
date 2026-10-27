#!/usr/bin/env python3
"""Build one story episode: narration, karaoke, cover, clip.

The story file is the input. Everything downstream is derived, so a re-run
reuses whatever is already in the library instead of regenerating it.

  aeris938-1/stories/<name>.txt

  # TITLE: หินแห่งความจำ
  # SUBTITLE: เรื่องที่ 1 · นิทานไทย
  # MOOD: calm thai folk, khamen sai, warm, slow, instrumental
  # SCENE: หมู่บ้านไทยยามพระอาทิตย์ตก ริมแม่น้ำ

  ในหมู่บ้านเล็กๆ ริมแม่น้ำ มีเด็กหญิงคนหนึ่งชื่อว่าแก้ว
  ...

`#` lines are directives, blank lines separate spoken paragraphs, and every
other line is narration. Directives are optional except TITLE.
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compose  # noqa: E402
import covers  # noqa: E402
import karaoke  # noqa: E402
import library  # noqa: E402
from narration import DEFAULT_RATE, VOICE_FEMALE, VOICE_MALE, narrate  # noqa: E402

ROOT = Path(__file__).resolve().parents[1]
STORIES = ROOT / "stories"
WORK = ROOT / "work"


def parse_story(path: Path) -> dict:
    text = Path(path).read_text(encoding="utf-8")
    meta: dict = {"scenes": []}
    spoken: list[str] = []
    for line in text.splitlines():
        m = re.match(r"^#\s*([A-Z_]+)\s*:\s*(.+?)\s*$", line)
        if m:
            field, value = m.group(1), m.group(2)
            if field == "SCENE":
                meta["scenes"].append(value)
            else:
                meta[field.lower()] = value
            continue
        spoken.append(line)
    meta["script"] = "\n".join(spoken).strip()
    if not meta.get("title"):
        raise ValueError(f"{path}: missing '# TITLE:' directive")
    if not meta["script"]:
        raise ValueError(f"{path}: no narration lines")
    return meta


def build(name: str, *, voice: str = VOICE_MALE, rate: str = DEFAULT_RATE,
          force_images: bool = False, with_music: bool = True) -> dict:
    story_path = STORIES / f"{name}.txt"
    meta = parse_story(story_path)
    work = WORK / name
    work.mkdir(parents=True, exist_ok=True)
    report: dict = {"story": name, "title": meta["title"], "steps": {}}

    # 1. Narration + timing.
    timing = narrate(meta["script"], work, voice=voice, rate=rate, name="narration")
    report["steps"]["narration"] = {
        "duration_seconds": timing["duration_seconds"],
        "lines": timing["line_count"],
        "matched": timing["matched_lines"],
        "unmatched": timing["unmatched_lines"],
    }

    # 2. Karaoke track.
    ass = work / "karaoke.ass"
    k = karaoke.build_ass(timing, ass)
    report["steps"]["karaoke"] = {"cues": k["cues"], "skipped": k["skipped_lines"]}
    if k["cues"] == 0:
        raise RuntimeError("no karaoke cues were produced; refusing to render a silent-subtitle clip")

    # 3. Cover, one per story, keyed by story name.
    cover_key = f"{name}-cover"
    cover_entry = library.find("cover", cover_key)
    hero = library.find("img", f"{name}-hero")
    if cover_entry is None or not (ROOT / cover_entry["file"]).exists():
        cover_path = library.KINDS["cover"] / f"{library.entry_id('cover', cover_key)}.png"
        c = covers.make_cover(meta["title"], cover_path,
                              image=(ROOT / hero["file"]) if hero else None,
                              subtitle=meta.get("subtitle"))
        cover_entry = library.add("cover", cover_key, cover_path,
                                  title=meta["title"], subtitle=meta.get("subtitle"),
                                  source="pipeline")
    report["steps"]["cover"] = {"file": cover_entry["file"], "bytes": cover_entry["bytes"]}

    # 4. Music bed. Prefer one already in the library; otherwise synthesise an
    # offline bed from the story's MOOD line, so an unattended run never ships
    # silent. flowmusic.app is third-party and deliberately not used here.
    music_path = None
    if with_music:
        mood_key = f"{name}-mood"
        mood_entry = library.find("music", mood_key)
        if mood_entry and (ROOT / mood_entry["file"]).exists():
            music_path = ROOT / mood_entry["file"]
            report["steps"]["music"] = {"file": mood_entry["file"], "reused": True}
        else:
            import make_music
            try:
                gen = make_music.ensure_for_story(name, meta.get("mood", ""))
                entry = gen["entry"]
                music_path = ROOT / entry["file"]
                report["steps"]["music"] = {
                    "file": entry["file"], "reused": False,
                    "preset": gen.get("preset"), "source": entry.get("source"),
                }
            except Exception as exc:  # noqa: BLE001 - a missing bed is not fatal
                report["steps"]["music"] = {
                    "missing": True, "error": f"{type(exc).__name__}: {exc}",
                    "hint": f"scripts/flow_music.py {mood_key} \"{meta.get('mood','')}\"",
                }

    # 5. Compose.
    clip = work / f"{name}.mp4"
    result = compose.compose(image=None, audio=work / timing["audio"], ass=ass,
                             out=clip, music=music_path)

    # 6. Loudness: measure, and if it is off target, correct with two-pass
    # loudnorm. A clip that misses the target is fixed, not just reported.
    target = -17.0
    measured = compose.measure_loudness(clip)
    result["loudness_before"] = measured
    if measured["integrated_lufs"] is None or abs(measured["integrated_lufs"] - target) > 1.0:
        fixed = work / f"{name}.normalised.mp4"
        norm = compose.normalise_audio(clip, fixed, target=target)
        if fixed.exists() and fixed.stat().st_size > 0:
            fixed.replace(clip)
            result["loudnorm"] = norm
            measured = compose.measure_loudness(clip)
    result["loudness"] = measured
    report["steps"]["clip"] = result
    return report


def main() -> int:
    ap = argparse.ArgumentParser(description="Build one story episode")
    ap.add_argument("name", help="story file stem under stories/")
    ap.add_argument("--voice", choices=[VOICE_MALE, VOICE_FEMALE], default=VOICE_MALE)
    ap.add_argument("--rate", default=DEFAULT_RATE)
    ap.add_argument("--no-music", action="store_true")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    report = build(args.name, voice=args.voice, rate=args.rate,
                   with_music=not args.no_music)
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        s = report["steps"]
        print(f"story      : {report['title']} ({report['story']})")
        print(f"narration  : {s['narration']['duration_seconds']}s, "
              f"{s['narration']['matched']}/{s['narration']['lines']} lines timed")
        print(f"karaoke    : {s['karaoke']['cues']} cues")
        print(f"cover      : {s['cover']['file']}")
        print(f"music      : {s['music'].get('file') or 'none'}")
        c = s["clip"]
        print(f"clip       : {c['output']} {c['bytes']}B "
              f"{c['video']['width']}x{c['video']['height']} {c['duration_seconds']}s")
        print(f"loudness   : {c['loudness']['integrated_lufs']} LUFS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
