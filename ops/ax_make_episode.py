#!/usr/bin/env python3
"""Drive the whole episode rail for one channel, in the order K requires.

The rail modules (thai_tts, audio_bed, stills_rail, video_build, episode_meta)
are libraries with no driver, so nothing joined them end to end. This is that
driver. It runs the steps in the only order that works:

  audio first  ->  prove the mix  ->  pictures  ->  metadata

K's rule (2026-10-24): retention comes from the sound, so the narration and the
music bed are built and measured before a single still is laid down.

    python3 ops/ax_make_episode.py --ch ch2 --script scripts_th/ch2_ep_heart_rest_th.md \
        --work /tmp/ep_ch2 --theme dhamma

Steps can be run alone with --only, because a 12-minute narration is long and a
rerun must not repeat the expensive part.
"""
from __future__ import annotations

import argparse
import glob
import json
import os
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import audio_bed  # noqa: E402
import episode_meta  # noqa: E402
import thai_tts  # noqa: E402
import video_build  # noqa: E402

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
DEFAULT_MUSIC = ("https://farmmer938-lgtm.github.io/aeris-store/"
                 "free/tracks/quiet-room.mp3")


def log(msg: str) -> None:
    print(msg, flush=True)


def stills_for(theme: str, work: str) -> list:
    """The stock pool for a theme, ordered for a calm build.

    The pool is already licence-checked (CC0/PD/CC BY/BY-SA, no NC/ND), so it is
    reused rather than re-harvested; `ops/stock_kit.py verify` guards it.
    """
    pool = os.path.join(ROOT, "stock", theme)
    files = sorted(glob.glob(os.path.join(pool, "s*.jpg")))
    if not files:
        raise SystemExit(f"no stills in {pool} — run ops/stock_kit.py rebuild")
    return files


def step_audio(script: str, work: str, music_url: str, gain: float) -> dict:
    title, paras = thai_tts.read_script(script)
    log(f"[audio] {title}")
    log(f"[audio] {len(paras)} paragraphs, "
        f"{sum(len(p) for p in paras)} chars, "
        f"~{sum(len(p) for p in paras)/13.6/60:.1f} min at 13.6 chars/s")

    tts_dir = os.path.join(work, "tts")
    raw, raw_secs, spoken = audio_bed.build_narration(paras, tts_dir, log=log)
    log(f"[audio] narration raw {raw_secs:.1f}s")

    norm = os.path.join(work, "narration_norm.m4a")
    audio_bed.normalize(raw, norm)

    music = os.path.join(work, os.path.basename(music_url))
    if not os.path.exists(music):
        import urllib.request
        log("[audio] fetching music bed")
        urllib.request.urlretrieve(music_url, music)

    mix = os.path.join(work, "mix.m4a")
    audio_bed.build_bed(norm, music, mix, gain=gain, log=log)

    lufs, lra = audio_bed.measure_lufs(mix)
    sil = audio_bed.measure_silence(mix)
    secs = thai_tts.audio_seconds(mix)
    log(f"[audio] mix {secs:.1f}s  {lufs} LUFS  LRA {lra}  "
        f"silences>1.2s={len(sil)}")
    audio_bed.sidecar(mix, step="audio", paragraphs=len(paras),
                      chars=sum(len(p) for p in paras), narration_secs=round(raw_secs, 1),
                      mix_lufs=lufs, mix_lra=lra, gain=gain,
                      silences_gt_1_2s=len(sil), voice=thai_tts.VOICE_MALE)
    return {"mix": mix, "tts_dir": tts_dir, "title": title, "paras": paras}


def step_video(work: str, theme: str, mix: str) -> str:
    stills = stills_for(theme, work)
    log(f"[video] {len(stills)} stills from theme '{theme}'")
    out = os.path.join(work, "episode_1080p.mp4")
    video_build.build(stills, mix, out, os.path.join(work, "segs"), log=log)
    info = video_build.probe(out)
    log(f"[video] {out}  {info['seconds']:.1f}s  {info.get('width')}x{info.get('height')}")
    return out


def step_meta(script: str, tts_dir: str, work: str, theme: str) -> dict:
    credits = os.path.join(ROOT, "stock", "CREDITS.txt")
    out_dir = os.path.join(work, "ready")
    os.makedirs(out_dir, exist_ok=True)
    meta = episode_meta.build(script, tts_dir, credits, out_dir)
    log(f"[meta] {meta['title']}  {meta['runtime']}  "
        f"{len(meta['chapters'])} chapters")
    return meta


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ch", required=True)
    ap.add_argument("--script", required=True)
    ap.add_argument("--work", required=True)
    ap.add_argument("--theme", required=True,
                    help="stock subdirectory: philosophy|dhamma|music|drama")
    ap.add_argument("--music", default=DEFAULT_MUSIC)
    ap.add_argument("--gain", type=float, default=0.34)
    ap.add_argument("--only", choices=["audio", "video", "meta"],
                    help="run a single step, reusing what earlier steps wrote")
    a = ap.parse_args()

    os.makedirs(a.work, exist_ok=True)
    state_path = os.path.join(a.work, "state.json")
    state = json.load(open(state_path, encoding="utf-8")) if os.path.exists(state_path) else {}

    if a.only in (None, "audio"):
        state.update(step_audio(a.script, a.work, a.music, a.gain))
        json.dump(state, open(state_path, "w", encoding="utf-8"),
                  ensure_ascii=False, indent=2)

    if a.only in (None, "video"):
        mix = state.get("mix") or os.path.join(a.work, "mix.m4a")
        state["video"] = step_video(a.work, a.theme, mix)
        json.dump(state, open(state_path, "w", encoding="utf-8"),
                  ensure_ascii=False, indent=2)

    if a.only in (None, "meta"):
        tts_dir = state.get("tts_dir") or os.path.join(a.work, "tts")
        state["meta"] = step_meta(a.script, tts_dir, a.work, a.theme)
        json.dump(state, open(state_path, "w", encoding="utf-8"),
                  ensure_ascii=False, indent=2)

    log(f"[done] state -> {state_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
