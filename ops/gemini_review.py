#!/usr/bin/env python3
"""Get a real Gemini verdict on a rendered clip, and record it for the gate.

K (2026-11-19): "ถ้าไม่ผ่านการตรวจสอบผ่านจาก gemini ห้ามเอาอัพขึ้นช่องและห้ามส่ง
ให้ K ดู ทำให้ผ่านก่อน". So a clip needs a *pass* before it can go anywhere, and
the only reviewer whose verdict counts is Gemini.

Gemini's web app cannot open a video file — it answers "ไม่สามารถเปิดไฟล์วิดีโอ"
even when signed in (measured 2026-11-18). What it can read is an image. So this
renders a labelled contact sheet of the clip (N evenly spaced frames with their
timestamps) plus the measured facts ffmpeg can prove, asks Gemini to score the
clip 1-10 against the channel standard, and records the verdict through
`gemini_gate.record()` — hash-bound to the exact file that was sampled.

    python3 ops/gemini_review.py CLIP.mp4            # review + record
    python3 ops/gemini_review.py CLIP.mp4 --dry-run  # sheet + prompt only

The measured facts are handed over with the pictures on purpose. A still cannot
show whether the picture moves; ffmpeg can measure that. Asking Gemini to judge
motion from a contact sheet would be asking it to guess, and a guess is not a
review.

Exit codes: 0 = passed and recorded, 1 = failed and recorded (the clip must be
fixed), 2 = the review itself could not happen (no desktop, no tab, no answer).
"""
from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import tempfile
import time
import urllib.request
from pathlib import Path

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import gemini_gate  # noqa: E402

ROOT = Path(__file__).resolve().parent.parent
CDP = "http://127.0.0.1:9222"
FRAMES = 8          # frames on the sheet: enough to show captions changing
SHEET_COLS = 2
SHEET_WIDTH = 540   # per-cell width; 2 columns = a 1080-wide sheet


# --- the sheet ---------------------------------------------------------------

def _run(cmd: list[str], **kw) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, **kw)


def probe(path: str | Path) -> dict:
    r = _run(["ffprobe", "-v", "error", "-print_format", "json",
              "-show_format", "-show_streams", str(path)])
    if r.returncode != 0:
        raise SystemExit(f"ffprobe failed on {path}: {r.stderr[:300]}")
    d = json.loads(r.stdout)
    v = next(s for s in d["streams"] if s["codec_type"] == "video")
    a = next((s for s in d["streams"] if s["codec_type"] == "audio"), None)
    num, den = (v.get("r_frame_rate") or "0/1").split("/")
    return {
        "duration": float(d["format"]["duration"]),
        "width": int(v["width"]), "height": int(v["height"]),
        "fps": round(float(num) / float(den or 1), 2),
        "vcodec": v.get("codec_name"), "acodec": (a or {}).get("codec_name"),
        "sample_rate": (a or {}).get("sample_rate"),
        "channels": (a or {}).get("channels"),
        "has_audio": a is not None,
    }


def motion(path: str | Path) -> float:
    """Mean absolute frame-to-frame difference. 0 = a frozen picture."""
    r = _run(["ffmpeg", "-hide_banner", "-i", str(path), "-vf",
              "scale=160:-2,tblend=all_mode=difference,"
              "signalstats,metadata=print:key=lavfi.signalstats.YAVG:file=-",
              "-f", "null", "-"])
    vals = [float(m) for m in re.findall(r"YAVG=([0-9.]+)", r.stdout + r.stderr)]
    return round(sum(vals) / len(vals), 3) if vals else 0.0


def loudness(path: str | Path) -> dict:
    r = _run(["ffmpeg", "-hide_banner", "-i", str(path), "-af",
              "loudnorm=print_format=json", "-f", "null", "-"])
    txt = r.stderr
    i = txt.rfind("{")
    if i < 0:
        return {}
    try:
        d = json.loads(txt[i:txt.rfind("}") + 1])
    except ValueError:
        return {}
    return {k: d.get(k) for k in ("input_i", "input_tp", "input_lra")}


