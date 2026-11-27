"""AR's world map: the whole territory on one page, from numbers already on disk.

K handed the map over (2026-11-27). A map is only worth having if it is drawn from
measurements, so every line here comes from a file or a live API read — never from
memory of what the state "should" be. A field that cannot be read says so.

The four levels are the game, in the order they must be cleared:

- **L1 identity**  — each surface exists and is readable.
- **L2 seen**      — the median video is watched by more than a rounding error.
- **L3 followed**  — 1,000 subscribers and 4,000 watch-hours.
- **L4 revenue**   — $500.

`--write` puts `WORLD-MAP.md` and `world-map.html` in the repo root.
"""
from __future__ import annotations

import argparse
import json
import sys
from datetime import datetime, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(ROOT / "ops"))
sys.path.insert(0, str(ROOT / "music938-1" / "scripts"))

WORK = ROOT / "music938-1" / "work"
AUDITS = ROOT / "ops" / "audits"
BANK = ROOT / "music938-1" / "library" / "bank"

L2_MEDIAN_VIEWS = 50
L3_SUBS = 1000
L3_HOURS = 4000
L4_USD = 500


def latest_audit() -> dict:
    files = sorted(AUDITS.glob("yt-audit-*.json"))
    if not files:
        return {}
    try:
        return json.loads(files[-1].read_text(encoding="utf-8"))
    except (OSError, ValueError):
        return {}


def youtube() -> dict:
    a = latest_audit()
    if not a:
        return {"read": False, "note": "no audit on disk yet"}
    t = a.get("totals", {})
    m = a.get("median_all", {})
    return {
        "read": True,
        "date": a.get("generated", "")[:10],
        "uploads": a.get("uploads"),
        "public": a.get("public"),
        "views": t.get("views"),
        "shorts": t.get("shorts"),
        "long": t.get("long"),
        "median_views": m.get("views"),
        "median_views_per_day": m.get("views_per_day"),
    }


def facebook() -> dict:
    try:
        import fb_graph  # noqa: PLC0415
    except Exception as exc:  # noqa: BLE001
        return {"read": False, "note": f"import failed: {exc}"}
    if not fb_graph.available():
        return {"read": False, "note": "no FB_PAGE_TOKEN in this environment"}
    ins = fb_graph.page_insights()
    if not ins.get("reachable"):
        return {"read": False, "note": ins.get("note", "unreachable")}
    fields = fb_graph.page_fields() or {}
    return {
        "read": True,
        "name": fields.get("name"),
        "about_set": bool((fields.get("about") or "").strip()),
        "followers": ins.get("followers"),
        "views_28d": ins.get("views_28d"),
        "engagements_28d": ins.get("engagements_28d"),
    }


def tiktok() -> dict:
    import os  # noqa: PLC0415
    return {
        "read": True,
        "token": bool(os.environ.get("TIKTOK_ACCESS_TOKEN")),
        "policy_email": bool(os.environ.get("TT_POLICY_EMAIL")),
        "blocked_by": "" if os.environ.get("TT_POLICY_EMAIL") else "TT_POLICY_EMAIL not set",
    }


def shopee() -> dict:
    """The affiliate link the copy actually carries, and whether it is tracked."""
    try:
        import monetize  # noqa: PLC0415
    except Exception as exc:  # noqa: BLE001
        return {"read": False, "note": f"import failed: {exc}"}
    try:
        link = monetize.link("youtube")
    except Exception as exc:  # noqa: BLE001
        return {"read": False, "note": f"no link: {exc}"}
    return {"read": True, "link": link, "tracked": "sub_id=" in link}


def inventory() -> dict:
    import bank_publish as bp  # noqa: PLC0415
    import compass  # noqa: PLC0415

    songs = compass.songs("bank")
    ledger = bp.load_choruses()
    clips = sorted(BANK.glob("*.mp4"))
    unused_songs = [s for s in songs if not any(k.startswith(f"{s}#") for k in ledger)]
    pending = [c for c in clips if bp.chorus_blocked(c, ledger, "youtube") == ""]
    return {
        "masters": len(songs),
        "clips_in_bank": len(clips),
        "choruses_published": len(ledger),
        "songs_never_used": unused_songs,
        "clips_waiting": [c.name for c in pending],
    }


def levels(yt: dict, fb: dict) -> list[dict]:
    l1 = (yt.get("uploads") or 0) > 0 and fb.get("read") and fb.get("about_set")
    median = yt.get("median_views")
    l2 = isinstance(median, (int, float)) and median >= L2_MEDIAN_VIEWS
    return [
        {"level": "L1 identity", "target": "every surface exists and is readable",
         "passed": bool(l1), "now": f"YT {yt.get('uploads', '?')} uploads · FB {'read' if fb.get('read') else 'unread'}"},
        {"level": "L2 seen", "target": f"median video >= {L2_MEDIAN_VIEWS} views",
         "passed": bool(l2), "now": f"median {median if median is not None else '?'} views/video"},
        {"level": "L3 followed", "target": f"{L3_SUBS:,} subs and {L3_HOURS:,} watch-hours",
         "passed": False, "now": "not measured — needs the Analytics read"},
        {"level": "L4 revenue", "target": f"${L4_USD}",
         "passed": False, "now": "gated behind L3 (the revenue gate is ch3)"},
    ]


