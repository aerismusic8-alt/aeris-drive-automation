#!/usr/bin/env python3
"""Write or rewrite a Thai lyric with a free AI (Gemini web, signed out).

K (2026-11-03) on the pack: the music is good, but the lyrics do not sit on the
melody — the phrasing does not breathe, the line breaks fall in the wrong place,
and the hook does not stick. Flow Music sings *exactly* the line breaks it is
handed, so a line that is one word too long, or a break in the middle of a
phrase, comes back as a melody that fights the vocal. That is the root cause of
"ทำนองกับเสียงร้องขัดกัน" — it is a lyric problem, not a melody problem.

This asks Gemini for the words instead of writing them by hand, under a strict
brief that targets exactly those faults:

* a fixed syllable count per line (a Thai syllable is a vowel sound, so the
  count is what the melody has room for);
* one breath per line, no line that needs two;
* the line break on the natural phrase boundary;
* an A-B-A-B end-rhyme, and a chorus first line that repeats as a hook.

Gemini is driven on the cloud desktop and needs no login. Nothing is published,
and an existing lyric is not overwritten unless `--write` is given — the output
goes to stdout by default so it can be read before it is trusted.

    python3 scripts/ai_lyrics.py --slug 04-saeng-chao-wan-mai
    python3 scripts/ai_lyrics.py --slug 04-saeng-chao-wan-mai --write
    python3 scripts/ai_lyrics.py --brief "แสงเช้าวันใหม่|เพื่อชีวิต|hopeful"
"""
from __future__ import annotations

import argparse
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LYRICS = ROOT / "lyrics"
GEMINI = "https://gemini.google.com/app"

# Song 01 is verse8/chorus8/verse4/chorus8/bridge3/chorus8 and renders at the
# model's create ceiling; the rest of the pack was expanded to match. A rewrite
# keeps that shape so the song still clears the length floor.
STRUCTURE = [
    ("verse", 4), ("chorus", 4), ("verse", 4), ("chorus", 4), ("bridge", 2),
    ("chorus", 4),
]


def read_header(path: Path) -> dict:
    meta: dict = {}
    for raw in path.read_text(encoding="utf-8").splitlines():
        line = raw.strip()
        if not line:
            continue
        m = re.match(r"#\s*([A-Z]+)\s*:\s*(.+)", line)
        if m:
            meta[m.group(1)] = m.group(2).strip()
        elif line.startswith("["):
            break
    return meta


def build_prompt(meta: dict) -> str:
    shape = " ".join(f"[{sec}] {n} บรรทัด" for sec, n in STRUCTURE)
    title = meta.get("TITLE", "")
    genre = meta.get("GENRE") or meta.get("MOOD") or "เพลงไทยฟังสบาย"
    tempo = meta.get("TEMPO", "")
    return (
        "คุณเป็นนักแต่งเนื้อเพลงไทยมืออาชีพที่เพลงติดหูและร้องง่าย "
        "จงเขียนเนื้อเพลงไทยใหม่ทั้งเพลงตามกติกาต่อไปนี้อย่างเคร่งครัด\n"
        f"ชื่อเพลง: {title}\nแนว: {genre}\n" + (f"จังหวะ BPM: {tempo}\n" if tempo else "") +
        f"โครงสร้าง (ต้องครบทุกท่อนและเรียงตามนี้): {shape}\n\n"
        "กติกา:\n"
        "1) ทุกบรรทัดยาว 8 พยางค์พอดี (พยางค์ไทย = 1 เสียงสระ) ห้ามเกินห้ามขาด\n"
        "2) 1 บรรทัด = 1 ลมหายใจ ห้ามมีบรรทัดที่ต้องหายใจกลางคัน\n"
        "3) ตัดบรรทัดตรงขอบวลีธรรมชาติ เหมือนจังหวะที่คนพูดจริง ไม่ตัดกลางคำ\n"
        "4) สัมผัสสระท้ายบรรทัดแบบ ก-ข-ก-ข (บรรทัด 1,3 สัมผัสกัน และ 2,4 สัมผัสกัน) "
        "แต่ห้ามฝืนความหมายเพื่อให้สัมผัส\n"
        "5) บรรทัดแรกของทุก [chorus] ต้องเป็นฮุกสั้น จำง่าย และร้องซ้ำได้\n"
        "6) ภาษาเรียบง่าย เป็นธรรมชาติ ไม่ประดิษฐ์คำ\n\n"
        "ตัวอย่าง 'รูปแบบ' ที่ถูกต้อง (คนละเพลง ห้ามลอกเนื้อความ):\n"
        "[verse]\nวันคืนที่ผ่านพ้นไป\nยังเหลือไว้แต่ความหลัง\n"
        "แม้เวลาจะเปลี่ยนผัน\nใจดวงนี้ยังเหมือนเดิม\n"
        "[chorus]\nอยากย้อนเวลากลับไป\nไปวันที่เรายังรักกัน\n"
        "กอดเธอไว้ไม่ให้หาย\nให้ความฝันนั้นเป็นจริง\n\n"
        f"ตอนนี้จงเขียนเพลง '{title}' ทั้งเพลง ครบทุกท่อนตามโครงสร้าง "
        "เริ่มตอบด้วย [verse] ทันที ตอบเฉพาะเนื้อเพลง ห้ามมีคำอธิบายหรือเลขกำกับ"
    )