def caption_lines(path: str | Path) -> tuple[int, str]:
    """(lines, how). Captions are burned into the picture by the ASS filter, so
    there is usually no subtitle *stream* to count — reporting 0 would tell
    Gemini the clip has no lyrics when it plainly does. The ASS that was burned
    is kept beside the song in `work/<slug>/short-song-h<N>.ass`, so look there
    first; fall back to a stream count for clips that carry a real track."""
    stem = Path(path).stem
    # The clip is `short-song-<hook>-<slug>.mp4`, so the song dir is the slug.
    # A loose glob would happily report another song's caption count — which
    # would tell Gemini a caption-less clip has lyrics, the worst kind of wrong.
    m = re.match(r"short-song-(h\d+)-(.+)$", stem)
    candidates = [Path(path).with_suffix(".ass")]
    if m:
        hook, slug = m.group(1), m.group(2)
        candidates.insert(0, ROOT / "music938-1" / "work" / slug / f"short-song-{hook}.ass")
    for side in candidates:
        if not side.exists():
            continue
        n = sum(1 for line in side.read_text(encoding="utf-8",
                                             errors="replace").splitlines()
                if line.strip().startswith("Dialogue:"))
        if n:
            return n, "burned"
    r = _run(["ffprobe", "-v", "error", "-select_streams", "s",
              "-show_entries", "stream=index", "-of", "csv=p=0", str(path)])
    if r.returncode != 0 or not r.stdout.strip():
        return 0, "none"
    total = 0
    for line in r.stdout.split():
        idx = line.strip().rstrip(",")
        if not idx:
            continue
        p = _run(["ffmpeg", "-hide_banner", "-i", str(path), "-map", f"0:{idx}",
                  "-f", "srt", "-"])
        total += len([b for b in (p.stdout or "").split("\n\n") if "-->" in b])
    return total, ("stream" if total else "none")


def build_sheet(clip: str | Path, out: Path) -> Path:
    info = probe(clip)
    dur = info["duration"]
    # Sample from 1.5 s in to just before the end: the first frame is a title
    # card and the last is the follow ask, so neither shows the actual content.
    step = (dur - 2.0) / FRAMES
    tmp = Path(tempfile.mkdtemp(prefix="ax-sheet-"))
    files = []
    for i in range(FRAMES):
        t = 1.5 + i * step
        f = tmp / f"f{i:02d}.png"
        _run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss", f"{t:.2f}",
              "-i", str(clip), "-frames:v", "1", "-vf",
              f"scale={SHEET_WIDTH}:-2,drawtext=text='{t:.1f}s':x=8:y=8:"
              f"fontsize=26:fontcolor=white:box=1:boxcolor=black@0.6",
              str(f)])
        if f.exists():
            files.append(f)
    if not files:
        raise SystemExit("could not extract any frame from the clip")
    rows = (len(files) + SHEET_COLS - 1) // SHEET_COLS
    lst = tmp / "list.txt"
    lst.write_text("".join(f"file '{f}'\n" for f in files), encoding="utf-8")
    # Pad the last row so the tile grid is rectangular, or xstack refuses.
    while len(files) < rows * SHEET_COLS:
        blank = tmp / f"blank{len(files)}.png"
        _run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "lavfi",
              "-i", f"color=c=black:s={SHEET_WIDTH}x960:d=1", "-frames:v", "1",
              str(blank)])
        files.append(blank)
        lst.write_text("".join(f"file '{f}'\n" for f in files), encoding="utf-8")
    out.parent.mkdir(parents=True, exist_ok=True)
    r = _run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-f", "concat",
              "-safe", "0", "-i", str(lst), "-filter_complex",
              f"tile={SHEET_COLS}x{rows}:padding=4:color=black", "-frames:v", "1",
              str(out)])
    if not out.exists():
        raise SystemExit(f"contact sheet failed: {r.stderr[:300]}")
    return out


# --- the CDP driver ----------------------------------------------------------

def _ws_url() -> str:
    with urllib.request.urlopen(f"{CDP}/json", timeout=10) as f:
        tabs = json.load(f)
    for t in tabs:
        if "gemini.google.com" in (t.get("url") or ""):
            return t["webSocketDebuggerUrl"]
    raise SystemExit("no gemini.google.com tab on the desktop — open one first")


class Session:
    """Minimal CDP client. Playwright's connect_over_cdp hangs on this sandbox,
    so the raw websocket is the route that works (learned 2026-11-18)."""

    def __init__(self) -> None:
        import websocket
        self.ws = websocket.create_connection(_ws_url(), timeout=180)
        self.n = 0

    def send(self, method: str, **params) -> dict:
        self.n += 1
        self.ws.send(json.dumps({"id": self.n, "method": method, "params": params}))
        while True:
            msg = json.loads(self.ws.recv())
            if msg.get("id") == self.n:
                if "error" in msg:
                    raise RuntimeError(f"{method}: {msg['error']}")
                return msg.get("result", {})

    def eval(self, expr: str):
        r = self.send("Runtime.evaluate", expression=expr, returnByValue=True,
                      awaitPromise=True)
        return r.get("result", {}).get("value")

    def close(self) -> None:
        try:
            self.ws.close()
        except Exception:
            pass


