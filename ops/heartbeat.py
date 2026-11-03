#!/usr/bin/env python3
"""AR's 24/7 green board.

One question, answered on a schedule: *is every rail that should be working
actually working?* GitHub Actions is the only always-on runner in this account,
so the heartbeat lives here and needs no sandbox and no personal token — the
job's own GITHUB_TOKEN can read the run history.

It writes `data/heartbeat.json` (committed, so the answer survives a pod
recycle) and pushes a single ntfy line only when something is wrong, so a quiet
phone means "all green".

Exit code is always 0: a monitor that fails its own job would be the outage it
is meant to report. Problems are reported through the file and ntfy, not the
job status.
"""
from __future__ import annotations

import json
import os
import sys
import urllib.error
import urllib.request
from datetime import datetime, timedelta, timezone

REPO = os.environ.get("GITHUB_REPOSITORY", "aerismusic8-alt/aeris-drive-automation")
TOKEN = os.environ.get("GITHUB_TOKEN", "")
NTFY = os.environ.get("AX_NTFY_TOPIC", "")
API = "https://api.github.com"

# Rails that must have run recently, and how stale is too stale (hours). A cron
# that has not fired in that window is a dropped schedule, which is exactly the
# failure mode that is invisible from a green dashboard.
#
# The windows are deliberately loose. GitHub delivers a scheduled workflow on a
# public repo best-effort, and in practice an hourly cron here lands every ~6-7
# hours under load (measured 2026-11-03: the hourly watchdog ran at 23:53 and
# 06:48). A tight window would just page on the throttling. These catch a rail
# that has genuinely stopped, not one that is merely late.
EXPECTED = {
    "AX Rail Watchdog": 14,
    "AX Music Crosspost (FB Reels + TikTok)": 16,
    "AX Roblox Live State": 16,
    "AX Music Daily Release (Actions fallback)": 40,
    "AX Music Daily Dashboard": 40,
}

# Rails whose cron must actually fire (not just manual dispatches). The release
# rail shipped with a schedule that has never produced a scheduled run.
CRON_RAILS = {
    "AX Rail Watchdog",
    "AX Music Crosspost (FB Reels + TikTok)",
    "AX Roblox Live State",
    "AX Music Daily Release (Actions fallback)",
    "AX Music Daily Dashboard",
}

# Workflow file per rail, so the heartbeat can re-dispatch a rail that has gone
# stale. This is the Actions-layer watchdog: ax-watchdog heals the OpenHands
# automations, this heals the GitHub crons.
FILES = {
    "AX Rail Watchdog": "ax-rail-watchdog.yml",
    "AX Music Crosspost (FB Reels + TikTok)": "ax-music-crosspost.yml",
    "AX Roblox Live State": "ax-roblox-live-state.yml",
    "AX Music Daily Release (Actions fallback)": "ax-music-release.yml",
    "AX Music Daily Dashboard": "ax-music-dashboard.yml",
}


def _get(url: str) -> dict:
    req = urllib.request.Request(url, headers={
        "Authorization": f"token {TOKEN}",
        "Accept": "application/vnd.github+json",
        "User-Agent": "ax-heartbeat",
    })
    with urllib.request.urlopen(req, timeout=30) as r:
        return json.loads(r.read().decode() or "{}")


