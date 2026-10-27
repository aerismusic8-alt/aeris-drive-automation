"""Thai text preparation for speech synthesis.

edge-tts has no Thai number dictionary: hand it "187" and it may read the digits
individually or drop them. Every digit run has to be spelled out first. Pauses in
the voice come from newlines, so newlines are preserved and intra-line spacing
between Thai characters is collapsed.
"""
from __future__ import annotations

import re

_DIGITS = ["ศูนย์", "หนึ่ง", "สอง", "สาม", "สี่", "ห้า", "หก", "เจ็ด", "แปด", "เก้า"]
_PLACES = ["", "สิบ", "ร้อย", "พัน", "หมื่น", "แสน"]

_THAI_RE = re.compile(r"[\u0E00-\u0E7F]")


def _under_million(n: int) -> str:
    if n == 0:
        return ""
    out = []
    s = str(n)
    length = len(s)
    for i, ch in enumerate(s):
        digit = int(ch)
        pos = length - i - 1
        if digit == 0:
            continue
        if pos == 0:
            # เอ็ด only after a ten, and never for a bare 1.
            out.append("เอ็ด" if (digit == 1 and length > 1) else _DIGITS[digit])
        elif pos == 1:
            if digit == 1:
                out.append("สิบ")
            elif digit == 2:
                out.append("ยี่สิบ")
            else:
                out.append(_DIGITS[digit] + "สิบ")
        else:
            out.append(_DIGITS[digit] + _PLACES[pos])
    return "".join(out)


def thai_number(n: int) -> str:
    if n == 0:
        return _DIGITS[0]
    if n < 0:
        return "ลบ" + thai_number(-n)
    if n >= 1_000_000:
        high, low = divmod(n, 1_000_000)
        text = thai_number(high) + "ล้าน"
        return text + (thai_number(low) if low else "")
    return _under_million(n)


def expand_numbers(text: str) -> str:
    """Spell out every integer. Decimals are read digit by digit after จุด."""
    def repl(m: re.Match) -> str:
        raw = m.group(0)
        if "." in raw:
            whole, frac = raw.split(".", 1)
            spoken = thai_number(int(whole)) if whole else ""
            return spoken + "จุด" + "".join(_DIGITS[int(c)] for c in frac if c.isdigit())
        return thai_number(int(raw))

    # Thousands separators are stripped before the run is read as one number.
    text = re.sub(r"\d[\d,]*(?:\.\d+)?", lambda m: repl(m) if True else m.group(0),
                  text)
    return text


def normalise(text: str) -> str:
    """Collapse intra-line spacing but keep the newlines that make the pauses."""
    lines = []
    for line in text.split("\n"):
        line = re.sub(r"[ \t]+", " ", line).strip()
        if _THAI_RE.search(line):
            # A space between two Thai characters is a typo, not a word break.
            line = re.sub(r"(?<=[\u0E00-\u0E7F]) (?=[\u0E00-\u0E7F])", "", line)
        lines.append(line)
    out = "\n".join(lines)
    out = re.sub(r"\n{3,}", "\n\n", out)
    return out.strip()


def prepare(text: str) -> str:
    return normalise(expand_numbers(text))


def script_lines(text: str) -> list[str]:
    """The lines that will actually be spoken, in order."""
    return [ln for ln in normalise(text).split("\n") if ln.strip()]
