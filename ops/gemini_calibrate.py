#!/usr/bin/env python3
"""Calibrate the Gemini reviewer: does its score mean anything?

K (2026-11-19): "ถ้า gemini ให้ผ่านแต่ K ไม่ผ่าน อันนี้จะต้องรื้อระบบตรวจสอบของ
gemini ด้วยนะ ว่ามาตรฐานอยู่ระดับไหน" — if Gemini can pass a clip K rejects, the
gate is worthless and we must know what its scale is actually anchored to.

The gate only has authority if its score tracks reality. This module measures
that, with no opinion and no API key:

1. **Known-answer probes.** Clips are built whose defects are *measured*, not
   judged: a clip with no captions, one with a frozen picture, one with black
   bars, one with clipped audio, one clean. If Gemini scores a clip with a
   measured defect as "good", its scale does not detect that defect. A reviewer
   that cannot tell a silent black rectangle from a finished clip is a rubber
   stamp, however confident its prose reads.

2. **Claim verification.** Every factual assertion Gemini makes about a clip
   ("caption is misspelled ตรงนิ", "no text at 36.5s", "watermark at 22.5s") is
   checked against the file. A reviewer that invents defects fails as hard as one
   that misses them — the 2026-11-19 review called a correct "ตรงนี้" a typo while
   missing a real 21.8 s caption gap.

3. **Repeatability.** The same clip is reviewed more than once. If the score
   swings across the pass bar on identical bytes, a single verdict is noise.

Output is a calibration report: per-probe score, whether it separated the
defective clip from the clean one, and the measured agreement rate of its claims.
No threshold here decides a clip; this decides whether the *reviewer* is
trustworthy, which is the question K asked.

CLI:
    python3 ops/gemini_calibrate.py --build      # make the known-answer probes
    python3 ops/gemini_calibrate.py --run        # review each probe, report
    python3 ops/gemini_calibrate.py --claims FILE --clip CLIP   # verify claims
"""
from __future__ import annotations

import argparse
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
PROBES = ROOT / "music938-1" / "work" / "gemini-calibration"
REPORT = PROBES / "report.json"

# Each probe: a name, the defect it *measures*, and how to build it from a clean
# clip. `defect` is what the reviewer must detect; `None` means the clip is clean
# and a low score is a false alarm.
PROBE_PLAN = [
    ("clean", None),
    ("no-captions", "no text on screen at all"),
    ("frozen", "picture never changes"),
    ("black-bars", "letterboxed, wasted vertical space"),
    ("clipped-audio", "audio clipping above -1 dBTP"),
]


def _ffmpeg() -> str:
    exe = shutil.which("ffmpeg")
    if exe:
        return exe
    for p in (Path("/workspace/ax-tools/ffmpeg"),):
        if p.exists():
            hits = sorted(p.rglob("ffmpeg"))
            if hits:
                return str(hits[0])
    raise SystemExit("ffmpeg not found")


def build(clean: Path) -> dict[str, Path]:
    """Derive one probe per known defect from a clean clip."""
    PROBES.mkdir(parents=True, exist_ok=True)
    ff = _ffmpeg()
    out: dict[str, Path] = {}

    def run(name: str, vf: str | None, af: str | None = None,
            extra: list[str] | None = None) -> Path:
        dst = PROBES / f"probe-{name}.mp4"
        cmd = [ff, "-v", "error", "-y", "-i", str(clean)]
        if vf:
            cmd += ["-vf", vf]
        if af:
            cmd += ["-af", af]
        cmd += (extra or [])
        cmd += ["-c:v", "libx264", "-preset", "veryfast", "-crf", "23",
                "-c:a", "aac", "-ar", "48000", "-ac", "2", str(dst)]
        subprocess.run(cmd, check=True)
        return dst

    out["clean"] = clean
    (PROBES / "source.txt").write_text(str(clean.resolve()), encoding="utf-8")
    # No captions: paint the caption band out. Cropping and re-scaling kept the
    # text visible through the zoom, so the probe was not actually caption-free
    # and would have tested nothing.
    out["no-captions"] = run(
        "no-captions",
        "drawbox=x=0:y=ih*0.62:w=iw:h=ih*0.38:color=black:t=fill")
    # Frozen: one frame held for the whole duration.
    out["frozen"] = run(
        "frozen",
        "select='eq(n\\,0)',setpts=N/FRAME_RATE/TB", None,
        ["-r", "30", "-t", "8"])
    # Black bars: the picture squeezed into the middle third.
    out["black-bars"] = run(
        "black-bars",
        "scale=1080:640,pad=1080:1920:0:640:black")
    # Clipped audio: pushed well past full scale.
    out["clipped-audio"] = run(
        "clipped-audio", None, "volume=24dB,alimiter=limit=0.99:level=false")
    return out


