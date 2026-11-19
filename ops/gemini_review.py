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


def _gray(path: Path) -> "np.ndarray":
    """A small grayscale copy of a frame, for comparing frames."""
    import numpy as np  # noqa: PLC0415
    from PIL import Image  # noqa: PLC0415

    with Image.open(path) as im:
        return np.asarray(im.convert("L").resize((64, 114)), dtype=np.float32)


SHOT_JUMP = 40.0   # mean-abs-difference between frames of different shots


def _shot_ids(files: list[Path]) -> list[int]:
    """Group sampled frames into shots: consecutive frames that look the same.

    A still that holds for five seconds is ONE shot, so two samples inside it are
    not a repeated shot — but a contact sheet cannot show that, and Gemini read
    the pair as a duplicate and marked the clip down. Grouping gives each cell a
    shot number, and the prompt says a shared number is one continuous shot.

    A per-pixel difference beats a hash here: the render keeps zooming inside a
    still, and that tiny drift moves every hash bit at once, so a hash split one
    shot into four. Measured on a real clip, two samples of one still differ by
    ~22 and two different stills by ~68, so the cut is unambiguous.
    """
    import numpy as np  # noqa: PLC0415

    ids, cur, prev = [], 0, None
    for f in files:
        g = _gray(f)
        if prev is not None and float(np.abs(g - prev).mean()) > SHOT_JUMP:
            cur += 1
        ids.append(cur)
        prev = g
    return ids


def build_sheet(clip: str | Path, out: Path) -> Path:
    info = probe(clip)
    dur = info["duration"]
    # Sample from 1.5 s in to just before the end: the first frame is a title
    # card and the last is the follow ask, so neither shows the actual content.
    step = (dur - 2.0) / FRAMES
    tmp = Path(tempfile.mkdtemp(prefix="ax-sheet-"))
    files = []
    labels = []
    for i in range(FRAMES):
        t = 1.5 + i * step
        f = tmp / f"f{i:02d}.png"
        for seek in (t, 0.0):
            # A clip that is genuinely frozen carries a single frame, so seeking
            # to 1.5 s yields nothing at all — the one defect this sheet exists
            # to expose was the one it could not render, and the review aborted
            # with "could not extract any frame". Fall back to the first frame.
            _run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-ss",
                  f"{seek:.2f}", "-i", str(clip), "-frames:v", "1", "-vf",
                  f"scale={SHEET_WIDTH}:-2",
                  str(f)])
            if f.exists():
                break
        if f.exists():
            files.append(f)
            labels.append(t)
    if not files:
        raise SystemExit("could not extract any frame from the clip")
    shots = _shot_ids(files)
    rows = (len(files) + SHEET_COLS - 1) // SHEET_COLS
    # Add a caption BAR under each frame. Two samples of one held still are not
    # a repeated shot, but a contact sheet cannot say that: on 2026-11-19 Gemini
    # failed a correct clip for "ช็อตซ้ำ" at 15.5s and 19.0s when both were the
    # same 5-second still. The label goes on a black bar, never on the picture,
    # because text drawn over the pixels made Gemini warn about burned-in timecode
    # and about legibility -- two findings that were about the sheet, not the clip.
    for f, sid, t in zip(files, shots, labels):
        tagged = tmp / f"tag-{f.name}"
        _run(["ffmpeg", "-hide_banner", "-loglevel", "error", "-i", str(f),
              "-vf", (f"pad=iw:ih+46:0:0:black,"
                      f"drawtext=text='SHOT {sid}   {t:.1f}s':x=8:y=h-38:"
                      f"fontsize=26:fontcolor=white"),
              "-frames:v", "1", str(tagged)])
        if tagged.exists():
            files[files.index(f)] = tagged
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
    """A CDP target for the review, in a tab this script owns.

    It used to grab the first gemini.google.com tab and navigate it to a fresh
    chat. On 2026-11-19 that tab was K's own conversation: the review destroyed
    K's work, and because the tab was mid-stream the websocket dropped with
    "Connection to remote host was lost" and the review returned nothing. A
    review must never touch a tab it did not open.
    """
    with urllib.request.urlopen(f"{CDP}/json", timeout=10) as f:
        tabs = json.load(f)
    mine = [t for t in tabs if t.get("type") == "page"
            and "gemini.google.com" in (t.get("url") or "")
            and os.environ.get("AX_QC_TAB_ID") == t.get("id")]
    if mine:
        return mine[0]["webSocketDebuggerUrl"]

    req = urllib.request.Request(
        f"{CDP}/json/new?https://gemini.google.com/app", method="PUT")
    with urllib.request.urlopen(req, timeout=20) as f:
        tab = json.load(f)
    os.environ["AX_QC_TAB_ID"] = tab["id"]
    return tab["webSocketDebuggerUrl"]


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