SET_PROMPT = """(() => {
  const c = document.querySelector('.ql-editor');
  if (!c) return 'no-composer';
  c.focus();
  const sel = window.getSelection(); sel.removeAllRanges();
  const r = document.createRange(); r.selectNodeContents(c); sel.addRange(r);
  document.execCommand('delete', false, null);
  document.execCommand('insertText', false, %s);
  return c.innerText.length;
})()"""

READ_ANSWER = """(() => {
  const msgs = document.querySelectorAll('message-content, .model-response-text');
  if (!msgs.length) return '';
  return msgs[msgs.length - 1].innerText || '';
})()"""


def attach_image(sess: Session, path: Path) -> bool:
    """Hand the sheet to the composer's file input.

    Gemini keeps no `input[type=file]` in the DOM until the "Upload & tools"
    menu is opened — clicking it mounts four of them, and the third accepts
    `image/*,video/*`. The element is addressed by objectId rather than nodeId:
    the menu re-renders on open, so a nodeId taken from `DOM.getDocument` goes
    stale between the click and the set, and the attach silently did nothing.
    """
    sess.eval("""(() => {
      const bs = [...document.querySelectorAll('button')];
      const b = bs.find(x => ((x.getAttribute('aria-label') || '') +
                              (x.textContent || '')).includes('Upload'));
      if (b) b.click();
      return !!b;
    })()""")
    time.sleep(4)
    r = sess.send("Runtime.evaluate", returnByValue=False, expression="""(() => {
      const ins = [...document.querySelectorAll('input[type=file]')];
      return ins.find(i => (i.accept || '').includes('image')) || null;
    })()""")
    obj = (r.get("result") or {}).get("objectId")
    if not obj:
        return False
    sess.send("DOM.setFileInputFiles", files=[str(path)], objectId=obj)
    return True


COUNT_MSGS = """(() => document.querySelectorAll('message-content, .model-response-text').length)()"""

# The desktop's Gemini is in Thai, so the send button is "ส่งข้อความ", not "Send".
SEND = """(() => {
  const cand = [...document.querySelectorAll('button')].filter(b => !b.disabled);
  const b = cand.find(x => {
    const a = (x.getAttribute('aria-label') || '') + ' ' + (x.textContent || '');
    return /send|ส่งข้อความ|ส่ง/i.test(a) && !/cancel|ยกเลิก/i.test(a);
  });
  if (b) { b.click(); return 'clicked:' + (b.getAttribute('aria-label') || ''); }
  const c = document.querySelector('.ql-editor');
  if (c) {
    c.dispatchEvent(new KeyboardEvent('keydown',
      {key: 'Enter', code: 'Enter', keyCode: 13, which: 13, bubbles: true}));
    return 'enter';
  }
  return 'no-send';
})()"""


def new_chat(sess: Session) -> bool:
    """Start a fresh chat, so the answer reader cannot pick up a previous reply.

    Reading the *last* message of an old conversation returned "2+2 = 4" from an
    earlier test and the parser then found no SCORE — the review looked broken
    when the real problem was a stale page.
    """
    sess.send("Page.navigate", url="https://gemini.google.com/app")
    for _ in range(20):
        time.sleep(2)
        if sess.eval("!!document.querySelector('.ql-editor')"):
            time.sleep(2)
            return True
    return False


def ask(sess: Session, prompt: str, sheet: Path | None, wait: float = 240.0) -> str:
    before = sess.eval(COUNT_MSGS) or 0
    if sheet is not None:
        if not attach_image(sess, sheet):
            raise SystemExit("could not find Gemini's file input to attach the sheet")
        # The upload is asynchronous: the chip appears when it lands, and sending
        # before that posts the text alone.
        for _ in range(40):
            time.sleep(2)
            if sess.eval("""(() => !!document.querySelector(
                    'img[src^="blob:"], .attachment-preview, [data-test-id*="attachment"]'))()"""):
                break
        time.sleep(2)
    sess.eval(SET_PROMPT % json.dumps(prompt, ensure_ascii=False))
    time.sleep(1.5)
    sent = sess.eval(SEND)
    if not str(sent).startswith(("clicked", "enter")):
        print(f"could not send the prompt: {sent}", file=sys.stderr)
    deadline = time.time() + wait
    last = ""
    stable = 0
    while time.time() < deadline:
        time.sleep(5)
        n = sess.eval(COUNT_MSGS) or 0
        now = sess.eval(READ_ANSWER) or ""
        # A reply only counts once it is a *new* message and has stopped growing.
        if n > before and now and now == last and len(now) > 40:
            stable += 1
            if stable >= 2:
                return now
        else:
            stable = 0
        last = now
    return last


# --- the review --------------------------------------------------------------