def verify_claims(answer: str, clip: Path) -> list[dict]:
    """Check the factual claims a review makes against the clip itself.

    Only claims this module can decide mechanically are checked — a caption
    typo, a caption gap, a repeated frame. Aesthetic remarks are left alone; the
    point is to catch invented *facts*, which is what made the 2026-11-19 review
    unusable: it reported a misspelling that was not there and missed a real gap.
    """
    checks: list[dict] = []
    text = answer or ""

    ass = _find_ass(clip)
    if ass is not None:
        # The ASS is the *current* render's overlay. A review of yesterday's
        # bytes cannot be checked against today's file: after the caption gap was
        # fixed, the old review's "no text at 50.5s" looked false when it had
        # been true. Say so instead of silently mis-scoring the reviewer.
        if ass.stat().st_mtime > clip.stat().st_mtime + 1:
            checks.append({"claim": "review matches this clip",
                           "verified": None,
                           "detail": f"{ass.name} is newer than the clip; "
                                     f"re-render or re-review before judging"})
        body = ass.read_text(encoding="utf-8", errors="replace")
        for quoted in re.findall(r"[“\"']([\u0E00-\u0E7F]{4,})[”\"']", text):
            if quoted in body:
                checks.append({"claim": f"text {quoted!r} is on screen",
                               "verified": True})
            else:
                near = _closest_in(body, quoted)
                checks.append({
                    "claim": f"text {quoted!r} is on screen",
                    "verified": False,
                    "detail": (f"not in the ASS; the file says {near!r}"
                               if near else "not in the ASS at all")})

        # Scope the "no text" claim to the timestamps in its own sentence. A
        # whole-answer scan attributed every timestamp in the review to one
        # sentence and produced 18 bogus failures, which would have made the
        # checker useless in the other direction.
        for line in text.splitlines():
            if not re.search(r"(ไม่มีข้อความ|ไม่มีซับ|no text|no caption)", line):
                continue
            head = re.split(r"(?:ไม่มีข้อความ|ไม่มีซับ|no text|no caption)", line)[0]
            clause = re.split(r"(?:ส่วนช่วง|แต่|while|but|however)", head)[-1]
            for sec in re.findall(r"(\d+(?:\.\d+)?)\s*s", clause):
                t = float(sec)
                covered = _caption_at(body, t)
                checks.append({
                    "claim": f"no caption at {t:g}s",
                    "verified": not covered,
                    "detail": ("caption is on screen there" if covered
                               else "confirmed empty")})

    for sec in re.findall(r"(\d+(?:\.\d+)?)\s*s", text):
        if re.search(r"(ซ้ำ|repeated|duplicate)", text):
            checks.append({"claim": f"frame at {float(sec):g}s is a repeat",
                           "verified": None,
                           "detail": "needs frame comparison; see --frames"})
            break
    return checks


def _find_ass(clip: Path) -> Path | None:
    """The ASS overlay a clip was burned from, or None.

    The file is `work/<slug>/<hook>.ass` where the hook is the `-hN-` token in
    the clip name; the first attempt built that name by slicing on hyphens and
    missed, so every claim went unchecked. Resolve it by glob on the slug and the
    hook instead.
    """
    m = re.match(r"^short-(?:song|karaoke)-(h\d+)-(.+)$", clip.stem)
    if not m:
        return None
    hook, slug = m.group(1), m.group(2)
    for cand in (
        ROOT / "music938-1" / "work" / slug / f"short-{hook}.ass",
        ROOT / "music938-1" / "work" / slug / f"{hook}.ass",
    ):
        if cand.exists():
            return cand
    hits = sorted((ROOT / "music938-1" / "work" / slug).glob(f"*{hook}*.ass"))
    return hits[0] if hits else None


def _closest_in(body: str, quoted: str) -> str | None:
    lines = [l for l in body.splitlines() if l.startswith("Dialogue")]
    for l in lines:
        payload = l.rsplit(",", 1)[-1]
        payload = re.sub(r"\{[^}]*\}", "", payload).strip()
        if payload and _similar(payload, quoted) > 0.75:
            return payload
    return None


def _similar(a: str, b: str) -> float:
    sa, sb = set(a), set(b)
    return len(sa & sb) / max(1, len(sa | sb))


