"""Daily marketing measurement for AERIS Music. No LLM.

The release rail ships videos and the activity monitor records a channel's
totals, but nothing turns those into a decision. This runs once a day and:

  1. fetches the repo tarball over HTTPS (the automation sandbox has no git
     transport; a `git clone` hangs until the run times out),
  2. runs `music938-1/scripts/market.py`, which reads every live video's stats,
     diffs them against the previous snapshot and writes `work/market-report.md`,
  3. refreshes the GitHub Pages promo page from the channel's newest uploads,
  4. commits the report and snapshot back to `main` through the Contents API, so
     the next run can diff and the weekly strategy pass has the file to read.

Config comes from AUTOMATION_CONFIG_PATH: channel, promo_repo. The GitHub and
YouTube credentials are OpenHands secrets, read from the environment.
"""
import base64
import json
import os
import subprocess
import sys
import tarfile
import tempfile
import urllib.error
import urllib.request
from pathlib import Path

REPO = "aerismusic8-alt/aeris-drive-automation"
API = "https://api.github.com"
COMMIT_FILES = [
    "music938-1/work/market-report.md",
    "music938-1/work/market-snapshot.json",
]


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
                                          "User-Agent": "ax-market-daily"})
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
    return next(dest.iterdir())


def gh(tok: str, method: str, path: str, body=None):
    req = urllib.request.Request(
        API + path,
        data=json.dumps(body).encode() if body is not None else None,
        method=method,
        headers={"Authorization": f"token {tok}", "Accept": "application/vnd.github+json",
                 "User-Agent": "ax-market-daily", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:300]}


def commit_file(tok: str, repo_path: str, content: bytes, message: str) -> bool:
    st, cur = gh(tok, "GET", f"/repos/{REPO}/contents/{repo_path}")
    if st == 200 and cur.get("content"):
        # Skip a no-op commit so the daily run does not add empty history.
        if base64.b64decode(cur["content"]) == content:
            print(f"{repo_path}: unchanged")
            return True
    body = {"message": message, "content": base64.b64encode(content).decode(), "branch": "main"}
    if st == 200 and cur.get("sha"):
        body["sha"] = cur["sha"]
    st, res = gh(tok, "PUT", f"/repos/{REPO}/contents/{repo_path}", body)
    print(f"{repo_path}: write {st} {str(res.get('commit', {}).get('sha', res.get('error', '')))[:12]}")
    return st in (200, 201)


def config() -> dict:
    cfg = {"channel": "ch3", "promo_repo": "aerismusic8-alt/site-aeris-music"}
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
    work = Path(tempfile.mkdtemp(prefix="ax-market-"))
    root = fetch_repo(tok, work)
    music = root / "music938-1"
    env = dict(os.environ, AX_GH_TOKEN=tok, PYTHONPATH=str(music / "scripts"))

    print("--- market.py ---", flush=True)
    rc = subprocess.call([sys.executable, str(music / "scripts" / "market.py"),
                          "--root", str(root), "--channel", str(cfg["channel"])],
                         env=env, cwd=str(root))
    if rc != 0:
        print(f"market.py returned {rc}", file=sys.stderr)
        return rc

    print("--- promo site ---", flush=True)
    promo = root / "ops" / "ar_promo_site.py"
    if promo.exists():
        rc = subprocess.call([sys.executable, str(promo),
                              "--channel", str(cfg["channel"]),
                              "--repo", str(cfg["promo_repo"])],
                             env=env, cwd=str(root), timeout=180)
        if rc != 0:
            print(f"promo site refresh returned {rc} (non-fatal)", file=sys.stderr)

    for rel in COMMIT_FILES:
        p = root / rel
        if p.exists():
            commit_file(tok, rel, p.read_bytes(), "market: daily channel report (automated)")
    return 0


if __name__ == "__main__":
    try:
        rc = main()
        fire_callback("COMPLETED" if rc == 0 else "FAILED",
                      None if rc == 0 else f"market-daily returned {rc}")
        sys.exit(rc)
    except Exception as exc:
        fire_callback("FAILED", f"{type(exc).__name__}: {exc}"[:300])
        raise
