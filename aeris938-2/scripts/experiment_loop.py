#!/usr/bin/env python3
"""The daily review loop: on a flat day, choose ONE new experiment and remember it.

K, 2026-11-09: "Each day, if there is no movement — followers do not increase —
we must search for data and hold a meeting to analyse it, then find a way to
adjust what we do. Look at competitors: how do THEY attract followers? We must
keep experimenting until we find the point that works."

`goal_watch.py` already names the constraint each day (reach / conversion /
offer / income). This module is the missing *response*: it turns that diagnosis
into a decision, records the experiment, and refuses to repeat a loser. The
design is the 2026-11-09 advisor panel's (duck + pollinations, quorum PASS):

  * If an experiment is already RUNNING and inside its evaluation window, keep it
    — update its metrics and wait. A flat day is a signal to *review*, not
    permission to switch: a tiny audience needs more exposure before a verdict.
  * If no experiment is running (or the last one reached its window), pick ONE
    new hypothesis that (a) matches the diagnosed constraint, (b) is not a
    duplicate of anything already tried, and (c) differs from a failed test by a
    real variable, not a synonym.
  * Record it with the fields that let tomorrow's run reason about it:
    id, hypothesis, constraint, peer evidence, the single changed variable,
    baseline, start/end, exposure threshold, primary + guardrail metric, result.

Why a ledger and not prose: a rule that lives only in a document gets skipped.
The ledger is read back on every run, so the loop cannot "forget" and re-try a
loser — the 2026-11-06 panel's lesson (a gate the worker cannot bypass).

    python3 scripts/experiment_loop.py --plan      # decide, print, do not write
    python3 scripts/experiment_loop.py --run       # decide and record
    python3 scripts/experiment_loop.py --status    # the ledger so far
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import sys
import time
import urllib.request
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import surfaces  # noqa: E402
import goal_watch  # noqa: E402

WORK = surfaces.WORK
LEDGER = WORK / "experiments.jsonl"
STATE = WORK / "experiment-state.json"

# A hypothesis is a duplicate of a past one when this share of its content words
# is shared. 0.6 is the panel's suggestion: high enough that a genuine re-test
# with a new variable passes, low enough that a reworded loser is caught.
DUP_THRESHOLD = 0.6
# How long a test runs before it is judged. Shorts reach is fast, so a fortnight
# is the panel's window; below the exposure threshold the outcome is INCONCLUSIVE,
# never a loss.
WINDOW_DAYS = 14.0
# Below this many views on the tested videos the result cannot be read as a loss.
EXPOSURE_FLOOR = 200

# The hypothesis library, keyed by the constraint `goal_watch` names. Each entry
# is a real, free, in-repo experiment with the ONE variable it changes, the peer
# evidence that motivated it, and how it is judged. The loop walks the list in
# order and takes the first that is neither done nor a duplicate. Order is the
# panel's priority: the first Shorts-framing test is first because YouTube's own
# data says Shorts drove >50% of new subscribers for active artists.
LIBRARY: dict[str, list[dict]] = {
    "reach": [
        {
            "key": "shorts-hook-framing",
            "title": "ทดลอง 3 hook ต่างกันจากเพลงเดียว วัดวิว/ซับต่อคลิป",
            "variable": "หน้าจอเปิดของ Short (บรรทัดร้องแรก vs คำถาม vs อารมณ์)",
            "hypothesis": ("Shorts ที่เปิดด้วยบรรทัดร้องแรกของท่อน จะได้วิวมากกว่า "
                           "การ์ดคำถาม เพราะคนอ่าน/ร้องตามได้ทันที"),
            "peer": "YouTube: Shorts คิดเป็น >50% ของซับใหม่ของศิลปินที่เล่น Shorts",
            "metric": "วิวเฉลี่ยต่อ Short + ซับที่ได้ต่อ Short",
            "guardrail": "อัตราการกดข้าม (ถ้าดูไม่จบ คลิปนั้นแย่ลง)",
        },
        {
            "key": "shorts-duration",
            "title": "ทดลองความยาว Short 15s vs 30s vs 60s",
            "variable": "ความยาวของ Short",
            "hypothesis": ("Short 15s ที่มี hook เดียว จะดูจบสูงกว่าและถูกดันมากกว่า "
                           "Short 60s ที่ยัดหลายท่อน"),
            "peer": "ช่องเพลงไทยที่โต ใช้ Short สั้นท่อนเดียวซ้ำ ๆ",
            "metric": "อัตราดูจบ + วิวต่อ Short",
            "guardrail": "วิวที่พาไปหาคลิปยาว (ถ้าหายหมด = ไม่ดี)",
        },
        {
            "key": "search-intent-title",
            "title": "ทดลองตั้งชื่อตามเจตนาค้นหา (อารมณ์/โอกาส) แทนชื่อเพลงเปล่า",
            "variable": "รูปแบบชื่อวิดีโอ",
            "hypothesis": ("ชื่อที่บอกอารมณ์/โอกาส (เพลงเศร้าฟังก่อนนอน) จะถูกค้นหา "
                           "มากกว่าชื่อเพลงล้วน"),
            "peer": "คู่แข่งใช้ชื่อยาวแบบมีคำอารมณ์/โอกาสนำ",
            "metric": "วิวจาก Search + วิวต่อวิดีโอ",
            "guardrail": "อัตราคลิกจากหน้าแรก (ถ้าตกทั้งที่วิวขึ้น = ได้วิวผิดกลุ่ม)",
        },
    ],
    "conversion": [
        {
            "key": "sing-along-karaoke",
            "title": "นำด้วยคาราโอเกะร้องตาม + เนื้อขึ้นจอ",
            "variable": "รูปแบบคลิป (คาราโอเกะ vs ครอปปก)",
            "hypothesis": ("คลิปที่ร้องตามได้ จะได้คนติดตามมากกว่า เพราะมีเหตุผลกลับมาซ้ำ "
                           "(มาฝึกร้อง/มาฟังท่อนที่ชอบ)"),
            "peer": "เพลงไทยที่คนร้องตามได้ โตด้วยคาราโอเกะ",
            "metric": "ซับต่อ 1,000 วิว",
            "guardrail": "อัตราดูจบ (คาราโอเกะที่ดูไม่จบ = ไม่ช่วย)",
        },
        {
            "key": "series-promise",
            "title": "สร้างซีรีส์ประจำ (เช่น ลูกทุ่งเศร้าทุกวันศุกร์) พร้อมป้ายซีรีส์",
            "variable": "คำสัญญาซีรีส์บนหน้าคลิป",
            "hypothesis": ("การมีซีรีส์ที่ออกสม่ำเสมอ ให้เหตุผลกดติดตาม เพราะรู้ว่าจะได้อะไรต่อ"),
            "peer": "ช่องที่โตมีเพลย์ลิสต์/ซีรีส์ประจำ",
            "metric": "ซับต่อ 1,000 วิว + จำนวนวิวเพลย์ลิสต์",
            "guardrail": "อัตราดูจบ (ถ้าซีรีส์ทำให้ซ้ำซาก คนหนี)",
        },
    ],
    "offer": [
        {
            "key": "longform-buying-guide",
            "title": "คลิปยาว '5 ของน่าซื้อ' มีบทต่อสินค้า ลิงก์ในคำอธิบาย",
            "variable": "วางลิงก์ในคลิปยาวที่มีบท แทน Short",
            "hypothesis": ("คำอธิบายคลิปยาวกดได้และอยู่เหนือเฟรม การวางลิงก์ตรงนั้นจะได้คลิก "
                           "มากกว่า Short ที่ลิงก์อยู่ใต้เฟรม"),
            "peer": "ช่องที่ขาย affiliate ได้ ใช้คลิปยาวรีวิวเป็นหลัก",
            "metric": "คลิก Shopee ต่อ 1,000 วิว",
            "guardrail": "ซับ/วิวไม่ตก (คลิปขายต้องไม่ทำลายช่องเพลง)",
        },
        {
            "key": "product-fit-listening-gear",
            "title": "เปลี่ยนสินค้าให้ตรงกับคนฟังเพลง (หูฟัง/ลำโพง) แบบเฉพาะเจาะจง",
            "variable": "ตัวสินค้า/หมวดที่ลิงก์ไป",
            "hypothesis": ("สินค้าที่เกี่ยวกับการฟังเพลงโดยตรง จะได้คลิกมากกว่าสินค้าทั่วไป "
                           "เพราะคนดูเพลงกำลังหาอุปกรณ์ฟังอยู่แล้ว"),
            "peer": "ช่องเพลงที่ขายของ มักขายหูฟัง/ลำโพง/ไมค์",
            "metric": "คลิก Shopee ต่อ 1,000 วิว",
            "guardrail": "คำสั่งซื้อจริง (คลิกเยอะแต่ออเดอร์ศูนย์ = ยังไม่พอ)",
        },
    ],
    "income": [
        {
            "key": "scale-winning-video",
            "title": "ขยายวิดีโอที่ทำเงินได้ (ทำหลายเวอร์ชัน/โปรโมตต่อ)",
            "variable": "ปริมาณที่ลงทุนกับวิดีโอที่ชนะ",
            "hypothesis": ("เมื่อมีคลิกที่แปลงได้แล้ว การทำเวอร์ชันเพิ่มของสิ่งที่ชนะ "
                           "จะได้ผลมากกว่าลองของใหม่"),
            "peer": "ช่องที่ทำเงินได้ ลงทุนซ้ำกับสิ่งที่ชนะ",
            "metric": "ค่าคอมต่อสัปดาห์",
            "guardrail": "ต้นทุนเวลา (ฟรีเท่านั้น ห้ามจ่ายเงิน)",
        },
    ],
}


def _now() -> str:
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


def load_ledger(path: Path | None = None) -> list[dict]:
    p = path or LEDGER
    if not p.exists():
        return []
    rows = []
    for line in p.read_text(encoding="utf-8").splitlines():
        line = line.strip()
        if not line:
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def _words(s: str) -> set[str]:
    import re
    return {w for w in re.findall(r"[0-9a-zA-Z\u0e00-\u0e7f]+", s.lower())
            if len(w) > 1}


def similarity(a: str, b: str) -> float:
    """Jaccard similarity of two hypotheses' content words."""
    wa, wb = _words(a), _words(b)
    if not wa or not wb:
        return 0.0
    return len(wa & wb) / len(wa | wb)


