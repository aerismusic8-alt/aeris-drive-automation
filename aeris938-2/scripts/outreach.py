#!/usr/bin/env python3
"""Grow the Facebook Page by following and inviting, with no paid tools.

K's rule (2026-11-03): a Page does not need a friend list to grow. Facebook
shows suggested pages, so the free loop is

  * follow pages in the Page's niche — they often follow back, and
  * invite the personal profile's friends to like the Page.

Both run as the signed-in Page on the cloud desktop, which is the only free
route (Rule #1 — free only). Nothing here spends money.

A fresh Page that follows five hundred accounts in a minute gets rate-limited or
banned, so this is deliberately slow: a per-run `--limit` and a `--min-gap`
between actions, plus a daily cap. Every action is written to
`work/outreach-state.json` so a page is never followed twice, and a re-run
resumes instead of repeating.

Usage:
    python3 scripts/outreach.py --plan            # what would happen now
    python3 scripts/outreach.py --follow --limit 5
    python3 scripts/outreach.py --invite
    python3 scripts/outreach.py --status
"""
from __future__ import annotations

import argparse
import json
import sys
import time
from pathlib import Path

import surfaces

ROOT = surfaces.ROOT
sys.path.insert(0, str(surfaces.music_scripts()))
sys.path.insert(0, str(surfaces.REPO / "aeris938-1" / "scripts"))

import browser as B  # noqa: E402

WORK = surfaces.WORK
STATE = WORK / "outreach-state.json"

# The Page the growth points at (Meta asset id used by the Reels rail).
PAGE_ID = "61595890900382"
PAGE_ASSET_ID = "1349201551618019"

# Suggested-pages directory. It renders a "แนะนำสำหรับคุณ" grid of Pages with a
# Follow button each, and it is where the Page identity can follow from.
SUGGEST = f"https://www.facebook.com/pages/?category=invite&page_id={PAGE_ID}"
INVITE = f"https://www.facebook.com/{PAGE_ID}/follower_invite/"

FOLLOW_TEXT = "ติดตาม"          # Follow
FOLLOWING_TEXT = "กำลังติดตาม"  # Following
INVITE_ALL = "เลือกทั้งหมด"     # Select all
INVITE_SEND = "ส่งคำเชิญ"       # Send invites
INVITE_NONE = "ไม่มีเพื่อนให้เชิญ"

# Pace. A human does not follow 40 pages in a row, and Facebook notices when one
# does, so the defaults stay small and the gap stays real.
DAILY_CAP = 40
MIN_GAP_SECONDS = 8


# --- state -------------------------------------------------------------------

def load_state() -> dict:
    if STATE.exists():
        return json.loads(STATE.read_text(encoding="utf-8"))
    return {"followed": {}, "invited": {}}


def save_state(state: dict) -> None:
    STATE.parent.mkdir(parents=True, exist_ok=True)
    STATE.write_text(json.dumps(state, ensure_ascii=False, indent=2) + "\n",
                     encoding="utf-8")


def _today() -> str:
    return time.strftime("%Y-%m-%d", time.gmtime())


def _follows_today(state: dict) -> int:
    day = _today()
    return sum(1 for v in state.get("followed", {}).values()
               if str(v.get("at", "")).startswith(day))


# --- desktop -----------------------------------------------------------------

def _connect():
    from playwright.sync_api import sync_playwright
    return sync_playwright()


def _follow_cards(page) -> list[dict]:
    """Return [{name, index}] for each not-yet-followed card on the grid.

    Read-only: it only inspects the DOM, so `--plan` can run it safely.
    """
    return page.evaluate(
        """(followText) => {
          const out = [];
          const buttons = [...document.querySelectorAll('[role=button]')];
          buttons.forEach((b) => {
            if ((b.innerText || '').trim() !== followText) return;
            let node = b, name = '';
            for (let i = 0; i < 8 && node; i++) {
              const txt = (node.innerText || '').split('\\n')
                .map(s => s.trim()).filter(Boolean);
              if (txt.length > 1) { name = txt[0]; break; }
              node = node.parentElement;
            }
            out.push({name: name || '(unknown)'});
          });
          return out;
        }""", FOLLOW_TEXT)


def _click_nth_follow(page, n: int) -> bool:
    """Click the n-th Follow button, skipping the Page's own controls."""
    return page.evaluate(
        """({followText, n}) => {
          const buttons = [...document.querySelectorAll('[role=button]')]
            .filter(b => (b.innerText || '').trim() === followText);
          if (n >= buttons.length) return false;
          const b = buttons[n];
          b.scrollIntoView({block: 'center'});
          const r = b.getBoundingClientRect();
          const opt = {bubbles: true, cancelable: true,
                       clientX: r.x + r.width / 2, clientY: r.y + r.height / 2};
          b.dispatchEvent(new PointerEvent('pointerdown', opt));
          b.dispatchEvent(new MouseEvent('mousedown', opt));
          b.dispatchEvent(new PointerEvent('pointerup', opt));
          b.dispatchEvent(new MouseEvent('mouseup', opt));
          b.dispatchEvent(new MouseEvent('click', opt));
          return true;
        }""", {"followText": FOLLOW_TEXT, "n": n})


def _acting_as_page(page) -> bool:
    """True when the header shows the Page management shell.

    Facebook only offers the page-profile menu (จัดการเพจ) while the Page is the
    acting identity; the personal profile shows the personal rail instead. A
    follow is only a Page follow when this is true, so it is checked, not
    assumed — otherwise the follows quietly land on the personal profile.
    """
    try:
        head = page.inner_text("body")[:600]
    except Exception:  # noqa: BLE001
        return False
    return "จัดการเพจ" in head


