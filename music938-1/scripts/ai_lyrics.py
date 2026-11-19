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
    "pop": (
        "ป็อปไทย — ภาษาง่าย ฟังครั้งเดียวติดหู เรื่องรักในชีวิตประจำวัน "
        "ความรักครั้งใหม่ ความสุขเล็ก ๆ การเต้นตามจังหวะ ฮุกสั้น ๆ ซ้ำคำ "
        "วรรคสั้นสม่ำเสมอ ร้องตามได้ทันที"
    ),
    "edm": (
        "อีดีเอ็ม/แดนซ์ — จังหวะมันส์ ปลุกให้ลุกขึ้นเต้น คำสั้น ๆ กระแทกจังหวะ "
        "คำเชื้อเชิญให้ปล่อยใจไปกับเสียงเพลง ฮุกซ้ำ ๆ แบบตะโกนได้ "
        "บรรทัดสั้น ๆ ให้เข้ากับบีต"
    ),
    "synthpop": (
        "ซินธ์ป็อป — จังหวะสดใส ภาพแสงสียามค่ำคืน ความฝันวัยหนุ่มสาว "
        "ความรักในเมืองใหญ่ คำทันสมัยสั้น ๆ ฮุกติดหูแบบซินธ์ "
        "วรรคสั้นสม่ำเสมอ ร้องตามได้"
    ),
    "citypop": (
        "ซิตี้ป็อป — ภาพเมืองยามค่ำคืน ไฟนีออน ถนนเปียกฝน ความรักที่ผ่านมา "
        "ความรู้สึกอบอุ่นปนเหงา คำเรียบ ๆ ชวนฝัน ฮุกนุ่ม ๆ "
        "วรรคยาวปานกลาง ลื่นไหล"
    ),
    "rnb": (
        "อาร์แอนด์บี — นุ่ม ๆ อ่อนโยน เรื่องความรัก ความคิดถึงที่ไม่กล้าบอก "
        "คำหวาน ๆ จังหวะช้า ๆ ฮุกนุ่ม ๆ ซ้ำได้ "
        "วรรคสั้นปานกลาง เน้นอารมณ์และความใกล้ชิด"
    ),
    "rap": (
        "แร็ป/ฮิปฮอปไทย — ภาษาพูดมันส์ ๆ จังหวะหนักแน่น สัมผัสในถี่ ๆ "
        "เนื้อเรื่องความมุ่งมั่น การฝึกฝน พัฒนาตัวเอง ความฝันใหญ่ และการไม่ยอมแพ้ "
        "ให้กำลังใจคนฟัง มีพลังบวก วรรคสั้นกระชับเข้าจังหวะ ฮุกซ้ำคำได้"
    ),
}

# Some keyless drafters refuse a Thai rap brief outright ("I can't help with
# that") when it reads like it could be about violence or aggression. Naming the
# tone up front — positive, no violence — clears the filter, and it also matches
# the brand's message (K wants followers, not shock). The genre still sets the
# sound; this only removes the framing the filter objects to.
POSITIVE_TONE = (
    "โทนเพลง: สร้างสรรค์และให้กำลังใจ ไม่มีความรุนแรง คำหยาบ การต่อสู้ "
    "หรือการดูถูกใคร เน้นความมุ่งมั่น การฝึกฝน และพลังบวก\n"
)

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
        + POSITIVE_TONE
        + f"ชื่อเพลง: {title}\nแนว: {genre}\n"
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
        "ตัวอย่าง 'รูปแบบ' ที่ถูกต้อง (คนละเพลง ห้ามลอกเนื้อความ ห้ามใช้บรรทัดเหล่านี้ซ้ำ "
        "เด็ดขาด ให้แต่งใหม่ทั้งหมดตามชื่อเพลงและโจทย์ด้านบน):\n"
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
    # "Gemini บอกว่า" is the marker the desktop's Thai UI renders; without it the
    # cut missed, the echoed prompt survived, and the answer's first section was
    # the prompt's own example lyric (measured 2026-11-19).
    for marker in ("gemini said", "chatgpt said", "gemini บอกว่า", "แชทจีพีทีบอกว่า"):
        i = low.rfind(marker)
        if i != -1:
            cut = max(cut, i + len(marker))
    if cut != -1:
        raw = raw[cut:]
    for stop in ("Sign in to connect", "Gemini is AI", "Gemini replied",
                 "ChatGPT can make mistakes", "About Gemini",
                 "Gemini เป็น AI", "อัปเกรด", "อัตโนมัติ"):
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
        m = re.match(
            r"^[\s*(\[]*(verse|chorus|bridge|intro|outro|pre[- ]?chorus)"
            r"[\s*)\]\d:.\-—]*$", s, re.I)
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

    The ceiling is 42, not 34: measured 2026-11-14, a run of drafts died on
    lines of 36-39 characters that were perfectly singable Thai (one held note
    spans two syllables), so 34 was rejecting real songs to catch a fused answer.
    A fused answer is not marginal — it is the whole section on one line, well
    past 60 characters — so the higher ceiling still catches it while the drafts
    that were being thrown away now reach Flow Music.
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
            if n < 8 or n > 42:
                problems.append(f"[{sec}] line is {n} Thai chars: {ln!r}")
            if CHROME.search(ln):
                problems.append(f"[{sec}] carries page chrome: {ln!r}")
    return problems