PROMPT = """คุณเป็นผู้ตรวจคุณภาพคลิปของช่อง "เพลงส้นทีนไรเนี่ย" (เพลงไทยแนวการาจพังค์)

ผมแนบ contact sheet ของคลิป Short 9:16 ยาว {dur:.1f} วินาที (เฟรมตัวอย่าง {n} เฟรม
พร้อมเวลา) และค่าที่วัดได้จริงจากไฟล์:
- ขนาด {w}x{h} ที่ {fps} fps
- ค่า motion (ผลต่างเฟรมเฉลี่ย) = {motion} (ค่าต่ำกว่า 0.03 = ภาพนิ่งสนิท)
- จำนวนบรรทัดซับไตเติล = {lines} (วิธี: {how})
- loudness = {lufs} LUFS, true peak = {tp} dBTP

เกณฑ์ของช่อง (ต้องได้ทุกข้อ):
1. มีเนื้อเพลง/ซับไตเติลบนจอ และอ่านออก
2. ภาพไม่นิ่งสนิท มีการเคลื่อนไหว/ซูม/แพน
3. ใช้พื้นที่แนวตั้งเต็ม ไม่มีแถบดำหรือขอบเบลอเสียเปล่า
4. ตัวอักษรไทยอ่านชัด ไม่ถูกตัดขอบ
5. ดูพรีเมียม พร้อมลงช่องจริง

ตอบตามรูปแบบนี้เท่านั้น ห้ามมีอย่างอื่นก่อน SCORE:
SCORE: <ตัวเลข 1-10>
VERDICT: <PASS หรือ FAIL>
REASON1: <เหตุผลสั้น>
REASON2: <เหตุผลสั้น>
REASON3: <เหตุผลสั้น>"""


def parse(answer: str) -> tuple[float | None, str, list[str]]:
    score = None
    m = re.search(r"SCORE\s*[:：]\s*([0-9]+(?:\.[0-9]+)?)", answer)
    if m:
        score = float(m.group(1))
    v = ""
    m = re.search(r"VERDICT\s*[:：]\s*(PASS|FAIL)", answer, re.I)
    if m:
        v = m.group(1).upper()
    reasons = [x.strip() for x in
               re.findall(r"REASON\d\s*[:：]\s*(.+)", answer)]
    return score, v, reasons


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(description="Gemini review of a rendered clip")
    ap.add_argument("clip")
    ap.add_argument("--dry-run", action="store_true",
                    help="build the sheet and print the prompt, ask nothing")
    ap.add_argument("--sheet", help="keep the sheet at this path")
    ap.add_argument("--replace", action="store_true",
                    help="overwrite an existing verdict")
    ap.add_argument("--wait", type=float, default=180.0)
    a = ap.parse_args(argv)

    clip = Path(a.clip)
    if not clip.exists():
        raise SystemExit(f"no such clip: {clip}")

    info = probe(clip)
    mo = motion(clip)
    lines, how = caption_lines(clip)
    lr = loudness(clip)
    lufs = lr.get("input_i", "?")
    tp = lr.get("input_tp", "?")

    sheet = Path(a.sheet) if a.sheet else (
        Path(tempfile.mkdtemp(prefix="ax-review-")) / f"{clip.stem}.jpg")
    build_sheet(clip, sheet)
    print(f"sheet: {sheet}  ({sheet.stat().st_size/1024:.0f} KB)")
    print(f"measured: {info['width']}x{info['height']}@{info['fps']}  "
          f"motion {mo}  captions {lines} ({how})  {lufs} LUFS  {tp} dBTP")

    prompt = PROMPT.format(dur=info["duration"], n=FRAMES, w=info["width"],
                           h=info["height"], fps=info["fps"], motion=mo,
                           lines=lines, how=how, lufs=lufs, tp=tp)
    if a.dry_run:
        print("\n--- prompt ---\n" + prompt)
        return 0

    sess = Session()
    try:
        if not new_chat(sess):
            print("could not open a fresh Gemini chat", file=sys.stderr)
            return 2
        answer = ask(sess, prompt, sheet, a.wait)
    finally:
        sess.close()
    if not answer:
        print("Gemini returned nothing", file=sys.stderr)
        return 2
    print("\n--- Gemini ---\n" + answer.strip()[:2000])

    score, verdict, reasons = parse(answer)
    if score is None:
        print("could not parse a SCORE out of the answer", file=sys.stderr)
        return 2
    passed = verdict == "PASS" and score >= gemini_gate.PASS_SCORE
    p = gemini_gate.record(
        clip, score, passed, verdict=verdict or ("PASS" if passed else "FAIL"),
        note=" | ".join(reasons)[:500], sheet=str(sheet), replace=a.replace)
    print(f"\nrecorded {p}")
    print(f"SCORE {score:g}  VERDICT {verdict or '-'}  -> "
          f"{'PASS (may publish)' if passed else 'FAIL (must be fixed)'}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