def is_duplicate(cand: dict, past: list[dict]) -> dict | None:
    """Return the past experiment this candidate repeats, or None.

    Two ways to be a duplicate: the same library key, or a hypothesis whose words
    overlap past the threshold. The key check catches the same experiment re-picked
    from the library; the similarity check catches a reworded version.
    """
    for p in past:
        if p.get("key") and p["key"] == cand.get("key"):
            return p
        if similarity(cand.get("hypothesis", ""), p.get("hypothesis", "")) >= DUP_THRESHOLD:
            return p
    return None


def _age_days(exp: dict) -> float:
    try:
        start = datetime.fromisoformat(exp["start"].replace("Z", "+00:00"))
    except Exception:  # noqa: BLE001
        return 0.0
    return (datetime.now(timezone.utc) - start).total_seconds() / 86400.0


def active_experiment(rows: list[dict]) -> dict | None:
    """The experiment that is still inside its evaluation window, if any."""
    for exp in reversed(rows):
        if exp.get("status") == "RUNNING" and _age_days(exp) < WINDOW_DAYS:
            return exp
        if exp.get("status") == "RUNNING":
            return exp  # window elapsed; the caller will close it
    return None


def pick(constraint: str, rows: list[dict]) -> dict | None:
    """The first library experiment for this constraint not already tried."""
    for cand in LIBRARY.get(constraint, []):
        if not is_duplicate(cand, rows):
            return cand
    return None