# Gemini's answer arrives with the page footer fused onto the last section
# ("อัตโนมัติ", "Gemini เป็น AI และอาจทำผิดพลาดได้"). Those are not lyrics and
# must never reach Flow Music, which would sing them.
CHROME = re.compile(
    r"อัตโนมัติ|Gemini|AI และอาจทำผิดพลาด|อัปเกรด|แชท|ข้อความ|เข้าสู่ระบบ"
)


def _default_reader():
    """A model that can read Thai: the API when a key is set, else the web app.

    The API comes first because the produce rail runs on a GitHub runner, which
    has no cloud desktop: a web-app-only reader would fail closed on every CI
    draft and stall the whole lane. `_drive_gemini` is never used — it waits for
    `[section]` tags to decide an answer is finished, so for a question that has
    none it never returns and hands back the page sidebar instead.
    """
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import gemini_api  # noqa: PLC0415

    def ask(question: str, timeout_s: int = 240) -> str:
        try:
            return gemini_api.ask(question, timeout=timeout_s)
        except Exception as api_exc:  # noqa: BLE001
            import gemini_ask  # noqa: PLC0415
            try:
                return gemini_ask.ask(question, new_chat=True, timeout=timeout_s)
            except Exception as web_exc:  # noqa: BLE001
                raise RuntimeError(
                    f"no reader available: api={api_exc}; web={web_exc}"
                ) from web_exc

    return ask


def verify_meaning(sections: list[tuple[str, list[str]]],
                   ask=None, timeout_s: int = 240) -> list[str]:
    """Ask a model whether the words are actually Thai, and believe the answer.

    Measured 2026-11-19: the free drafters do not all write Thai. Gemini web
    produced singable Thai ("ปิดไฟห้องแล้วเดินออกไป"), while pollinations'
    `openai-fast` produced syllable salad that passed every structural test —
    real syllables, real line lengths, no Latin, no chrome:
    "ตัดขาออกทางเส้นทางจิต / แสงนี๊ดตอบใจข้างหลัง". A dictionary cannot catch it
    (every token is a genuine word; `thai_words` coverage scored 1.00 on the
    worst lines) and neither can a function-word count (measured: a salad line
    scored 2.0 against a correct line's 0.0, i.e. backwards). Only a reader of
    the language can, so the check asks one.

    The reader is `ops/gemini_api` when a key is set, else `ops/gemini_ask`
    (the signed-in web app). The API comes first because the produce rail runs
    on a GitHub runner, which has no cloud desktop: a web-app-only reader would
    fail closed on every CI draft and stall the whole lane. `_drive_gemini` is
    never used — it waits for `[section]` tags to decide an answer is finished,
    so for a question that has none it never returns and hands back the page
    sidebar instead.

    A reader that cannot be reached reports a problem rather than passing: an
    unread lyric is not a lyric we know reads.

    Returns a list of reasons the lyric must not be used; empty means it reads.
    """
    if ask is None:
        ask = _default_reader()

    text = "\n".join(ln for _, lines in sections for ln in lines)
    question = (
        "อ่านเนื้อเพลงไทยต่อไปนี้ แล้วตอบว่ามันเป็นประโยคภาษาไทยที่มีความหมาย "
        "จริงหรือไม่ (ไม่ใช่คำไทยที่เอามาเรียงมั่วจนอ่านไม่รู้เรื่อง)\n"
        "ตอบบรรทัดแรกด้วยคำเดียว: PASS หรือ FAIL\n"
        "ถ้า FAIL ให้บอกบรรทัดที่ผิดและเพราะอะไร สั้น ๆ\n\n"
        f"เนื้อเพลง:\n{text}\n"
    )
    answer = ask(question, timeout_s=timeout_s)
    first = next((ln.strip() for ln in answer.splitlines() if ln.strip()), "")
    if first.upper().startswith("PASS"):
        return []
    reason = " ".join(answer.split())[:300]
    return [f"meaning check did not pass: {reason}"]


