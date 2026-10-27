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
import math
import re
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

import compose  # noqa: E402
import covers  # noqa: E402
import karaoke  # noqa: E402
import library  # noqa: E402
from browser import LoginRequired  # noqa: E402
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


def plan_scenes(meta: dict, timing: dict, crossfade: float = 1.5) -> list[dict]:
    """Split the narration into per-scene spans and pair each with its still.

    Lines are handed out evenly rather than by counting characters: the story is
    written one clause per line, so line count is already the rhythm. The last
    scene runs to the end of the audio so the clip never cuts a sentence off.

    Each scene is padded by `crossfade` because the renderer overlaps the joins
    and subtracts one crossfade per join from the total; without the padding the
    finished clip would run `crossfade * (scenes - 1)` short of the narration.
    """
    lines = [l for l in timing["lines"] if l.get("matched")]
    scenes = meta.get("scenes") or []
    if not lines:
        raise ValueError("no matched narration lines to lay out")
    if not scenes:
        raise ValueError("the story has no '# SCENE:' directives")

    per = math.ceil(len(lines) / len(scenes))
    total_audio = float(timing["duration_seconds"])
    plan: list[dict] = []
    for index, prompt in enumerate(scenes):
        chunk = lines[index * per:(index + 1) * per]
        if not chunk:
            break
        start = float(chunk[0]["start"])
        if index + 1 < len(scenes) and lines[(index + 1) * per:]:
            nxt = lines[(index + 1) * per]
            end = float(nxt["start"])
        else:
            end = total_audio
        span = max(0.5, end - start)
        pad = crossfade if index < len(scenes) - 1 else 0.0
        plan.append({"index": index + 1, "prompt": prompt, "start": start,
                     "duration": span + pad})
    return plan


def build(name: str, *, voice: str = VOICE_MALE, rate: str = DEFAULT_RATE,
          force_images: bool = False, with_music: bool = True,
          with_images: bool = True, force_narration: bool = False) -> dict:
    story_path = STORIES / f"{name}.txt"
    meta = parse_story(story_path)
    work = WORK / name
    work.mkdir(parents=True, exist_ok=True)
    report: dict = {"story": name, "title": meta["title"], "steps": {}}

    # 1. Narration + timing. Reused when the script has not changed: synthesis
    # takes minutes for a quarter-hour story, and the timing only depends on the
    # line count and the voice. A changed script changes the count, so it re-runs.
    timing_path = work / "narration.timing.json"
    timing = None
    script_lines = [l for l in meta["script"].splitlines() if l.strip()]
    if timing_path.exists() and not force_narration:
        cached = json.loads(timing_path.read_text(encoding="utf-8"))
        audio_present = (work / cached.get("audio", "")).exists()
        if (audio_present and cached.get("line_count") == len(script_lines)
                and cached.get("voice") == voice and cached.get("rate") == rate):
            timing = cached
    if timing is None:
        timing = narrate(meta["script"], work, voice=voice, rate=rate, name="narration")
        timing_path.write_text(json.dumps(timing, ensure_ascii=False, indent=2),
                               encoding="utf-8")
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

    # 3. Scene stills. Each `# SCENE:` line is one picture, keyed by its position
    # so the same scene is reused on a re-run instead of being paid for twice.
    # The first scene doubles as the hero image the cover is drawn over.
    #
    # A scene needs the signed-in cloud desktop. If it is not signed in the run
    # stops here rather than shipping an episode whose art silently went missing;
    # --no-images skips the step for a text-only build.
    scene_images: list[dict] = []
    if with_images:
        import gemini_image

        # A still occasionally times out because Gemini is slow, not because the
        # prompt is bad. One missing picture should not sink a sixteen-scene
        # episode, so a failed scene falls back to the nearest still that did
        # render and the failure is recorded rather than hidden.
        failed: list[int] = []
        for index, scene in enumerate(meta["scenes"], start=1):
            key = f"{name}-scene{index}"
            try:
                result = gemini_image.generate(scene, key, force=force_images)
                scene_images.append(result["entry"])
            except gemini_image.LoginRequired:
                raise
            except Exception as exc:
                if not scene_images:
                    raise
                failed.append(index)
                report.setdefault("warnings", []).append(
                    f"scene {index} still failed, reusing the previous image: {exc}")
                scene_images.append(scene_images[-1])
        report["steps"]["images"] = {
            "count": len(scene_images),
            "failed": failed,
            "files": [e["file"] for e in scene_images],
        }
        hero_key = f"{name}-hero"
        if library.find("img", hero_key) is None and scene_images:
            hero_entry = library.add("img", hero_key, ROOT / scene_images[0]["file"],
                                     source="gemini-web", prompt=meta["scenes"][0],
                                     provider="gemini.google.com",
                                     derived_from=scene_images[0]["id"])
            report["steps"]["hero"] = {"file": hero_entry["file"]}

    # 4. Cover, one per story, keyed by story name.
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

    # 5. Compose. With scene stills the clip is long-form: one still per scene,
    # panned and crossfaded. Without them it falls back to the single-still
    # renderer so a text-only build still produces something watchable.
    clip = work / f"{name}.mp4"
    plan = plan_scenes(meta, timing) if scene_images else []
    if plan:
        scenes = [{"image": ROOT / e["file"], "duration": p["duration"]}
                  for p, e in zip(plan, scene_images)]
        result = compose.compose_scenes(scenes=scenes, audio=work / timing["audio"],
                                        ass=ass, out=clip, music=music_path)
        report["steps"]["scene_plan"] = [
            {"scene": p["index"], "prompt": p["prompt"],
             "start": round(p["start"], 2), "duration": round(p["duration"], 2),
             "image": e["file"]}
            for p, e in zip(plan, scene_images)]
    else:
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
    ap.add_argument("--no-images", action="store_true",
                    help="skip scene stills (no cloud desktop needed)")
    ap.add_argument("--json", action="store_true")
    args = ap.parse_args()
    try:
        report = build(args.name, voice=args.voice, rate=args.rate,
                       with_music=not args.no_music,
                       with_images=not args.no_images)
    except LoginRequired as exc:
        print(str(exc), file=sys.stderr)
        return 3
    if args.json:
        print(json.dumps(report, ensure_ascii=False, indent=2))
    else:
        s = report["steps"]
        print(f"story      : {report['title']} ({report['story']})")
        print(f"narration  : {s['narration']['duration_seconds']}s, "
              f"{s['narration']['matched']}/{s['narration']['lines']} lines timed")
        print(f"karaoke    : {s['karaoke']['cues']} cues")
        if "images" in s:
            print(f"images     : {s['images']['count']} scene still(s)")
        print(f"cover      : {s['cover']['file']}")
        print(f"music      : {s['music'].get('file') or 'none'}")
        c = s["clip"]
        print(f"clip       : {c['output']} {c['bytes']}B "
              f"{c['video']['width']}x{c['video']['height']} {c['duration_seconds']}s")
        print(f"loudness   : {c['loudness']['integrated_lufs']} LUFS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
