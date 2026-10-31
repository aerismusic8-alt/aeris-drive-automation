"""Hourly channel-activity check for the AX YouTube channels. No LLM.

For every channel it records subs, videos, views and the age of the newest
upload, then flags a channel that has not uploaded within `stale_hours`. The
reading is written to the automation KV store so it survives the sandbox, and
the newest reading per channel is what a follow-up automation or a person reads.

The refresh tokens are OpenHands secrets, fetched at run time. A missing or
rejected token records `auth_error` and the run still succeeds, so a broken
credential shows up as a gap in the series instead of a silent absence.
"""
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timezone

CHANNELS = {
    "ch1": ("YT_CH1_REFRESH_TOKEN", "ตาต้า GenX Shop"),
    "ch2": ("YT_CH2_REFRESH_TOKEN", "Farmmer"),
    "ch3": ("YT_CH3_REFRESH_TOKEN", "AERIS Music"),
    "ch4": ("YT_CH4_REFRESH_TOKEN", "kongkeat pratumma"),
}
TOKEN_URL = "https://oauth2.googleapis.com/token"
API = "https://www.googleapis.com/youtube/v3"


def get_secret(name: str) -> str:
    # OpenHands injects user secrets as environment variables, so read that
    # first; the API path is the fallback for a sandbox that does not.
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
    except Exception as exc:
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


def _http(url, data=None, headers=None, method=None, tries=4):
    req = urllib.request.Request(url, data=data, headers=headers or {}, method=method)
    for attempt in range(tries):
        try:
            with urllib.request.urlopen(req, timeout=60) as f:
                return f.status, json.loads(f.read().decode() or "{}")
        except urllib.error.HTTPError as e:
            if e.code in (429, 500, 502, 503, 504) and attempt < tries - 1:
                continue
            return e.code, json.loads(e.read().decode(errors="replace") or "{}")
    raise RuntimeError("unreachable")


def access_token(refresh: str) -> str:
    data = urllib.parse.urlencode({
        "client_id": get_secret("YT_CLIENT_ID"),
        "client_secret": get_secret("YT_CLIENT_SECRET"),
        "refresh_token": refresh,
        "grant_type": "refresh_token",
    }).encode()
    code, body = _http(TOKEN_URL, data=data,
                       headers={"Content-Type": "application/x-www-form-urlencoded"},
                       method="POST")
    if "access_token" not in body:
        raise RuntimeError(f"token {code}: {json.dumps(body)[:120]}")
    return body["access_token"]


def api_get(path: str, tok: str, **params):
    q = urllib.parse.urlencode(params)
    return _http(f"{API}/{path}?{q}", headers={"Authorization": f"Bearer {tok}"})


def snapshot(ch: str, var: str, stale_hours: float) -> dict:
    now = datetime.now(timezone.utc).isoformat(timespec="seconds")
    row = {"at": now, "ch": ch}
    try:
        tok = access_token(get_secret(var))
        code, body = api_get("channels", tok,
                             part="snippet,statistics,contentDetails", mine="true")
        item = (body.get("items") or [None])[0]
        if not item:
            row["status"] = "no_channel"
            return row
        st = item["statistics"]
        row.update({"status": "ok", "id": item["id"],
                    "title": item["snippet"]["title"],
                    "subs": int(st.get("subscriberCount", 0)),
                    "videos": int(st.get("videoCount", 0)),
                    "views": int(st.get("viewCount", 0))})
        uploads = item["contentDetails"]["relatedPlaylists"]["uploads"]
        _, pl = api_get("playlistItems", tok, part="contentDetails",
                        playlistId=uploads, maxResults=1)
        items = pl.get("items") or []
        if items:
            pub = items[0]["contentDetails"].get("videoPublishedAt")
            row["last_upload"] = pub
            if pub:
                age = datetime.now(timezone.utc) - datetime.fromisoformat(
                    pub.replace("Z", "+00:00"))
                row["hours_since_upload"] = round(age.total_seconds() / 3600, 1)
                row["stale"] = row["hours_since_upload"] > stale_hours
    except Exception as exc:
        row["status"] = "auth_error"
        row["detail"] = f"{type(exc).__name__}: {exc}"[:160]
    return row


def main() -> int:
    stale_hours = 36.0
    cfg_path = os.environ.get("AUTOMATION_CONFIG_PATH")
    if cfg_path and os.path.exists(cfg_path):
        try:
            stale_hours = float(json.load(open(cfg_path)).get("stale_hours", 36))
        except Exception:
            pass

    rows = [snapshot(ch, var, stale_hours) for ch, (var, _) in CHANNELS.items()]
    kv_set("latest", {"at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
                      "channels": rows})
    hist = kv_get("history") or []
    hist = (hist + [{"at": r["at"], "ch": r["ch"], "subs": r.get("subs"),
                     "views": r.get("views"), "videos": r.get("videos"),
                     "hours_since_upload": r.get("hours_since_upload")} for r in rows])[-96:]
    kv_set("history", hist)

    stale = []
    for r in rows:
        if r["status"] != "ok":
            print(f"{r['ch']} {r['status']}: {r.get('detail', '')}")
            continue
        flag = " STALE" if r.get("stale") else ""
        if r.get("stale"):
            stale.append(r["ch"])
        print(f"{r['ch']} {r['title']}: {r['subs']} subs, {r['videos']} videos, "
              f"{r['views']} views, last upload {r.get('hours_since_upload', '?')}h{flag}")
    if stale:
        print(f"\nSTALE (no upload > {stale_hours:.0f}h): {', '.join(stale)}")
    return 0


if __name__ == "__main__":
    try:
        rc = main()
        fire_callback("COMPLETED")
        sys.exit(rc)
    except Exception as exc:
        print(f"ERROR: {exc}", file=sys.stderr)
        fire_callback("FAILED", str(exc))
        sys.exit(1)
