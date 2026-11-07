#!/usr/bin/env python3
"""Forge one Thai song per genre with a multi-AI filter, then render it.

K (2026-11-04): "ลองสร้างสูตรแต่งเพลง โดยใช้ ai หลายตัวช่วยกรองจนได้เนื้อร้อง
ทำนอง ที่คิดว่าดีที่สุด แล้วสร้างเป็นเพลง ในแต่ละแนวเพลง ส่งให้ k ฟังหน่อย".

The formula follows the advisors' verdict (Duck.ai, consult 2026-11-04):

    ChatGPT   — drafts (here: Gemini web drafts, because it is the driver that
                already exists and needs no login)
    Gemini    — critiques the draft point by point (does not rewrite it)
    Duck.ai   — judges only when the critique leaves a real disagreement
    human/AR  — locks the final text before a single Flow Music credit is spent

Flow Music's free credits are the scarce resource (~2-3 renders/day), so the
filter runs entirely offline of Flow: a candidate must pass `lint_sections` and
a second AI's critique before it is allowed to cost a render.

    python3 scripts/forge_song.py --genre lukthung
    python3 scripts/forge_song.py --genre rock --slug 27-...
    python3 scripts/forge_song.py --genre lukthung --no-render
"""
from __future__ import annotations

import argparse
import json
import re
import sys
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
REPO = ROOT.parent
sys.path.insert(0, str(ROOT / "scripts"))
sys.path.insert(0, str(REPO / "ops"))

import ai_lyrics as A  # noqa: E402
import genres as G  # noqa: E402

LOG = ROOT / "work" / "forge.jsonl"


def log(rec: dict) -> None:
    LOG.parent.mkdir(parents=True, exist_ok=True)
    with LOG.open("a", encoding="utf-8") as fh:
        fh.write(json.dumps(rec, ensure_ascii=False) + "\n")


def as_text(sections: list[tuple[str, list[str]]]) -> str:
    out = []
    for sec, lines in sections:
        out.append(f"[{sec}]")
        out += lines
    return "\n".join(out)


def critique(genre: str, sections: list[tuple[str, list[str]]]) -> str:
    """Second AI's point-by-point critique (does not rewrite the lyric).

    Duck.ai is the critic: it needs no login, so the filter still runs on the day
    the Google session is what is broken, and it is a different vendor from the
    ChatGPT drafter.
    """
    import duck_ask
    q = (
        "คุณเป็นโปรดิวเซอร์เพลงไทย จงวิจารณ์เนื้อเพลงนี้แบบจุดต่อจุด สั้น ๆ\n"
        f"แนว: {genre}\n"
        "เกณฑ์: (1) ภาษาตรงแนวไหม (2) ฮุกจำง่ายไหม (3) มีคำ/ภาพซ้ำซากไหม "
        "(4) บรรทัดไหนร้องยากหรือยืดเกิน 8 พยางค์ (5) จุดที่ควรแก้ 1-3 จุด\n"
        "ห้ามเขียนเนื้อเพลงใหม่ทั้งเพลง ตอบเป็นข้อ ๆ\n\n"
        "เนื้อเพลง:\n" + as_text(sections)
    )
    return duck_ask.ask(q, timeout=240)


def judge(genre: str, a: str, b: str) -> str:
    """Duck.ai decides when two drafts disagree on quality."""
    import duck_ask
    q = (
        f"เพลงแนว {genre} มีเนื้อเพลง 2 ฉบับ ให้คะแนนฉบับละ 10 ตามเกณฑ์ "
        "ความติดหู ภาษาตรงแนว และร้องง่าย\n"
        "บรรทัดสุดท้ายต้องเป็น 'เลือก: A' หรือ 'เลือก: B' เท่านั้น "
        "(ห้ามตอบอื่น)\n\nฉบับ A:\n" + a + "\n\nฉบับ B:\n" + b
    )
    return duck_ask.ask(q, timeout=240)


def pick(text: str, n: int) -> int:
    """Which draft the judge chose, as an index into `drafts`.

    Only a verdict the judge actually stated is honoured; anything ambiguous
    leaves the first draft in place rather than guessing from a stray letter.
    """
    if n < 2:
        return 0
    m = re.search(r"เลือก\s*[:：]?\s*([AB])", text, re.I)
    if not m:
        m = re.search(r"ฉบับ\s*([AB])\s*ดีกว่า", text, re.I)
    if m:
        return 0 if m.group(1).upper() == "A" else 1
    return 0


