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

# A `# GENRE:` header alone hands Gemini an id like "lukthung", which it does not
# read as a writing brief — the words come back as the same generic เพื่อชีวิต
# lyric the 20 existing songs already are. Each genre therefore also carries the
# imagery, the vocabulary and the line shape that make it *sound* like itself,
# which is what the style prompt later asks Flow Music to sing.
GENRE_BRIEF = {
    "lukthung": (
        "ลูกทุ่งไทย — ภาษาพูดบ้าน ๆ เข้าใจทันที ภาพชนบท ท้องนา ดอกไม้ ทางลูกรัง "
        "ความรัก ความจน ความคิดถึง และการจากลา ใช้คำลงท้ายร้องง่าย สัมผัสใน "
        "วรรคสั้นสม่ำเสมอ ฮุกติดปากแบบที่ร้องตามได้ในงานบุญ"
    ),
    "morlam": (
        "หมอลำ — จังหวะสนุก มันส์ ลายแคน เรียกตอบได้ "
        "คำเชื้อเชิญให้เต้นและสนุก ภาษาถิ่นอีสานปนไทยกลางได้ ฮุกสั้น ๆ ซ้ำได้บ่อย"
    ),
    "rock": (
        "ร็อกไทย — คำหนักแน่น มีพลัง อารมณ์ดิบ เนื้อเรื่องการต่อสู้ "
        "การยืนหยัด ความผิดหวังแล้วลุกขึ้นใหม่ วรรคสั้นกระชับ เน้นจังหวะ "
        "ท่อนฮุกต้องระเบิดพลังและตะโกนตามได้"
    ),
}

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