def blocked(fb: dict, tt: dict) -> list[str]:
    out = []
    if not tt["policy_email"]:
        out.append("TikTok: `TT_POLICY_EMAIL` is unset — no policy email, no publish (K's order).")
    if not fb.get("read"):
        out.append(f"Facebook: numbers unreadable here ({fb.get('note', '')}).")
    out.append("YouTube long-form 90–600 s: refused by `clip_standard.duration_verdict()` "
               "unless the slug is in `channel/special-releases.json` (max 2/quarter).")
    out.append("Vol.4: held until 2026-12-15 or five new songs, whichever first.")
    return out


def render(md_path: Path, html_path: Path) -> dict:
    yt, fb, tt, sp = youtube(), facebook(), tiktok(), shopee()
    inv = inventory()
    lv = levels(yt, fb)
    bl = blocked(fb, tt)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%d %H:%MZ")

    lines = [f"# AR — world map ({now})", "",
             "Every number below was read from a file or an API at the time above. "
             "An unreadable field says so; nothing here is inferred.", "",
             "## Levels", "", "| level | target | now | cleared |", "| --- | --- | --- | --- |"]
    for row in lv:
        lines.append(f"| {row['level']} | {row['target']} | {row['now']} | {'✅' if row['passed'] else '—'} |")

    lines += ["", "## Surfaces", "", "| surface | state |", "| --- | --- |"]
    lines.append("| YouTube @aerismusicth | " + (
        f"{yt['uploads']} uploads, {yt['views']} views, median {yt['median_views']}/video "
        f"({yt['median_views_per_day']}/day) — audit {yt['date']}" if yt.get("read")
        else yt.get("note", "unread")) + " |")
    lines.append("| Facebook Page | " + (
        f"{fb.get('followers')} followers, {fb.get('views_28d')} views/28d, "
        f"{fb.get('engagements_28d')} engagements/28d" if fb.get("read")
        else fb.get("note", "unread")) + " |")
    lines.append("| TikTok | " + (
        "ready" if tt["policy_email"] else f"blocked: {tt['blocked_by']}") + " |")
    lines.append("| Shopee | " + (
        f"{'tracked' if sp.get('tracked') else 'plain'} link {sp.get('link')}"
        if sp.get("read") else sp.get("note", "unread")) + " |")

    lines += ["", "## Inventory", "",
              f"- publishable masters: **{inv['masters']}**",
              f"- clips in the bank: **{inv['clips_in_bank']}** ({len(inv['clips_waiting'])} waiting)",
              f"- choruses published: **{inv['choruses_published']}**",
              f"- songs never used: {', '.join(inv['songs_never_used']) or 'none'}"]

    lines += ["", "## Blocked, and by what", ""] + [f"- {b}" for b in bl]
    md = "\n".join(lines) + "\n"
    md_path.write_text(md, encoding="utf-8")

    rows = "".join(
        f"<tr class='{ 'ok' if r['passed'] else 'no' }'><td>{r['level']}</td>"
        f"<td>{r['target']}</td><td>{r['now']}</td><td>{'cleared' if r['passed'] else 'open'}</td></tr>"
        for r in lv)
    html = f"""<!doctype html><meta charset="utf-8">
<title>AR world map</title>
<style>
body{{font:16px/1.6 system-ui,sans-serif;background:#0e1116;color:#e6e9ef;margin:0;padding:32px}}
h1{{font-size:26px;margin:0 0 4px}} .sub{{color:#8b94a7;margin-bottom:24px}}
table{{border-collapse:collapse;width:100%;margin:12px 0 28px}}
th,td{{text-align:left;padding:8px 10px;border-bottom:1px solid #232a36;vertical-align:top}}
th{{color:#8b94a7;font-weight:600;font-size:13px;text-transform:uppercase;letter-spacing:.06em}}
tr.ok td:last-child{{color:#3ddc97}} tr.no td:last-child{{color:#f2b544}}
ul{{padding-left:18px}} li{{margin:4px 0}} code{{background:#171c25;padding:1px 5px;border-radius:4px}}
</style>
<h1>AR — world map</h1><div class="sub">{now} · read, not remembered</div>
<table><tr><th>level</th><th>target</th><th>now</th><th>state</th></tr>{rows}</table>
<pre style="background:#171c25;padding:16px;border-radius:8px;overflow:auto">{md.split('## Surfaces')[1].split('## Inventory')[0] if '## Surfaces' in md else ''}</pre>
"""
    html_path.write_text(html, encoding="utf-8")
    return {"levels": lv, "youtube": yt, "facebook": fb, "tiktok": tt,
            "shopee": sp, "inventory": inv, "blocked": bl}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--write", action="store_true", help="write WORLD-MAP.md and world-map.html")
    ap.add_argument("--json", action="store_true", help="print the map as JSON")
    a = ap.parse_args(argv)
    data = render(ROOT / "WORLD-MAP.md", ROOT / "world-map.html")
    if a.json:
        print(json.dumps(data, ensure_ascii=False, indent=1))
    else:
        for row in data["levels"]:
            print(f"{'OK ' if row['passed'] else '   '}{row['level']:<12} {row['now']}")
        print(f"inventory: {data['inventory']['masters']} masters, "
              f"{data['inventory']['clips_in_bank']} clips, "
              f"{len(data['inventory']['songs_never_used'])} songs never used")
        if a.write:
            print("wrote WORLD-MAP.md and world-map.html")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
