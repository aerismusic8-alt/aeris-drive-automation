"""Daily release entrypoint for the `music-release` automation. No LLM.

The plugin root already contains this repository (the automation fetched it), so
the driver is run in place — no git clone, because a sandbox with no git
transport hangs on one. `daily_release.py` fetches the code tarball it needs,
pulls each media file from the `media-938` release only as it is uploaded, and
writes the release ledger back through the GitHub Contents API.

Config comes from AUTOMATION_CONFIG_PATH: count, spread, channel. The GitHub and
YouTube credentials are OpenHands secrets, read from the environment.
"""
import json
import os
import subprocess
import sys
import urllib.request

PLUGIN_ROOT = os.environ.get("AUTOMATION_PLUGIN_ROOT", os.getcwd())


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
    except Exception as exc:
        print(f"callback error: {exc}", file=sys.stderr)


def config() -> dict:
    cfg = {"count": 6, "spread": 4, "channel": "ch3"}
    path = os.environ.get("AUTOMATION_CONFIG_PATH")
    if path and os.path.exists(path):
        try:
            cfg.update(json.load(open(path)))
        except Exception:
            pass
    return cfg


def main() -> int:
    cfg = config()
    os.environ["AX_GH_TOKEN"] = get_secret("AX_GH_TOKEN")
    driver = os.path.join(PLUGIN_ROOT, "music938-1", "scripts", "daily_release.py")
    cmd = [sys.executable, driver, "--count", str(int(cfg["count"])),
           "--spread", str(cfg["spread"]), "--ch", str(cfg["channel"])]
    print("$", " ".join(cmd), flush=True)
    return subprocess.call(cmd, cwd=PLUGIN_ROOT)


if __name__ == "__main__":
    try:
        rc = main()
        fire_callback("COMPLETED" if rc == 0 else "FAILED",
                      None if rc == 0 else f"daily_release returned {rc}")
        sys.exit(rc)
    except Exception as exc:
        fire_callback("FAILED", f"{type(exc).__name__}: {exc}"[:300])
        raise