def evaluate(exp: dict, rows: list[dict]) -> tuple[str, str]:
    """Judge a finished experiment from the metrics history.

    The panel was explicit: do not call a test a loss before its exposure
    threshold. So the verdict is:
      * WIN — the primary goal metric (subscribers, then commission) rose during
        the window;
      * INCONCLUSIVE — the goal metric is flat but there was too little exposure
        to read it as a failure (a tiny channel needs views before a verdict);
      * FAILED — exposure was above the floor and the goal metric still did not
        move.
    The experiment's own before/after is the history slice between its start and
    now; the baseline recorded at pick time anchors it.
    """
    try:
        start = datetime.fromisoformat(exp["start"].replace("Z", "+00:00"))
    except Exception:  # noqa: BLE001
        start = None
    after = [r for r in rows if _row_at(r) and start and _row_at(r) >= start]
    if len(after) < 2:
        return "INCONCLUSIVE", "ข้อมูลไม่พอในช่วงทดลอง — ปิดเป็น inconclusive"
    base = after[0]
    last = after[-1]

    def delta(key):
        a, b = base.get(key), last.get(key)
        if isinstance(a, (int, float)) and isinstance(b, (int, float)):
            return b - a
        return None

    d_subs = delta("yt_subs")
    d_comm = delta("sp_commission")
    d_clicks = delta("sp_clicks")
    d_views = delta("yt_views")
    exposure = d_views if isinstance(d_views, (int, float)) else 0

    if (d_comm or 0) > 0:
        return "WIN", f"ค่าคอมเพิ่ม {d_comm:g} — สิ่งที่ทำได้ผล"
    if (d_subs or 0) > 0:
        return "WIN", f"ซับเพิ่ม {d_subs:g} ในหน้าต่างทดลอง — สิ่งที่ทำได้ผล"
    if exposure < exp.get("exposure_floor", EXPOSURE_FLOOR):
        return ("INCONCLUSIVE",
                f"วิวเพิ่มแค่ {exposure:g} (ต่ำกว่าพื้น "
                f"{exp.get('exposure_floor', EXPOSURE_FLOOR)}) — หลักฐานไม่พอ "
                "ตัดสิน ยังไม่นับเป็นแพ้")
    return "FAILED", (f"วิวเพิ่ม {exposure:g} แต่ซับไม่ขยับ — "
                      "สมมติฐานนี้ไม่พาคนติดตาม")


