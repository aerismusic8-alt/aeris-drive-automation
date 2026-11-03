"""Grow the AERIS Music Facebook Page. No LLM.

K's rule (2026-11-03): a Page grows by following suggested pages, not by waiting
for friendships. This runs twice a day and:

  1. fetches the repo tarball over HTTPS (the automation sandbox has no git
     transport; a `git clone` hangs until the run times out),
  2. installs Playwright's Chromium and restores the saved session from
     AERIS_STORAGE_STATE_B64, the same free route the crosspost rail uses,
  3. runs `aeris938-2/scripts/outreach.py --follow`, which switches to the Page
     identity, follows a small paced batch of suggested pages and records each
     one in `aeris938-2/work/outreach-state.json`,
  4. commits that state back to `main` through the Contents API so a page is
     never followed twice and the next run resumes.

A GitHub workflow cannot ship this (no token here carries `workflow` scope), so
it runs as a plugin-spec automation instead.

Config comes from AUTOMATION_CONFIG_PATH: limit, min_gap.
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
STATE_REL = "aeris938-2/work/outreach-state.json"


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
    req = urllib.request.Request(f"{API}/repos/{REPO}/tarball/main",
                                 headers={"Authorization": f"token {tok}",
                                          "User-Agent": "ax-growth"})
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
                 "User-Agent": "ax-growth", "Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=60) as r:
            return r.status, json.loads(r.read().decode() or "{}")
    except urllib.error.HTTPError as e:
        return e.code, {"error": e.read().decode()[:300]}


def commit_file(tok: str, repo_path: str, content: bytes, message: str) -> bool:
    st, cur = gh(tok, "GET", f"/repos/{REPO}/contents/{repo_path}")
    if st == 200 and cur.get("content"):
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
    cfg = {"limit": 12, "min_gap": 8}
    path = os.environ.get("AUTOMATION_CONFIG_PATH")
    if path and os.path.exists(path):
        try:
            cfg.update(json.load(open(path)))
        except Exception:
            pass
    return cfg


def install_browser() -> None:
    """Playwright's Chromium is not in the automation image, so install it here."""
    print("--- install playwright ---", flush=True)
    subprocess.check_call([sys.executable, "-m", "pip", "install", "--quiet",
                           "playwright"])
    subprocess.check_call([sys.executable, "-m", "playwright", "install",
                           "--with-deps", "chromium"])


def main() -> int:
    cfg = config()
    tok = get_secret("AX_GH_TOKEN")
    os.environ["AX_GH_TOKEN"] = tok
    session = get_secret("AERIS_STORAGE_STATE_B64")
    if not session:
        print("AERIS_STORAGE_STATE_B64 is not set; cannot reach a signed-in Page",
              file=sys.stderr)
        return 2

    work = Path(tempfile.mkdtemp(prefix="ax-growth-"))
    root = fetch_repo(tok, work)
    install_browser()

    env = dict(os.environ, AERIS_STORAGE_STATE_B64=session, AX_GH_TOKEN=tok)
    env["PYTHONPATH"] = str(root / "aeris938-2" / "scripts")
    script = root / "aeris938-2" / "scripts" / "outreach.py"
    args = [sys.executable, str(script), "--follow",
            "--limit", str(cfg["limit"]), "--min-gap", str(cfg["min_gap"])]
    print("--- outreach --follow ---", flush=True)
    rc = subprocess.call(args, env=env, cwd=str(root))
    subprocess.call([sys.executable, str(script), "--status"], env=env, cwd=str(root))
    if rc != 0:
        print(f"outreach returned {rc}", file=sys.stderr)
        return rc

    state = root / STATE_REL
    if state.exists():
        commit_file(tok, STATE_REL, state.read_bytes(),
                    "data(aeris938-2): outreach state (automated)")
    return 0


if __name__ == "__main__":
    try:
        rc = main()
        fire_callback("COMPLETED" if rc == 0 else "FAILED",
                      None if rc == 0 else f"ax-growth returned {rc}")
        sys.exit(rc)
    except Exception as exc:
        fire_callback("FAILED", f"{type(exc).__name__}: {exc}"[:300])
        raise