def _drive_gemini(prompt: str, timeout_s: int = 180) -> str:
    sys.path.insert(0, str(ROOT.parent / "aeris938-1" / "scripts"))
    from playwright.sync_api import sync_playwright

    pw = sync_playwright().start()
    br = pw.chromium.connect_over_cdp("http://127.0.0.1:9222")
    ctx = br.contexts[0]
    p = ctx.new_page()
    p.set_viewport_size({"width": 1400, "height": 950})
    try:
        p.goto(GEMINI, wait_until="domcontentloaded", timeout=45000)
        p.wait_for_timeout(5000)
        p.click("div[contenteditable=true]")
        p.wait_for_timeout(400)
        # insert_text, not type: the prompt is multi-line, and `type` turns every
        # "\n" into an Enter — which SUBMITS the message, so Gemini received only
        # the first line and answered "please give me the details".
        p.keyboard.insert_text(prompt)
        p.wait_for_timeout(900)
        box = p.locator("div[contenteditable=true]").first
        entered = box.inner_text()
        if "กติกา" not in entered or "[chorus]" not in entered:
            print(f"WARN: prompt entered only {len(entered)} chars", file=sys.stderr)
        p.keyboard.press("Enter")
        # The prompt itself contains the literal "[chorus]" tag, so the echoed
        # prompt cannot be the "done" signal — that matched on the first poll and
        # captured an empty answer. Wait for the answer text to stop growing and
        # for the streaming/stop control to disappear.
        deadline = time.time() + timeout_s
        body, prev, stable = "", "", 0
        p.wait_for_timeout(9000)
        while time.time() < deadline:
            p.wait_for_timeout(4000)
            body = p.inner_text("body")
            stop = p.query_selector("button[aria-label*='Stop'], button[aria-label*='หยุด']")
            if body == prev and not stop:
                stable += 1
                if stable >= 2:
                    break
            else:
                stable = 0
            prev = body
        return body
    finally:
        p.close()
        pw.stop()


def parse_body(raw: str) -> list[tuple[str, list[str]]]:
    """Pull [section] + lines out of the model's answer, dropping the chrome.

    The page text carries the app chrome AND an echo of the prompt, and the
    prompt itself contains the literal section tags — so the answer must be
    sliced from after the last "Gemini said", not from the first "[verse]".
    """
    low = raw.lower()
    idx = low.rfind("gemini said")
    if idx != -1:
        raw = raw[idx + len("gemini said"):]
    for stop in ("Sign in to connect", "Gemini is AI", "Gemini replied",
                 "About Gemini"):
        if stop in raw:
            raw = raw[: raw.find(stop)]
    chrome = {"flash-lite", "flash", "pro", "sign in", "new chat", "images",
              "settings", "get app", "you said", "gemini said"}
    sections: list[tuple[str, list[str]]] = []
    cur: tuple[str, list[str]] | None = None
    for line in raw.splitlines():
        s = line.strip()
        if not s:
            continue
        m = re.match(r"\[(verse|chorus|bridge|intro|outro|pre[- ]?chorus)\]", s, re.I)
        if m:
            cur = (m.group(1).lower(), [])
            sections.append(cur)
            continue
        if cur is None or s.startswith("[") or s.startswith("#"):
            continue
        if s.lower() in chrome:
            continue
        # The model often echoes the syllable count it is aiming for as a
        # trailing "(8)"; it is not part of the lyric and Flow Music would sing
        # it. Strip a trailing parenthetical number.
        s = re.sub(r"\s*[\(（]?\s*\d{1,2}\s*[\)）]?\s*$", "", s) \
            if re.search(r"[\(（]\s*\d{1,2}\s*[\)）]\s*$", s) else s
        if s:
            cur[1].append(s)
    return [(sec, lines) for sec, lines in sections if lines]


def render_file(meta: dict, sections: list[tuple[str, list[str]]]) -> str:
    head = [f"# {k}: {v}" for k, v in meta.items()]
    out = head + ["", ""]
    seen: dict[str, int] = {}
    for sec, lines in sections:
        seen[sec] = seen.get(sec, 0) + 1
        tag = sec if seen[sec] == 1 else sec
        out.append(f"[{tag}]")
        out += lines
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--slug", help="rewrite lyrics/<slug>.txt, keeping its header")
    ap.add_argument("--brief", help="title|genre|mood for a brand-new song")
    ap.add_argument("--write", action="store_true", help="overwrite the lyric file")
    ap.add_argument("--out", type=Path, help="write the candidate here instead")
    args = ap.parse_args()

    if args.slug:
        path = LYRICS / f"{args.slug}.txt"
        if not path.exists():
            print(f"no such lyric: {path}", file=sys.stderr)
            return 2
        meta = read_header(path)
    elif args.brief:
        parts = [p.strip() for p in args.brief.split("|")]
        meta = {"TITLE": parts[0] if parts else "เพลงใหม่"}
        if len(parts) > 1 and parts[1]:
            meta["GENRE"] = parts[1]
        if len(parts) > 2 and parts[2]:
            meta["MOOD"] = parts[2]
        path = None
    else:
        ap.error("give --slug or --brief")

    body = _drive_gemini(build_prompt(meta))
    sections = parse_body(body)
    if not sections:
        print("Gemini returned no sections; raw tail:", file=sys.stderr)
        print(body[-800:], file=sys.stderr)
        return 1
    text = render_file(meta, sections)
    nlines = sum(len(l) for _, l in sections)
    print(f"# sections: {[s for s, _ in sections]}  lines: {nlines}", file=sys.stderr)

    if args.out:
        args.out.write_text(text, encoding="utf-8")
        print(f"wrote {args.out}", file=sys.stderr)
    elif args.write and path:
        path.write_text(text, encoding="utf-8")
        print(f"wrote {path}", file=sys.stderr)
    else:
        print(text)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