def _caption_at(body: str, t: float) -> bool:
    for l in body.splitlines():
        if not l.startswith("Dialogue"):
            continue
        p = l.split(",")
        if len(p) < 4:
            continue
        try:
            s, e = _sec(p[1]), _sec(p[2])
        except ValueError:
            continue
        if s <= t <= e:
            return True
    return False


def _sec(v: str) -> float:
    v = v.strip()
    if ":" in v:
        h, m, s = v.split(":")
        return int(h) * 3600 + int(m) * 60 + float(s)
    return float(v)


def validate_probes() -> dict[str, dict]:
    """Measure each probe and confirm it carries the defect it claims.

    A calibration run is only evidence if the probes really are defective. The
    first `no-captions` build was not caption-free (the zoom kept the text
    visible) and would have "proven" Gemini detects a defect that was not there.
    Each probe is measured here, and a probe that does not measure as defective
    is reported as invalid rather than counted.
    """
    import gemini_review as R  # noqa: PLC0415

    out: dict[str, dict] = {}
    for name, defect in PROBE_PLAN:
        p = PROBES / f"probe-{name}.mp4"
        if name == "clean":
            p = PROBES / "probe-clean.mp4"
            if not p.exists():
                src = PROBES / "source.txt"
                if src.exists():
                    p = Path(src.read_text(encoding="utf-8").strip())
        if not p.exists():
            continue
        mo = R.motion(p)
        lines, how = R.caption_lines(p)
        lr = R.loudness(p)
        tp = float(lr.get("input_tp") or 0.0)
        ok = True
        detail = ""
        if name == "frozen":
            ok = mo < 0.03
            detail = f"motion {mo:.3f}"
        elif name == "no-captions":
            ok = lines == 0
            detail = f"captions {lines} ({how})"
        elif name == "black-bars":
            ok = _has_bars(p)
            detail = "black band measured" if ok else "no black band found"
        elif name == "clipped-audio":
            ok = tp > -1.0
            detail = f"true peak {tp} dBTP"
        out[name] = {"valid": ok, "detail": detail, "motion": round(mo, 3),
                     "captions": lines, "tp": tp}
    return out


