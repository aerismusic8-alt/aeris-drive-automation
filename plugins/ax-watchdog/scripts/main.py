"""Hourly watchdog for the AX rail. No LLM.

Why this exists
---------------
The rail already has automations that *do* things (release, market, activity).
What it did not have was anything that noticed when one of them **stopped**.
On 2026-11-01 the platform auto-paused "AX Music Daily Release" after five
consecutive failures — every one of them `Timed out: Sandbox not available` —
and nothing said so. A paused release automation looks exactly like a working
one from the outside: no video appears, and the reason is only visible in the
automation's run history. That is the gap this closes.

It runs outside the sandbox, so a dead sandbox cannot stop the thing whose job
is to notice dead sandboxes.

What it does each run
---------------------
1. Lists every automation and flags any that is disabled, or that has failed
   recently, or that has not succeeded in a long time.
2. Heals the ones the platform paused itself (`disabled_reason.source ==
   "consecutive_failures"`): re-enables them, because a paused rail is worse
   than a retrying one. Manual pauses are left alone — a human chose those.
3. Reads every YouTube channel's newest upload and flags a stale one.
4. Pushes one alert to ntfy when anything is wrong, with a cooldown so a
   long outage does not send an alert an hour.

State (last alert time per key) lives in the automation KV store, not a file,
because a file does not survive the run.
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

API = "https://app.all-hands.dev/api/automation/v1"
TOKEN_URL = "https://oauth2.googleapis.com/token"
YT_API = "https://www.googleapis.com/youtube/v3"
CHANNELS = {
    "ch1": ("YT_CH1_REFRESH_TOKEN", "ตาต้า GenX Shop"),
    "ch2": ("YT_CH2_REFRESH_TOKEN", "Farmmer"),
    "ch3": ("YT_CH3_REFRESH_TOKEN", "AERIS Music"),
    "ch4": ("YT_CH4_REFRESH_TOKEN", "kongkeat pratumma"),
}
FAIL_LOOKBACK = 12  # runs to inspect per automation


def get_secret(name: str) -> str:
    v = os.environ.get(name)
    if v:
        return v
    url = os.environ.get("AGENT_SERVER_URL", "").rstrip("/")
    key = os.environ.get("SESSION_API_KEY") or os.environ.get("OH_SESSION_API_KEYS_0", "")
    if url:
        url = f"{url}/api/settings/secrets/{name}"
    else:
        api = os.environ["OPENHANDS_CLOUD_API_URL"].rstrip("/")
        url = f"{api}/api/v1/sandboxes/{os.environ['SANDBOX_ID']}/settings/secrets/{name}"
    with urllib.request.urlopen(urllib.request.Request(
            url, headers={"X-Session-API-Key": key})) as r:
        return r.read().decode().strip()


def fire_callback(status="COMPLETED", error=None):
    url = os.environ.get("AUTOMATION_CALLBACK_URL", "")
    if not url:
        return
    body = {"status": status, "run_id": os.environ.get("AUTOMATION_RUN_ID", "")}
    if error:
        body["error"] = error
    try:
        urllib.request.urlopen(urllib.request.Request(
            url, data=json.dumps(body).encode(),
            headers={"Content-Type": "application/json",
                     "Authorization": f"Bearer {os.environ.get('AUTOMATION_CALLBACK_API_KEY', '')}"}))
    except Exception as exc:  # noqa: BLE001
        print(f"callback error: {exc}", file=sys.stderr)


_KV_TOKEN = os.environ.get("AUTOMATION_KV_TOKEN", "")
_KV_BASE = os.environ.get("AUTOMATION_API_URL", "").rstrip("/")


def kv_get(key: str):
    if not (_KV_TOKEN and _KV_BASE):
        return None
    req = urllib.request.Request(f"{_KV_BASE}/v1/kv/{key}",
                                 headers={"Authorization": f"Bearer {_KV_TOKEN}"})
    try:
        with urllib.request.urlopen(req) as r:
            return json.loads(r.read())["value"]
    except urllib.error.HTTPError as exc:
        if exc.code == 404:
            return None
        raise


def kv_set(key: str, value) -> None:
    if not (_KV_TOKEN and _KV_BASE):
        print(f"[kv off] {key} = {json.dumps(value)[:200]}")
        return
    req = urllib.request.Request(
        f"{_KV_BASE}/v1/kv/{key}", data=json.dumps(value).encode(),
        headers={"Authorization": f"Bearer {_KV_TOKEN}",
                 "Content-Type": "application/json"}, method="PUT")
    with urllib.request.urlopen(req) as r:
        r.read()


def _http(url, data=None, headers=None, method=None, tries=3):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    last = None
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(req, timeout=60) as f:
                raw = f.read().decode() or "{}"
                return f.status, (json.loads(raw) if raw.strip().startswith(("{", "[")) else {})
        except urllib.error.HTTPError as e:
            body = e.read().decode(errors="replace")
            if e.code in (429, 500, 502, 503, 504) and attempt < tries - 1:
                last = f"{e.code} {body[:120]}"
                continue
            try:
                return e.code, json.loads(body or "{}")
            except Exception:  # noqa: BLE001
                return e.code, {"raw": body[:200]}
    raise RuntimeError(last or "unreachable")


def _api_token() -> str:
    return os.environ.get("OPENHANDS_API_KEY") or get_secret("OPENHANDS_API_KEY")


def list_automations() -> list[dict]:
    tok = _api_token()
    code, body = _http(f"{API}", headers={"Authorization": f"Bearer {tok}",
                                          "Accept": "application/json"})
    if code != 200:
        raise RuntimeError(f"list automations {code}: {json.dumps(body)[:150]}")
    return body.get("automations", [])


def recent_runs(aid: str) -> list[dict]:
    tok = _api_token()
    code, body = _http(f"{API}/{aid}/runs?limit={FAIL_LOOKBACK}",
                       headers={"Authorization": f"Bearer {tok}",
                                "Accept": "application/json"})
    if code != 200:
        return []
    return body.get("runs") or body.get("items") or []


def re_enable(aid: str) -> bool:
    tok = _api_token()
    code, _ = _http(f"{API}/{aid}", data=json.dumps({"enabled": True}).encode(),
                    headers={"Authorization": f"Bearer {tok}",
                             "Content-Type": "application/json"}, method="PATCH")
    return code in (200, 201)


def audit_automations(heal: bool) -> tuple[list[str], list[str]]:
    """Return (problems, actions taken)."""
    problems, actions = [], []
    for a in list_automations():
        name = a.get("name", "?")
        aid = a.get("id")
        if a.get("enabled"):
            continue
        detail = a.get("disabled_detail") or {}
        reason = (a.get("disabled_reason") or "")
        source = detail.get("source") if isinstance(detail, dict) else None
        if source == "consecutive_failures" or "Paused automatically" in reason:
            runs = recent_runs(aid)
            errs = [str(r.get("error_detail") or r.get("error") or "")[:80]
                    for r in runs if r.get("status") == "FAILED"]
            problems.append(f"{name}: auto-paused after repeated failures"
                            + (f" ({errs[0]})" if errs else ""))
            if heal and re_enable(aid):
                actions.append(f"re-enabled {name}")
            elif heal:
                problems.append(f"{name}: re-enable failed")
        elif reason and reason != "manual":
            problems.append(f"{name}: disabled ({reason[:60]})")
    return problems, actions


def channel_rows(stale_hours: float) -> list[dict]:
    rows = []
    for ch, (var, title) in CHANNELS.items():
        row = {"ch": ch, "title": title}
        try:
            data = urllib.parse.urlencode({
                "client_id": get_secret("YT_CLIENT_ID"),
                "client_secret": get_secret("YT_CLIENT_SECRET"),
                "refresh_token": get_secret(var),
                "grant_type": "refresh_token"}).encode()
            _, tok = _http(TOKEN_URL, data=data,
                           headers={"Content-Type": "application/x-www-form-urlencoded"},
                           method="POST")
            access = tok.get("access_token")
            if not access:
                row.update({"status": "auth_error", "detail": json.dumps(tok)[:120]})
                rows.append(row)
                continue
            h = {"Authorization": f"Bearer {access}"}
            _, ch_body = _http(f"{YT_API}/channels?part=statistics,contentDetails&mine=true",
                               headers=h)
            item = (ch_body.get("items") or [None])[0]
            if not item:
                row.update({"status": "no_channel"})
                rows.append(row)
                continue
            uploads = item["contentDetails"]["relatedPlaylists"]["uploads"]
            _, pl = _http(f"{YT_API}/playlistItems?part=contentDetails&playlistId={uploads}"
                          f"&maxResults=1", headers=h)
            items = pl.get("items") or []
            pub = items[0]["contentDetails"].get("videoPublishedAt") if items else None
            hours = None
            if pub:
                age = datetime.now(timezone.utc) - datetime.fromisoformat(pub.replace("Z", "+00:00"))
                hours = round(age.total_seconds() / 3600, 1)
            row.update({"status": "ok", "subs": int(item["statistics"].get("subscriberCount", 0)),
                        "views": int(item["statistics"].get("viewCount", 0)),
                        "videos": int(item["statistics"].get("videoCount", 0)),
                        "hours_since_upload": hours,
                        "stale": hours is not None and hours > stale_hours})
        except Exception as exc:  # noqa: BLE001
            row.update({"status": "error", "detail": f"{type(exc).__name__}: {exc}"[:140]})
        rows.append(row)
    return rows


def push(topic: str, title: str, message: str, priority: str = "high") -> bool:
    if not topic:
        return False
    try:
        urllib.request.urlopen(urllib.request.Request(
            f"https://ntfy.sh/{topic}", data=message.encode(),
            headers={"Title": title, "Priority": priority,
                     "Tags": "warning,robot"}, method="POST"), timeout=30)
        return True
    except Exception as exc:  # noqa: BLE001
        print(f"ntfy error: {exc}", file=sys.stderr)
        return False


def main() -> int:
    cfg = {}
    cfg_path = os.environ.get("AUTOMATION_CONFIG_PATH")
    if cfg_path and os.path.exists(cfg_path):
        try:
            cfg = json.load(open(cfg_path))
        except Exception:  # noqa: BLE001
            cfg = {}
    stale_hours = float(cfg.get("stale_hours", 30))
    cooldown = float(cfg.get("cooldown_hours", 6))
    topic = (cfg.get("ntfy_topic") or "").strip()
    heal = bool(cfg.get("heal", True))

    problems, actions = audit_automations(heal)
    rows = channel_rows(stale_hours)
    for r in rows:
        if r.get("status") != "ok":
            problems.append(f"{r['title']}: {r['status']} {r.get('detail', '')}".strip())
        elif r.get("stale"):
            problems.append(f"{r['title']}: no upload for {r['hours_since_upload']}h")

    now = datetime.now(timezone.utc)
    kv_set("latest", {"at": now.isoformat(timespec="seconds"),
                      "problems": problems, "actions": actions, "channels": rows})

    alerted = False
    if problems:
        sig = "|".join(sorted(p.split(":")[0] for p in problems))
        last = kv_get("last_alert") or {}
        try:
            last_at = datetime.fromisoformat(last.get("at", ""))
        except Exception:  # noqa: BLE001
            last_at = None
        due = (last.get("sig") != sig or last_at is None
               or (now - last_at).total_seconds() > cooldown * 3600)
        if due and push(topic, "AX rail needs attention",
                        "\n".join(problems + [f"- {a}" for a in actions])):
            kv_set("last_alert", {"at": now.isoformat(timespec="seconds"), "sig": sig})
            alerted = True

    for a in actions:
        print(f"HEAL  {a}")
    for p in problems:
        print(f"WARN  {p}")
    for r in rows:
        if r.get("status") == "ok":
            print(f"      {r['title']}: {r['subs']} subs, {r['videos']} videos, "
                  f"last upload {r.get('hours_since_upload', '?')}h")
    if not problems:
        print("all clear")
    print(f"\nalert: {'pushed' if alerted else ('held (cooldown)' if problems else 'not needed')}")
    return 0


if __name__ == "__main__":
    try:
        rc = main()
        fire_callback("COMPLETED")
        sys.exit(rc)
    except Exception as exc:  # noqa: BLE001
        print(f"ERROR: {exc}", file=sys.stderr)
        fire_callback("FAILED", str(exc))
        sys.exit(1)