def build_prompt(meta: dict, angle: str = "") -> str:
    shape = " ".join(f"[{sec}] {n} บรรทัด" for sec, n in STRUCTURE)
    title = meta.get("TITLE", "")
    genre = meta.get("GENRE") or meta.get("MOOD") or "เพลงไทยฟังสบาย"
    brief = GENRE_BRIEF.get(str(meta.get("GENRE", "")).lower(), "")
    tempo = meta.get("TEMPO", "")
    return (
        "คุณเป็นนักแต่งเนื้อเพลงไทยมืออาชีพที่เพลงติดหูและร้องง่าย "
        "จงเขียนเนื้อเพลงไทยใหม่ทั้งเพลงตามกติกาต่อไปนี้อย่างเคร่งครัด\n"
        f"ชื่อเพลง: {title}\nแนว: {genre}\n"
        + (f"แนวนำทาง: {brief}\n" if brief else "")
        + (f"มุมเล่าเรื่อง (สำคัญ): {angle}\n" if angle else "")
        + (f"จังหวะ BPM: {tempo}\n" if tempo else "") +
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
            # Two stable polls (8 s) once fired while a long answer was still
            # streaming, and the partial text was then concatenated with the
            # finished answer — a lyric with two songs fused mid-line. An answer
            # is only "finished" when it is stable AND the last section of the
            # requested structure has arrived; a pause mid-verse is not the end.
            complete = len(parse_body(body)) >= len(STRUCTURE)
            if body == prev and not stop and complete:
                stable += 1
                if stable >= 3:
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
    sliced from after the last "… said" marker, not from the first "[verse]".
    Both ChatGPT and Gemini render that marker; whichever drafted, the rule is
    the same.
    """
    low = raw.lower()
    cut = -1
    for marker in ("gemini said", "chatgpt said"):
        i = low.rfind(marker)
        if i != -1:
            cut = max(cut, i + len(marker))
    if cut != -1:
        raw = raw[cut:]
    for stop in ("Sign in to connect", "Gemini is AI", "Gemini replied",
                 "ChatGPT can make mistakes", "About Gemini"):
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
        # A mid-line tag means two answers were fused (the stream-stability bug).
        # Such a line is not a lyric; drop it rather than let Flow sing "[verse]".
        if re.search(r"\[(verse|chorus|bridge|intro|outro|pre[- ]?chorus)\]", s, re.I):
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


def lint_sections(sections: list[tuple[str, list[str]]]) -> list[str]:
    """Reasons a candidate lyric must not reach Flow Music.

    Duck.ai's filter (consult 2026-11-04): a fused or truncated answer is the
    failure that wastes a render, so it is caught here rather than heard later.

    The length test is a *proxy*. Thai has no spaces between words, so a
    character count cannot be a syllable count; ~8 sung syllables land between
    roughly 10 and 30 Thai characters. The band rejects an empty or runaway
    line, not a stylistically short one.
    """
    problems: list[str] = []
    shape = [s for s, _ in STRUCTURE]
    got = [s for s, _ in sections]
    if len(sections) < len(shape):
        problems.append(f"only {len(sections)}/{len(shape)} sections")
    if got and got[0] != shape[0]:
        problems.append(f"starts with [{got[0]}], not [{shape[0]}]")
    if got and got[-1] != shape[-1]:
        problems.append(f"ends with [{got[-1]}], not [{shape[-1]}]")
    # A fused answer (partial stream + finished answer) carries the whole
    # structure as a contiguous block that does NOT start at position 0.
    if len(got) > len(shape):
        for i in range(1, len(got) - len(shape) + 1):
            if got[i:i + len(shape)] == shape:
                problems.append(f"structure repeats at position {i}: {got}")
                break
    for sec, lines in sections:
        if not lines:
            problems.append(f"[{sec}] is empty")
        for ln in lines:
            if "[" in ln or "]" in ln:
                problems.append(f"[{sec}] has a stray tag: {ln!r}")
            if "#" in ln or ln.endswith(":"):
                problems.append(f"[{sec}] looks like chrome: {ln!r}")
            # The voice is Thai-only; a stray Latin word (page chrome fused into
            # a line) would be sung as gibberish. The test suite rejects it too.
            if re.search(r"[A-Za-z]", ln):
                problems.append(f"[{sec}] has Latin text: {ln!r}")
            n = len(re.findall(r"[ก-๙]", ln))
            if n < 8 or n > 34:
                problems.append(f"[{sec}] line is {n} Thai chars: {ln!r}")
    return problems


def _drive_chatgpt(prompt: str, timeout_s: int = 300) -> str:
    """Draft with the signed-in ChatGPT web app.

    Gemini web is signed out on this desktop and the signed-out Flash-Lite model
    refuses the writing brief outright ("ฉันเป็นแค่โมเดลภาษา ... นอกเหนือ
    ความสามารถ"), so the drafting step runs on ChatGPT — which is signed in and
    is the stronger drafter anyway. Duck.ai stays the judge, so it still answers
    on the day the Google session is what is broken.
    """
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import chatgpt_ask  # noqa: PLC0415

    return chatgpt_ask.ask(prompt, new_chat=True, timeout=timeout_s)


def _drive_duck(prompt: str, timeout_s: int = 300) -> str:
    """Draft with Duck.ai — no login, no API key, so it survives a dead session.

    The lyric rail used to need the ChatGPT web app, which needs K's Google
    session; when that is signed out there is no new song at all. Duck.ai is
    keyless and its Thai is the strongest of the free channels (measured
    2026-11-07: pollinations is faster but its Thai is weak and it rate-limits to
    one reply per 45s, so it is the second opinion, not the drafter). The
    `lint_sections` filter still decides whether a draft may reach Flow Music, so
    a weaker channel costs a retry, not a bad render.
    """
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import duck_ask  # noqa: PLC0415

    return duck_ask.ask(prompt, timeout=timeout_s)


DRAFTERS = {"gemini": _drive_gemini, "chatgpt": _drive_chatgpt, "duck": _drive_duck}


def draft(meta: dict, angle: str = "", drafter: str = "chatgpt"
          ) -> tuple[list[tuple[str, list[str]]], list[str]]:
    """One draft, parsed and linted. Returns (sections, problems).

    A thin public wrapper so the multi-AI forge drives the same prompt, the same
    parser and the same filter as the single-shot path.
    """
    sections = parse_body(DRAFTERS[drafter](build_prompt(meta, angle)))
    return sections, lint_sections(sections)


def render_file(meta: dict, sections: list[tuple[str, list[str]]]) -> str:
    head = [f"# {k}: {v}" for k, v in meta.items()]
    out = head + ["", ""]
    for sec, lines in sections:
        out.append(f"[{sec}]")
        out += lines
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--slug", help="rewrite lyrics/<slug>.txt, keeping its header")
    ap.add_argument("--brief", help="title|genre|mood[|tempo|key|voice] for a new song")
    ap.add_argument("--write", action="store_true", help="overwrite the lyric file")
    ap.add_argument("--out", type=Path, help="write the candidate here instead")
    ap.add_argument("--force", action="store_true", help="write even if lint fails")
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
        for i, key in enumerate(("GENRE", "MOOD", "TEMPO", "KEY", "VOICE"), start=1):
            if len(parts) > i and parts[i]:
                meta[key] = parts[i]
        path = None
    else:
        ap.error("give --slug or --brief")

    body = _drive_gemini(build_prompt(meta))
    sections = parse_body(body)
    if not sections:
        print("Gemini returned no sections; raw tail:", file=sys.stderr)
        print(body[-800:], file=sys.stderr)
        return 1
    problems = lint_sections(sections)
    if problems:
        print("candidate rejected by lint:", file=sys.stderr)
        for p in problems:
            print("  - " + p, file=sys.stderr)
        if not args.force:
            return 3
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
