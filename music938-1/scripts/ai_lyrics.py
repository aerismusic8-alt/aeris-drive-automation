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

# A `# GENRE:` header alone is an id like "lukthung", not a writing brief — songs
# written from it come back as the same generic เพื่อชีวิต lyric the 20 existing
# ones already are. Each genre therefore also carries the imagery, the vocabulary
# and the line shape that make it *sound* like itself, which is what the style
# prompt later asks Flow Music to sing.
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
        # 10, not 8: 25 Thai pop hits measured 2026-11-23 (ops/lyric_text.py) sit at
        # a median of 10 syllables per line, p10-p90 of 7-14. Eight was short.
        "1) ทุกบรรทัดยาว 9-11 พยางค์ (เป้าหมาย 10 พยางค์; พยางค์ไทย = 1 เสียงสระ) "
        "ห้ามสั้นกว่า 7 ห้ามเกิน 14\n"
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




def parse_body(raw: str) -> list[tuple[str, list[str]]]:
    """Pull [section] + lines out of a lyric file.

    It used to also slice away the chat app's chrome and its echo of the prompt,
    because the text arrived scraped from a web page. AR writes the file, so the
    parser only has to read it.
    """
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
        # A mid-line tag means two sections were fused; the line is not a lyric,
        # so drop it rather than let Flow sing "[verse]".
        if re.search(r"\[(verse|chorus|bridge|intro|outro|pre[- ]?chorus)\]", s, re.I):
            continue
        # A trailing "(8)" is a syllable count, not a lyric, and Flow Music would
        # sing it. Strip a trailing parenthetical number.
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




















def render_file(meta: dict, sections: list[tuple[str, list[str]]]) -> str:
    head = [f"# {k}: {v}" for k, v in meta.items()]
    out = head + ["", ""]
    for sec, lines in sections:
        out.append(f"[{sec}]")
        out += lines
        out.append("")
    return "\n".join(out).rstrip() + "\n"


def load_ar(path: Path) -> tuple[list[tuple[str, list[str]]], list[str]]:
    """Read a lyric AR wrote, and lint it. Returns (sections, problems).

    The lyric arrives as a file, so it can be read, corrected and re-read before
    anything is sung. `lint_sections` is the same gate it always was: a line that
    does not fit the melody is caught here, not after a render.
    """
    sections = parse_body(path.read_text(encoding="utf-8"))
    return sections, lint_sections(sections)


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--slug", help="lint lyrics/<slug>.txt")
    ap.add_argument("--file", type=Path, help="lint any lyric file")
    args = ap.parse_args()

    if args.file:
        path = args.file
    elif args.slug:
        path = LYRICS / f"{args.slug}.txt"
    else:
        ap.error("give --slug or --file")
    if not path.exists():
        print(f"no such lyric: {path}", file=sys.stderr)
        return 2

    sections, problems = load_ar(path)
    if not sections:
        print("no [section] tags found — nothing to lint", file=sys.stderr)
        return 1
    nlines = sum(len(l) for _, l in sections)
    print(f"# sections: {[s for s, _ in sections]}  lines: {nlines}")
    if problems:
        print("rejected by lint:", file=sys.stderr)
        for prob in problems:
            print("  - " + prob, file=sys.stderr)
        return 3
    print("lint: PASS")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
