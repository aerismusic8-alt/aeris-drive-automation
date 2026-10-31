"""Daily scheduled release entrypoint for the `music-release` automation. No LLM.

The automation fetches **only this plugin directory** (`plugins/music-release`),
not the whole repository, so the driver at `music938-1/scripts/daily_release.py`
is not on disk here. This module downloads the repository tarball over HTTPS
once and runs the driver from that tree with `--root`, which also stops the
driver from fetching a second copy. Git transport is never used: the automation
sandbox has none, and a `git clone` there hangs until the run times out.

Config comes from AUTOMATION_CONFIG_PATH: count, spread, channel. The GitHub and
YouTube credentials are OpenHands secrets, read from the environment.
"""
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import urllib.request
from pathlib import Path

REPO = "aerismusic8-alt/aeris-drive-automation"
API = "https://api.github.com"


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


def fetch_repo(tok: str, dest: Path) -> Path:
    """Download and extract the repo tarball; return the extracted repo root."""
    req = urllib.request.Request(f"{API}/repos/{REPO}/tarball/main",
                                 headers={"Authorization": f"token {tok}",
                                          "User-Agent": "ax-music-release"})
    with urllib.request.urlopen(req, timeout=180) as r, tempfile.NamedTemporaryFile(
            suffix=".tar.gz", delete=False) as fh:
        fh.write(r.read())
        tmp = fh.name
    dest.mkdir(parents=True, exist_ok=True)
    with tarfile.open(tmp) as t:
        try:
            t.extractall(dest, filter="data")
        except TypeError:  # Python < 3.12 has no filter argument
            t.extractall(dest)
    os.unlink(tmp)
    return next(dest.iterdir())  # the tarball extracts into one top dir


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
    tok = get_secret("AX_GH_TOKEN")
    os.environ["AX_GH_TOKEN"] = tok
    work = Path(tempfile.mkdtemp(prefix="ax-music-release-"))
    root = fetch_repo(tok, work)
    driver = root / "music938-1" / "scripts" / "daily_release.py"
    cmd = [sys.executable, str(driver), "--root", str(root),
           "--count", str(int(cfg["count"])),
           "--spread", str(cfg["spread"]), "--ch", str(cfg["channel"])]
    print("$", " ".join(cmd), flush=True)
    return subprocess.call(cmd, cwd=str(root))


if __name__ == "__main__":
    try:
        rc = main()
        fire_callback("COMPLETED" if rc == 0 else "FAILED",
                      None if rc == 0 else f"daily_release returned {rc}")
        sys.exit(rc)
    except Exception as exc:
        fire_callback("FAILED", f"{type(exc).__name__}: {exc}"[:300])
        raise