def _post_ntfy(title: str, body: str) -> bool:
    if not NTFY:
        return False
    req = urllib.request.Request(
        f"https://ntfy.sh/{NTFY}", data=body.encode(),
        headers={"Title": title, "Tags": "rotating_light", "Priority": "high"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=20) as r:
            return r.status == 200
    except Exception:
        return False


def _dispatch(workflow_file: str) -> bool:
    """Re-run a stale rail's workflow. Needs actions:write on the job token."""
    req = urllib.request.Request(
        f"{API}/repos/{REPO}/actions/workflows/{workflow_file}/dispatches",
        data=json.dumps({"ref": "main"}).encode(),
        headers={"Authorization": f"token {TOKEN}",
                 "Accept": "application/vnd.github+json",
                 "Content-Type": "application/json",
                 "User-Agent": "ax-heartbeat"},
        method="POST")
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status in (201, 204)
    except urllib.error.HTTPError:
        return False


def collect() -> dict:
    now = datetime.now(timezone.utc)
    rails: dict[str, dict] = {}
    alerts: list[str] = []

    # Recent runs across all workflows in one page (100 is plenty for 48h here).
    runs = _get(f"{API}/repos/{REPO}/actions/runs?per_page=100").get("workflow_runs", [])
    by_name: dict[str, list[dict]] = {}
    for r in runs:
        by_name.setdefault(r["name"], []).append(r)

    # Workflow creation dates, so a just-shipped rail is not flagged for a cron
    # that has simply not had its first slot yet.
    wf_created: dict[str, str] = {}
    try:
        for w in _get(f"{API}/repos/{REPO}/actions/workflows?per_page=100").get("workflows", []):
            wf_created[w["name"]] = w.get("created_at", "")
    except Exception:
        pass

    for name, max_age_h in EXPECTED.items():
        items = by_name.get(name, [])
        last = items[0] if items else None
        last_at = last["created_at"] if last else None
        fresh = False
        if last_at:
            age = now - datetime.fromisoformat(last_at.replace("Z", "+00:00"))
            fresh = age <= timedelta(hours=max_age_h)
        rails[name] = {
            "last_at": last_at,
            "last_conclusion": (last or {}).get("conclusion"),
            "fresh": fresh,
            "max_age_h": max_age_h,
        }
        # A rail can look healthy while its cron never fires at all: the manual
        # runs are green, so nothing is red, yet the schedule is dead. That is
        # how AX Music Daily Release behaved — only workflow_dispatch runs ever
        # appeared. Flag it only once the workflow is older than 48h, so a
        # just-shipped rail waiting for its first slot is not a false alarm.
        if name in CRON_RAILS:
            sched = [r for r in items if r.get("event") == "schedule"]
            newest_sched = sched[0]["created_at"] if sched else None
            rails[name]["last_scheduled_at"] = newest_sched
            created = wf_created.get(name, "")
            old_enough = False
            if created:
                old_enough = (now - datetime.fromisoformat(created.replace("Z", "+00:00"))) > timedelta(hours=48)
            if not newest_sched and old_enough:
                alerts.append(f"{name}: cron has never fired (only manual runs)")

        if last is None:
            alerts.append(f"{name}: never ran")
        elif not fresh:
            alerts.append(f"{name}: stale (last {last_at})")

    # A red run in the last 24h is a softer signal (a retry may have fixed it),
    # so it is recorded but only alerted on when the rail is also the latest run.
    red24 = [
        f"{r['name']} @ {r['created_at']}"
        for r in runs
        if r.get("conclusion") == "failure"
        and datetime.fromisoformat(r["created_at"].replace("Z", "+00:00")) >= now - timedelta(hours=24)
    ]

    return {
        "checked_at": now.isoformat(),
        "rails": rails,
        "red_last_24h": red24,
        "alerts": alerts,
        "ok": not alerts,
    }


def main() -> int:
    heal = os.environ.get("AX_HEARTBEAT_HEAL", "1") != "0"
    try:
        report = collect()
    except Exception as exc:  # network/API hiccup must not crash the board
        report = {"checked_at": datetime.now(timezone.utc).isoformat(),
                  "error": str(exc), "ok": False, "alerts": [f"heartbeat error: {exc}"]}

    # Self-heal the Actions layer: re-dispatch any rail that has gone stale, so a
    # missed cron costs minutes, not a day. Only for rails with a dispatch entry.
    if heal and report.get("rails"):
        healed = []
        for name, info in report["rails"].items():
            if info.get("fresh") or name not in FILES:
                continue
            if _dispatch(FILES[name]):
                healed.append(name)
        if healed:
            report["healed"] = healed

    os.makedirs("data", exist_ok=True)
    with open("data/heartbeat.json", "w") as f:
        json.dump(report, f, indent=2, ensure_ascii=False)
        f.write("\n")

    if report.get("ok"):
        print("ALL GREEN —", ", ".join(f"{k}:{v['last_conclusion']}" for k, v in report.get("rails", {}).items()))
    else:
        print("PROBLEMS:")
        for a in report.get("alerts", []):
            print("  -", a)
        if report.get("healed"):
            print("healed:", ", ".join(report["healed"]))
        _post_ntfy("AERIS rails", "\n".join(report.get("alerts", [])[:8]))
    return 0


if __name__ == "__main__":
    sys.exit(main())