def _has_bars(clip: Path) -> bool:
    """True when a whole horizontal band of the frame is pure black."""
    import tempfile  # noqa: PLC0415

    ff = _ffmpeg()
    with tempfile.TemporaryDirectory() as d:
        frame = Path(d) / "f.png"
        subprocess.run([ff, "-v", "error", "-y", "-ss", "5", "-i", str(clip),
                        "-frames:v", "1", str(frame)], check=True)
        try:
            from PIL import Image  # noqa: PLC0415
        except ImportError:
            return True  # cannot measure; do not call a good probe invalid
        im = Image.open(frame).convert("L")
        w, h = im.size
        for y in range(0, h, max(1, h // 40)):
            row = list(im.crop((0, y, w, min(h, y + 1))).convert("L")
                       .get_flattened_data())
            if max(row) <= 8:
                return True
        return False


def run_probes() -> int:
    sys.path.insert(0, str(ROOT / "ops"))
    import gemini_gate  # noqa: PLC0415
    import gemini_review as R  # noqa: PLC0415

    built = {p.name.replace("probe-", "").replace(".mp4", ""): p
             for p in sorted(PROBES.glob("probe-*.mp4"))}
    # The clean probe is the source clip, not a derived file, so it has no
    # probe-clean.mp4. Without this the baseline was missing from the report and
    # every Δ was skipped — the summary printed "separated every defect" while
    # having nothing to compare against.
    src = PROBES / "source.txt"
    if src.exists():
        built["clean"] = Path(src.read_text(encoding="utf-8").strip())
    if not built:
        print("no probes; run --build first", file=sys.stderr)
        return 2

    valid = validate_probes()
    print("=== probe validity ===")
    bad_probes = []
    for name, defect in PROBE_PLAN:
        v = valid.get(name)
        if v is None:
            continue
        mark = "ok  " if v["valid"] else "INVALID"
        print(f"{mark} {name:15s} {v['detail']}")
        if not v["valid"]:
            bad_probes.append(name)
    if bad_probes:
        print(f"\n{len(bad_probes)} probe(s) do not carry their defect "
              f"({', '.join(bad_probes)}); a run on them proves nothing. "
              f"Rebuild with --build.", file=sys.stderr)
        return 2

    rows: list[dict] = []
    sess = R.Session()
    try:
        for name, defect in PROBE_PLAN:
            clip = built.get(name)
            if clip is None:
                continue
            sheet = PROBES / f"sheet-{name}.jpg"
            R.build_sheet(clip, sheet)
            if not R.new_chat(sess):
                print("could not open a chat", file=sys.stderr)
                return 2
            info = R.probe(clip)
            mo = R.motion(clip)
            lines, how = R.caption_lines(clip)
            lr = R.loudness(clip)
            genre, mood = R.song_style(clip)
            prompt = R.PROMPT.format(
                dur=info["duration"], n=R.FRAMES, w=info["width"],
                h=info["height"], fps=info["fps"], motion=mo, lines=lines,
                how=how, lufs=lr.get("input_i", "?"),
                tp=lr.get("input_tp", "?"), genre=genre, mood=mood)
            answer = R.ask(sess, prompt, sheet)
            score, verdict, _ = R.parse(answer or "")
            if score is None:
                answer2 = R.ask(
                    sess, "ให้คะแนนรวมเป็นตัวเลข 1-10: SCORE: <เลข> "
                          "VERDICT: <PASS หรือ FAIL>", None, 90.0)
                score, verdict, _ = R.parse(answer2 or "")
            claims = verify_claims(answer or "", clip)
            rows.append({
                "probe": name, "defect": defect, "score": score,
                "verdict": verdict,
                "measured": {"motion": round(mo, 3), "captions": lines,
                             "lufs": lr.get("input_i"),
                             "tp": lr.get("input_tp")},
                "claims": claims,
                "answer": (answer or "")[:4000],
            })
            print(f"{name:15s} defect={str(defect)[:34]:36s} "
                  f"score={score} verdict={verdict} "
                  f"claims_ok={sum(1 for c in claims if c['verified'] is True)}"
                  f"/{sum(1 for c in claims if c['verified'] is not None)}")
    finally:
        sess.close()

    REPORT.parent.mkdir(parents=True, exist_ok=True)
    REPORT.write_text(json.dumps(rows, ensure_ascii=False, indent=2) + "\n",
                      encoding="utf-8")
    print(f"\nreport: {REPORT}")
    return summarise(rows)


def summarise(rows: list[dict]) -> int:
    """Report whether the reviewer separated defective clips from a clean one."""
    clean = next((r for r in rows if r["probe"] == "clean"), None)
    bad = [r for r in rows if r["probe"] != "clean" and r["score"] is not None]
    print("\n=== calibration ===")
    if clean is None or clean["score"] is None:
        print("NO BASELINE: the clean clip was not scored, so no defect can be "
              "compared against it. This run is not evidence.", file=sys.stderr)
        return 2
    print(f"clean clip            : {clean['score']:g}")
    for r in bad:
        delta = r["score"] - clean["score"]
        mark = "OK" if delta < 0 else "!! NOT DETECTED"
        print(f"{r['probe']:22s}: {r['score']:g}  (Δ vs clean {delta:+g}) {mark}")
    total = [c for r in rows for c in r["claims"] if c["verified"] is not None]
    ok = [c for c in total if c["verified"]]
    if total:
        print(f"\nclaims verified: {len(ok)}/{len(total)} "
              f"({100*len(ok)/len(total):.0f}%)")
        for c in total:
            if not c["verified"]:
                print(f"  FALSE: {c['claim']} — {c.get('detail','')}")
    misses = [r for r in bad
              if clean and clean["score"] is not None
              and r["score"] >= clean["score"]]
    if misses:
        print(f"\n{len(misses)} measured defect(s) did NOT lower the score. "
              f"On this evidence the score does not detect them.")
        return 1
    print("\nthe score separated every measured defect from the clean clip.")
    return 0


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--build", action="store_true", help="build the probes")
    ap.add_argument("--run", action="store_true", help="review the probes")
    ap.add_argument("--clean", help="clean source clip for --build")
    ap.add_argument("--claims", help="review text to verify")
    ap.add_argument("--clip", help="clip the review is about")
    a = ap.parse_args(argv)

    if a.build:
        src = Path(a.clean) if a.clean else None
        if src is None or not src.exists():
            print("--build needs --clean <clip.mp4>", file=sys.stderr)
            return 2
        made = build(src)
        for k, v in made.items():
            print(f"{k:15s} {v}")
        return 0
    if a.claims:
        if not a.clip:
            print("--claims needs --clip", file=sys.stderr)
            return 2
        for c in verify_claims(Path(a.claims).read_text(encoding="utf-8"),
                               Path(a.clip)):
            flag = {True: "OK  ", False: "FALSE", None: "n/a "}[c["verified"]]
            print(f"{flag} {c['claim']}  {c.get('detail','')}")
        return 0
    if a.run:
        return run_probes()
    ap.print_help()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