def _switch_to_page(page) -> bool:
    """Make the Page the acting identity, and prove it stuck.

    The switch is triggered from the Page profile, and it must be done *before*
    navigating to the follow grid: the grid does not offer the switch, so
    switching after the navigation is a silent no-op.
    """
    page.goto(f"https://www.facebook.com/{PAGE_ID}",
              wait_until="domcontentloaded", timeout=60000)
    page.wait_for_timeout(7000)
    if _acting_as_page(page):
        return True
    for label in ("สลับเลย", "สลับ"):
        try:
            page.get_by_text(label, exact=True).first.click(timeout=4000)
            page.wait_for_timeout(6000)
            if _acting_as_page(page):
                return True
        except Exception:  # noqa: BLE001
            continue
    return _acting_as_page(page)


def _page_following_count(page) -> int | None:
    """Read the Page profile's own 'กำลังติดตาม N' (pages it follows)."""
    try:
        page.goto(f"https://www.facebook.com/{PAGE_ID}",
                  wait_until="domcontentloaded", timeout=60000)
        page.wait_for_timeout(6000)
        import re
        body = page.inner_text("body")
        m = re.search(r"กำลังติดตาม\s*([\d,]+)", body)
        return int(m.group(1).replace(",", "")) if m else None
    except Exception:  # noqa: BLE001
        return None


def cmd_follow(limit: int, min_gap: int, plan: bool) -> int:
    state = load_state()
    today = _follows_today(state)
    budget = min(limit, max(0, DAILY_CAP - today))
    print(f"follows today: {today}/{DAILY_CAP}; this run budget: {budget}")
    if budget <= 0:
        print("daily cap reached; try again tomorrow")
        return 0

    with _connect() as p:
        br, ctx = B.connect(p)
        page = ctx.new_page()
        try:
            if not _switch_to_page(page):
                print("could not make the Page the acting identity; a follow now "
                      "would land on the personal profile, so nothing was done")
                return 1
            before = _page_following_count(page)
            page.goto(SUGGEST, wait_until="domcontentloaded", timeout=60000)
            page.wait_for_timeout(8000)
            print(f"candidate pages on the grid: {len(_follow_cards(page))}")
            done = 0
            while done < budget:
                cards = _follow_cards(page)
                target = next((c for c in cards if c["name"] not in state["followed"]),
                              None)
                if target is None:
                    print("no fresh candidate pages left on the grid")
                    break
                name = target["name"]
                if plan:
                    print(f"  would follow: {name}")
                    state["followed"][name] = {"at": "plan"}  # don't re-list in this run
                    done += 1
                    continue
                # Always click the first remaining Follow button: a followed card
                # leaves the list, so a stored index goes stale after one action.
                if not _click_nth_follow(page, 0):
                    print("could not click a Follow button; stopping")
                    break
                page.wait_for_timeout(2500)
                state["followed"][name] = {"at": time.strftime(
                    "%Y-%m-%dT%H:%M:%SZ", time.gmtime())}
                save_state(state)
                print(f"  followed: {name}")
                done += 1
                if done < budget:
                    time.sleep(min_gap)
            print(f"{'would follow' if plan else 'followed'}: {done}")
            if done and not plan:
                after = _page_following_count(page)
                if before is not None and after is not None:
                    delta = after - before
                    print(f"Page 'กำลังติดตาม': {before} -> {after} (+{delta})")
                    if delta <= 0:
                        print("WARNING: the Page count did not rise — the follows "
                              "may have landed on the personal profile")
        finally:
            page.close()
    return 0


def cmd_invite(plan: bool) -> int:
    state = load_state()
    with _connect() as p:
        br, ctx = B.connect(p)
        page = ctx.new_page()
        try:
            page.goto(INVITE, wait_until="domcontentloaded", timeout=60000)
            page.wait_for_timeout(9000)
            body = page.inner_text("body")
            if INVITE_NONE in body:
                print("no friends available to invite (personal profile has none "
                      "to suggest)")
                return 0
            if plan:
                print("would invite the friends listed on the invite tool")
                return 0
            try:
                page.get_by_role("button", name=INVITE_ALL).first.click(timeout=5000)
                page.wait_for_timeout(2000)
            except Exception:  # noqa: BLE001
                pass
            page.get_by_role("button", name=INVITE_SEND).first.click(timeout=5000)
            page.wait_for_timeout(4000)
            state["invited"][time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())] = {
                "page": PAGE_ID}
            save_state(state)
            print("sent the Page like invites")
        finally:
            page.close()
    return 0


def cmd_status() -> int:
    state = load_state()
    followed = state.get("followed", {})
    print(f"pages followed (all time): {len(followed)}")
    print(f"follows today:             {_follows_today(state)}/{DAILY_CAP}")
    print(f"invite runs:               {len(state.get('invited', {}))}")
    if followed:
        last = sorted(followed.items(), key=lambda kv: kv[1].get("at", ""))[-3:]
        for name, meta in last:
            print(f"  {meta.get('at')}  {name}")
    return 0


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--follow", action="store_true", help="follow suggested pages")
    ap.add_argument("--invite", action="store_true", help="invite friends to like the Page")
    ap.add_argument("--plan", action="store_true", help="show what would happen")
    ap.add_argument("--status", action="store_true", help="counts so far")
    ap.add_argument("--limit", type=int, default=5)
    ap.add_argument("--min-gap", type=int, default=MIN_GAP_SECONDS)
    args = ap.parse_args(argv)

    if args.status:
        return cmd_status()
    if args.invite:
        return cmd_invite(args.plan)
    if args.follow:
        return cmd_follow(args.limit, args.min_gap, args.plan)
    ap.print_help()
    return 2


if __name__ == "__main__":
    raise SystemExit(main())