PROMPT = """คุณเป็นผู้ตรวจคุณภาพคลิปของช่อง "เพลงส้นทีนไรเนี่ย"
เพลงนี้เป็นแนว **{genre}** อารมณ์ **{mood}** — ให้ตัดสินภาพให้เข้ากับแนวนี้นะ
อย่าตัดสินว่าต้องดิบแบบการาจพังค์ ถ้าเพลงนี้ไม่ใช่พังค์

ผมแนบ contact sheet ของคลิป Short 9:16 ยาว {dur:.1f} วินาที (เฟรมตัวอย่าง {n} เฟรม
พร้อมเวลา) และค่าที่วัดได้จริงจากไฟล์:
- ขนาด {w}x{h} ที่ {fps} fps
- ค่า motion (ผลต่างเฟรมเฉลี่ย) = {motion} (ค่าต่ำกว่า 0.03 = ภาพนิ่งสนิท)
- ในแต่ละช่องมีป้าย "SHOT n" กำกับ ช่องที่เลข SHOT **ซ้ำกันคือภาพเดียวกันที่ยังฉายอยู่**
  (ไม่ใช่ช็อตซ้ำ) — ช็อตซ้ำคือคนละเลข SHOT แต่ภาพเหมือนกัน
- จำนวนบรรทัดซับไตเติล = {lines} (วิธี: {how})
- loudness = {lufs} LUFS, true peak = {tp} dBTP

เกณฑ์ของช่อง (ต้องได้ทุกข้อ — ตัดสินจากที่เห็นในภาพเท่านั้น):
1. มีเนื้อเพลง/ซับไตเติลบนจอ และอ่านออก
2. ภาพไม่นิ่งสนิท มีการเคลื่อนไหว/ซูม/แพน หรือเปลี่ยนภาพ
3. ใช้พื้นที่แนวตั้งเต็ม ไม่มีแถบดำหรือขอบเบลอเสียเปล่า
4. ตัวอักษรไทยอ่านชัด ไม่ถูกตัดขอบ
5. ภาพไม่ซ้ำซากจนน่าเบื่อ (ดูจากเลข SHOT ที่ต่างกัน) และเข้ากับอารมณ์เพลงแนว {genre}
6. ดูพรีเมียม พร้อมลงช่องจริง

ตอบตามรูปแบบนี้เท่านั้น ห้ามมีอย่างอื่นก่อน SCORE:
SCORE: <ตัวเลข 1-10>
VERDICT: <PASS หรือ FAIL>
REASON1: <เหตุผลสั้น>
REASON2: <เหตุผลสั้น>
REASON3: <เหตุผลสั้น>"""


def song_style(clip: Path) -> tuple[str, str]:
    """The song's real genre and mood, read from its lyric header.

    The review prompt used to hard-code "การาจพังค์" for every clip, so a lofi
    song was marked down every time for not being punk — a real clip was scored
    4/10 for not matching a genre it was never in. The lyric file carries the
    truth in its `# GENRE:` / `# MOOD:` headers; when it cannot be read, say so
    rather than guess a genre.
    """
    stem = clip.stem
    # Two naming schemes reach this: the posting queue's `short-song-hN-<slug>`
    # and the clip lane's `bank-<song>-<theme>`. Matching only the first left a
    # bank clip with genre/mood "ไม่ระบุ", and the review then judged the pictures
    # against no genre at all. The theme tail is not part of the song name.
    slug = re.sub(r"^short-(?:song|karaoke)-h\d+-", "", stem)
    slug = re.sub(r"-h\d+$", "", slug)
    lyrics = ROOT / "music938-1" / "lyrics"
    if not (lyrics / f"{slug}.txt").exists():
        # The clip lane names a clip `bank-<song>-<theme>`, and the song slug is
        # whatever part of that name matches a lyric file. Resolve it against the
        # files that exist rather than stripping fixed prefixes: a theme word is
        # free text, so a prefix list silently missed `bank-song-19-...`.
        found = ""
        for f in lyrics.glob("*.txt"):
            # The theme is appended after the song slug, so the lyric name sits
            # *inside* the clip name, not at its end.
            if f.stem in stem and len(f.stem) > len(found):
                found = f.stem
        if found:
            slug = found
    genre = mood = ""
    cand = lyrics / f"{slug}.txt"
    if cand.exists():
        for line in cand.read_text(encoding="utf-8").splitlines()[:12]:
            if line.startswith("# GENRE:"):
                genre = line.split(":", 1)[1].strip()
            elif line.startswith("# MOOD:"):
                mood = line.split(":", 1)[1].strip()
    return genre or "ไม่ระบุ", mood or "ไม่ระบุ"