def _row_at(row: dict) -> datetime | None:
    try:
        return datetime.fromisoformat(str(row["at"]).replace("Z", "+00:00"))
    except Exception:  # noqa: BLE001
        return None


def decide(rows: list[dict], constraint: str, history: list[dict] | None = None) -> dict:
    """The one decision for today: keep, close, or start.

    Order follows the panel: never switch away from a running test before its
    window (a flat day is a review, not a reason to churn); once the window is
    done, close it, judge it from the metrics, and pick the next untried
    experiment for the constraint.
    """
    act = active_experiment(rows)
    if act and act.get("status") == "RUNNING" and _age_days(act) < WINDOW_DAYS:
        return {"action": "keep", "experiment": act,
                "why": (f"การทดลอง '{act['key']}' ยังอยู่ในหน้าต่างประเมิน "
                        f"({_age_days(act):.1f}/{WINDOW_DAYS:.0f} วัน) — "
                        "วันนี้เก็บข้อมูลต่อ ไม่สลับ (คนดูน้อยต้องให้เวลาก่อนตัดสิน)")}
    if act and act.get("status") == "RUNNING":
        closed = dict(act)
        status, result = evaluate(act, history or [])
        closed["status"] = status
        closed["end"] = _now()
        closed["result"] = result
        nxt = pick(constraint, rows)
        if not nxt:
            return {"action": "exhausted", "close": closed,
                    "why": "ปิดการทดลองเดิม แต่คลังสมมติฐานของคอนสตรนต์นี้ใช้หมดแล้ว"}
        return {"action": "start", "close": closed, "experiment": nxt,
                "why": f"หน้าต่างประเมินครบ — ปิดของเดิม ({status}) แล้วเปิดสมมติฐานใหม่"}

    nxt = pick(constraint, rows)
    if not nxt:
        return {"action": "exhausted",
                "why": (f"ไม่มีสมมติฐานใหม่สำหรับคอนสตรนต์ '{constraint}' — "
                        "ทุกตัวถูกลองแล้ว ต้องให้ที่ปรึกษาคิดชุดใหม่")}
    return {"action": "start", "experiment": nxt,
            "why": f"ยังไม่มีการทดลองที่รันอยู่ — เปิดสมมติฐานแรกของ '{constraint}'"}