def repair_lines(sections: list[tuple[str, list[str]]], reason: str,
                 ask=None, timeout_s: int = 240) -> list[tuple[str, list[str]]]:
    """Rewrite only the lines the meaning check objected to.

    Measured 2026-11-19: a rock lyric came back with one weak line
    ("มองข้างหน้าไม่คลาดแคล้ว" — "not missing" grafted onto a dawn image) among
    five good ones, and rejecting the whole draft threw away a usable hook and
    two verses. The check names the offending line, so the fix is surgical: ask
    for that one line again, keep every other line byte-for-byte.

    A line that cannot be replaced stays as it was, so the caller's next
    `verify_meaning` still rejects the draft. Repair can improve a draft; it can
    never launder a bad one through.
    """
    ask = ask or _default_reader()
    bad = re.findall(r"FAIL\s*(.+?)(?:\s*—|\s*-|:|\n|$)", reason)
    quoted = [b.strip() for b in bad if len(re.findall(r"[ก-๙]", b)) >= 4]
    fixed = list(sections)
    for target in quoted:
        for i, (sec, lines) in enumerate(fixed):
            for j, ln in enumerate(lines):
                if ln.strip() != target and target not in ln:
                    continue
                question = (
                    f"ในเพลงไทยนี้ บรรทัดนี้ยังไม่เป็นธรรมชาติ: {ln}\n"
                    f"เขียนบรรทัดเดิมใหม่ 1 บรรทัด ให้เป็นภาษาไทยที่ลื่นไหล "
                    f"ความหมายเดิม ยาวพอ ๆ กับเดิม (ราว 8 พยางค์) "
                    f"และเข้าท่อน [{sec}]\n"
                    "ตอบเฉพาะบรรทัดใหม่ บรรทัดเดียว ห้ามอธิบาย\n"
                )
                try:
                    out = ask(question, timeout_s=timeout_s)
                except Exception:  # noqa: BLE001
                    continue
                cand = next((c.strip() for c in out.splitlines()
                             if len(re.findall(r"[ก-๙]", c)) >= 8), "")
                if cand and not re.search(r"[A-Za-z]", cand):
                    fixed[i] = (sec, lines[:j] + [cand] + lines[j + 1:])
                break
    return fixed


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


def _drive_pollinations(prompt: str, timeout_s: int = 180) -> str:
    """Draft over plain HTTP — no browser, so it works where Duck.ai cannot.

    Duck.ai is driven through the cloud desktop's CDP port, so on a machine with
    no desktop (a GitHub Actions runner) the whole lyric rail stops. Pollinations
    is plain HTTP with no key and no login, so it survives a runner. Its Thai is
    weaker (measured 2026-11-07) and it rate-limits to one reply per ~45s, so it
    is the fallback channel; `lint_sections` still decides what may be used.
    """
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import pollinations_ask  # noqa: PLC0415

    return pollinations_ask.ask(prompt, timeout=timeout_s)


def _drive_gemini_api(prompt: str, timeout_s: int = 120) -> str:
    """Draft through the Gemini API free tier — plain HTTP, runs in CI.

    Gemini's own advice (2026-11-18), after the keyless channels refused the Thai
    rap prompt: the free tier needs no card, its filter is looser, and it needs
    no browser tab. Raises `GeminiUnavailable` with no key so the loop falls
    through to the next drafter instead of failing the run.
    """
    sys.path.insert(0, str(ROOT.parent / "ops"))
    import gemini_api  # noqa: PLC0415

    return gemini_api.ask(prompt, timeout=timeout_s)


DRAFTERS = {"gemini": _drive_gemini, "chatgpt": _drive_chatgpt,
            "duck": _drive_duck, "pollinations": _drive_pollinations,
            "gemini-api": _drive_gemini_api}


def draft(meta: dict, angle: str = "", drafter: str = "chatgpt",
          check_meaning: bool = True
          ) -> tuple[list[tuple[str, list[str]]], list[str]]:
    """One draft, parsed and linted. Returns (sections, problems).

    A thin public wrapper so the multi-AI forge drives the same prompt, the same
    parser and the same filter as the single-shot path.

    The meaning check lives *here* rather than only in `main()` because this is
    the path the produce rail takes: gating only the CLI left `produce_loop`
    free to write a syllable-salad lyric and render it, which is exactly how the
    2026-11-19 pack shipped. A drafter that fails it is reported like any other
    bad draft, so the loop tries the next channel instead of using the text.
    """
    raw = DRAFTERS[drafter](build_prompt(meta, angle))
    sections = parse_body(raw)
    if not sections:
        # The parser found no [section] tags. That is either a model refusal or
        # a heading style the parser did not recognise (2026-11-18: a CI run
        # answered in Thai but parsed to 0/6 and looked like an empty reply).
        # Print a bounded preview so the next run shows which it was.
        preview = " / ".join(raw.split())[:300]
        print(f"  {drafter}: parsed 0 sections; raw preview: {preview}",
              flush=True)
        return sections, lint_sections(sections)
    problems = lint_sections(sections)
    if check_meaning and not problems:
        problems = verify_meaning(sections)
        if problems:
            # One weak line should cost that line, not the whole draft. Repair
            # only what the check named, then judge the result again: an
            # unrepaired line still fails, so this cannot launder a bad lyric.
            repaired = repair_lines(sections, " ".join(problems))
            again = verify_meaning(repaired)
            if not again:
                sections, problems = repaired, []
    return sections, problems


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
    # Structure and length cannot tell real Thai from a syllable salad, so a
    # lyric that reads correctly is a separate gate. Skipped under --force.
    if not args.force:
        meaning = verify_meaning(sections)
        if meaning:
            print("candidate rejected by the meaning check:", file=sys.stderr)
            for p in meaning:
                print("  - " + p, file=sys.stderr)
            return 4
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