def parse(answer: str) -> tuple[float | None, str, list[str]]:
    """Read a verdict out of Gemini's answer, formatted or not.

    Gemini often ignores the requested `SCORE:` block and answers in prose
    instead — a real review, just not the shape we asked for. Requiring the exact
    label made the gate impossible to pass: every clip recorded "could not parse
    a SCORE" and nothing could ever ship. So the labelled form is tried first,
    then a bare "7/10" or "ให้ 7 คะแนน", and the verdict is inferred from the
    prose when it is not stated. Fail-closed still holds: no score found at all
    means no verdict, which blocks the clip.
    """
    score = None
    for pat in (r"SCORE\s*[:：]\s*([0-9]+(?:\.[0-9]+)?)",
                r"\b([0-9]+(?:\.[0-9]+)?)\s*/\s*10\b",
                r"ให้\s*([0-9]+(?:\.[0-9]+)?)\s*คะแนน",
                r"([0-9]+(?:\.[0-9]+)?)\s*คะแนน"):
        m = re.search(pat, answer)
        if m:
            v = float(m.group(1))
            if 0 < v <= 10:
                score = v
                break
    verdict = ""
    m = re.search(r"VERDICT\s*[:：]\s*(PASS|FAIL)", answer, re.I)
    if m:
        verdict = m.group(1).upper()
    elif re.search(r"ยังไม่ผ่าน|ไม่ผ่าน(?:เกณฑ์)?|Needs\s+Revision|FAIL", answer, re.I):
        verdict = "FAIL"
    elif re.search(r"\bPASS\b|ผ่าน(?:เกณฑ์|ทุกข้อ)", answer, re.I):
        verdict = "PASS"
    reasons = [x.strip() for x in
               re.findall(r"REASON\d\s*[:：]\s*(.+)", answer)]
    if not reasons:
        # The prose form has no REASON labels; the first substantive lines are
        # the findings, and they are what a human reads to fix the clip.
        lines = [ln.strip(" -*•\t") for ln in answer.splitlines()]
        reasons = [ln for ln in lines
                   if len(ln) > 12 and not re.match(r"^(สรุป|สถานะ|จุด|ตาราง|ช่วงเวลา)",
                                                    ln)][:3]
    return score, verdict, reasons


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

    genre, mood = song_style(clip)
    prompt = PROMPT.format(dur=info["duration"], n=FRAMES, w=info["width"],
                           h=info["height"], fps=info["fps"], motion=mo,
                           lines=lines, how=how, lufs=lufs, tp=tp,
                           genre=genre, mood=mood)
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
        # A prose review is a real review, it just left the number out. Asking
        # for the number is not a re-review: the findings are already given, and
        # the clip is still judged by them. Without this the gate blocked every
        # clip Gemini chose to answer in paragraphs.
        follow = ("ให้คะแนนรวมคลิปนี้เป็นตัวเลข 1-10 ตามที่วิจารณ์ไปแล้ว "
                  "ตอบสั้น ๆ ว่า: SCORE: <เลข> VERDICT: <PASS หรือ FAIL>")
        try:
            sess = Session()
            try:
                second = ask(sess, follow, None, min(a.wait, 90.0))
            finally:
                sess.close()
            s2, v2, _ = parse(second or "")
            if s2 is not None:
                score, verdict = s2, (v2 or verdict)
                print(f"\n--- Gemini (score follow-up) ---\n{(second or '').strip()[:400]}")
        except SystemExit:
            pass
    if score is None:
        print("could not parse a SCORE out of the answer", file=sys.stderr)
        return 2
    passed = verdict == "PASS" and score >= gemini_gate.PASS_SCORE
    p = gemini_gate.record(
        clip, score, passed, verdict=verdict or ("PASS" if passed else "FAIL"),
        note=" | ".join(reasons)[:2000], sheet=str(sheet), replace=a.replace)
    # Keep the whole answer beside the verdict. The stored `note` is capped, and
    # a truncated review cannot be acted on: the actionable points sat past the
    # cut and had to be re-fetched by running the review again.
    raw = p.with_suffix(".md")
    raw.write_text(f"# {Path(clip).name}\n\nscore {score:g} / verdict "
                   f"{verdict or '-'}\n\n{(answer or '').strip()}\n",
                   encoding="utf-8")
    print(f"\nrecorded {p}  (full review: {raw.name})")
    print(f"SCORE {score:g}  VERDICT {verdict or '-'}  -> "
          f"{'PASS (may publish)' if passed else 'FAIL (must be fixed)'}")
    return 0 if passed else 1


if __name__ == "__main__":
    raise SystemExit(main())