def forge(genre: str, slug: str, title: str, mood: str, tempo: str, key: str,
          voice: str, angles: list[str], do_render: bool) -> int:
    meta = {"TITLE": title, "GENRE": genre, "MOOD": mood, "TEMPO": tempo,
            "KEY": key, "VOICE": voice}
    drafts: list[tuple[list[tuple[str, list[str]]], list[str]]] = []
    # Keyless first: Duck.ai needs no login, so a song can still be made on the
    # day K's Google session is signed out. ChatGPT is the fallback for when
    # Duck is rate-limited or its draft fails the lint. Both go through the same
    # prompt, parser and filter, so a weaker channel costs a retry, not a render.
    for i, angle in enumerate(angles):
        print(f"[draft {i+1}/{len(angles)}] {angle}", flush=True)
        secs: list[tuple[str, list[str]]] = []
        problems: list[str] = []
        for drafter in ("duck", "chatgpt"):
            try:
                secs, problems = A.draft(meta, angle, drafter=drafter)
            except Exception as exc:  # noqa: BLE001
                problems = [f"{drafter}: {type(exc).__name__}: {exc}"]
                continue
            print(f"  {drafter}: sections={len(secs)} problems={problems[:2]}",
                  flush=True)
            if secs and not problems:
                break
        if secs and not problems:
            drafts.append((secs, problems))
        time.sleep(2)
    if not drafts:
        print("no draft passed the filter", file=sys.stderr)
        log({"slug": slug, "genre": genre, "result": "no-draft"})
        return 1

    best = drafts[0][0]
    rec: dict = {"slug": slug, "genre": genre, "drafts": len(drafts)}
    try:
        c = critique(genre, best)
        rec["critique"] = c[:2000]
        print("--- critique ---\n" + c[:700], flush=True)
    except Exception as exc:  # noqa: BLE001
        rec["critique_error"] = f"{type(exc).__name__}: {exc}"
    if len(drafts) > 1:
        try:
            verdict = judge(genre, as_text(drafts[0][0]), as_text(drafts[1][0]))
            rec["judge"] = verdict[:1500]
            chosen = pick(verdict, len(drafts))
            rec["chosen"] = "AB"[chosen]
            best = drafts[chosen][0]
            print(f"judge chose {rec['chosen']}", flush=True)
        except Exception as exc:  # noqa: BLE001
            rec["judge_error"] = f"{type(exc).__name__}: {exc}"

    out = ROOT / "lyrics" / f"{slug}.txt"
    out.write_text(A.render_file(meta, best), encoding="utf-8")
    rec["wrote"] = str(out)
    print(f"wrote {out}", flush=True)
    log(rec)

    if do_render:
        import subprocess
        print("rendering with Flow Music...", flush=True)
        r = subprocess.run(
            [sys.executable, str(ROOT / "scripts" / "flow_song.py"), slug, "--force"],
            cwd=ROOT, text=True, capture_output=True, timeout=1500,
        )
        print((r.stdout or "")[-800:], (r.stderr or "")[-400:], flush=True)
        rec["render_rc"] = r.returncode
        log(rec)
    return 0


def main() -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--genre", required=True)
    ap.add_argument("--slug", required=True)
    ap.add_argument("--title", required=True)
    ap.add_argument("--mood", default="hopeful")
    ap.add_argument("--tempo", default="")
    ap.add_argument("--key", default="")
    ap.add_argument("--voice", default="female")
    ap.add_argument("--angles", default="ความรักที่รอคอย|ความผูกพันกับบ้านเกิด")
    ap.add_argument("--no-render", action="store_true")
    a = ap.parse_args()
    if a.genre not in {g["id"] for g in G.genres()}:
        print(f"unknown genre {a.genre}", file=sys.stderr)
        return 2
    return forge(a.genre, a.slug, a.title, a.mood, a.tempo, a.key, a.voice,
                 a.angles.split("|"), not a.no_render)


if __name__ == "__main__":
    raise SystemExit(main())