def _new_id(key: str) -> str:
    stamp = time.strftime("%Y%m%d", time.gmtime())
    h = hashlib.sha1(f"{key}{time.time()}".encode()).hexdigest()[:4]
    return f"exp-{stamp}-{key}-{h}"


def record(cand: dict, constraint: str, peer_scan: dict | None) -> dict:
    return {
        "id": _new_id(cand["key"]),
        "key": cand["key"],
        "title": cand["title"],
        "hypothesis": cand["hypothesis"],
        "constraint": constraint,
        "variable": cand["variable"],
        "peer": cand["peer"],
        "peer_scan_at": (peer_scan or {}).get("at"),
        "metric": cand["metric"],
        "guardrail": cand["guardrail"],
        "window_days": WINDOW_DAYS,
        "exposure_floor": EXPOSURE_FLOOR,
        "baseline": (peer_scan or {}).get("baseline"),
        "start": _now(),
        "end": None,
        "status": "RUNNING",
        "result": None,
    }


def peer_scan(handle: str = "@aerismusicth", peers: list[str] | None = None) -> dict:
    """A free read of our own + peer channels, to anchor the experiment.

    Uses `ops/yt_public_scan.py` (no API quota). Best effort: a network failure
    returns an empty dict so the loop still decides from the library.
    """
    out: dict = {"at": _now(), "peers": []}
    try:
        sys.path.insert(0, str(surfaces.OPS))
        import yt_public_scan as scan  # noqa: E402
    except Exception as e:  # noqa: BLE001
        return {"at": _now(), "peers": [], "error": f"scanner unavailable: {e}"}
    targets = [handle] + list(peers or [])
    for h in targets:
        try:
            ch = scan.channel_videos(h)
            s = scan.summarise(ch)
            out["peers"].append({"handle": h, "subs": s.get("subs"),
                                 "scanned": s.get("scanned"),
                                 "median_views": s.get("median_views"),
                                 "longform": s.get("longform"),
                                 "shorts": s.get("shorts"),
                                 "mean_title_chars": s.get("mean_title_chars")})
        except Exception as e:  # noqa: BLE001
            out["peers"].append({"handle": h, "error": str(e)[:120]})
    mine = next((p for p in out["peers"] if p["handle"] == handle), {})
    out["baseline"] = {"subs": mine.get("subs"), "median_views": mine.get("median_views")}
    return out


def render(decision: dict, scan: dict | None = None) -> str:
    lines = ["# ลูปทดลองรายวัน — AERIS Music", "",
             f"ตัดสินเมื่อ: {_now()}", ""]
    act = decision["action"]
    if act == "keep":
        e = decision["experiment"]
        lines += [f"**คงการทดลองเดิม:** {e['title']}",
                  f"- ตัวแปรที่ทดลอง: {e['variable']}",
                  f"- วัดที่: {e['metric']} (guardrail: {e['guardrail']})",
                  f"- เหตุผล: {decision['why']}"]
    elif act in ("start",):
        if decision.get("close"):
            lines += [f"**ปิดการทดลองเดิม:** {decision['close']['key']} → "
                      f"{decision['close']['status']}", ""]
        e = decision["experiment"]
        lines += [f"**เปิดการทดลองใหม่:** {e['title']}",
                  f"- สมมติฐาน: {e['hypothesis']}",
                  f"- ตัวแปรเดียวที่เปลี่ยน: {e['variable']}",
                  f"- หลักฐานคู่แข่ง: {e['peer']}",
                  f"- วัดที่: {e['metric']} (guardrail: {e['guardrail']})",
                  f"- หน้าต่าง: {e.get('window_days', WINDOW_DAYS):.0f} วัน, "
                  f"พื้นวิว {e.get('exposure_floor', EXPOSURE_FLOOR)}",
                  f"- เหตุผล: {decision['why']}"]
    elif act == "exhausted":
        lines += [f"**คลังสมมติฐานหมดสำหรับคอนสตรนต์นี้** — {decision['why']}",
                  "ต้องให้ที่ปรึกษา (consult.py) คิดชุดสมมติฐานใหม่"]
    if scan:
        lines += ["", "## สัญญาณคู่แข่ง (สแกนฟรี ไม่ใช้ quota)"]
        for p in scan.get("peers", []):
            if p.get("error"):
                lines.append(f"- {p['handle']}: อ่านไม่ได้ ({p['error']})")
            else:
                lines.append(f"- {p['handle']}: {p.get('subs')} ซับ, "
                             f"{p.get('scanned')} คลิป, median {p.get('median_views')} วิว")
    return "\n".join(lines)


def push(text: str, topic: str) -> None:
    try:
        req = urllib.request.Request(
            f"https://ntfy.sh/{topic}", data=text.encode("utf-8"),
            headers={"Title": "AERIS Music — ลูปทดลอง", "Tags": "test_tube"})
        urllib.request.urlopen(req, timeout=20).read()
        print("ntfy: pushed")
    except Exception as e:  # noqa: BLE001
        print(f"ntfy: failed ({e}) — non-fatal")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--plan", action="store_true", help="decide and print only")
    ap.add_argument("--run", action="store_true", help="decide and record")
    ap.add_argument("--status", action="store_true", help="print the ledger")
    ap.add_argument("--constraint", help="override the diagnosed constraint")
    ap.add_argument("--no-scan", action="store_true", help="skip the peer scan")
    ap.add_argument("--no-push", action="store_true")
    args = ap.parse_args(argv)

    rows = load_ledger()
    if args.status:
        for e in rows:
            print(f"{e.get('start','?')[:10]}  {e.get('status','?'):12} "
                  f"{e.get('key','?'):24} {e.get('title','')}")
        return 0

    diag = goal_watch.diagnose(goal_watch.load())
    constraint = args.constraint or diag.get("constraint", "reach")
    scan = None if args.no_scan else peer_scan()
    decision = decide(rows, constraint, goal_watch.load())
    text = render(decision, scan)
    print(text)

    if not args.run:
        print("\n(dry run — pass --run to record)")
        return 0

    new_rows = list(rows)
    if decision.get("close"):
        closed = decision["close"]
        new_rows = [closed if r.get("id") == closed["id"] else r for r in new_rows]
    if decision.get("experiment") and decision["action"] == "start":
        rec = record(decision["experiment"], constraint, scan)
        new_rows.append(rec)
        print(f"\nrecorded: {rec['id']}")
    LEDGER.write_text(
        "\n".join(json.dumps(r, ensure_ascii=False) for r in new_rows) + "\n",
        encoding="utf-8")
    STATE.write_text(json.dumps(
        {"at": _now(), "constraint": constraint, "action": decision["action"]},
        ensure_ascii=False, indent=1), encoding="utf-8")

    if not args.no_push:
        topic = os.environ.get("AX_NTFY_TOPIC", "")
        if topic:
            e = decision.get("experiment") or decision.get("close") or {}
            push(f"ลูปทดลอง: {decision['action']} | คอขวด {constraint} | "
                 f"{e.get('title','')}", topic)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
