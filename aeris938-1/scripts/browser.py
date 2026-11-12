"""Shared browser plumbing for the cloud desktop.

The browser is a real, headful Chromium on the sandbox X display, driven over
CDP. That matters because the generation tools (Gemini, Flow Music) are
login-only web apps: the operator signs in once through the noVNC link and the
agent then drives that same already-authenticated session. Nothing here types or
stores a credential.
"""
from __future__ import annotations

import json
import os
import urllib.request
from pathlib import Path

CDP_DEFAULT = os.environ.get("AERIS_CDP", "http://127.0.0.1:9222")
NOVNC_PORT = os.environ.get("AERIS_NOVNC_PORT", "12000")
STATE_DIR = Path(os.environ.get("AERIS_STATE_DIR", "/workspace/ax-tools/aeris938-state"))


class LoginRequired(RuntimeError):
    """Raised when the target app is showing a sign-in wall."""


class RateLimited(RuntimeError):
    """Raised when the app returns 429; the caller should back off and retry."""


class TooShort(RuntimeError):
    """Raised when a take is shorter than the brief; retry rather than ship it."""

    def __init__(self, slug: str, seconds: float):
        super().__init__(f"{slug}: take is {seconds:.0f}s, under the floor")
        self.slug = slug
        self.seconds = seconds


def cdp_alive(url: str | None = None) -> bool:
    # Resolved per call, not bound at import: the desktop may be started after
    # this module is loaded.
    url = url or CDP_DEFAULT
    try:
        with urllib.request.urlopen(f"{url}/json/version", timeout=8) as fh:
            json.load(fh)
        return True
    except Exception:
        return False


def login_link() -> str:
    """The noVNC URL for the operator, with the host taken from the environment.

    The host changes every session (`work-1-<random>...`), so a hard-coded one
    goes stale and 404s the moment the pod is replaced. The value comes from the
    session's work_hosts block; if it is not set, say so instead of guessing.
    """
    host = os.environ.get("AERIS_PUBLIC_HOST")
    if not host:
        return ("(set AERIS_PUBLIC_HOST to the session's work-1-... host; the "
                "desktop is on local noVNC port " + NOVNC_PORT + ")")
    return f"https://{host}/vnc.html?autoconnect=1&resize=scale"


def login_instructions(app: str) -> str:
    return (
        f"{app} needs a signed-in browser.\n"
        f"  1. Open the cloud desktop: {login_link()}\n"
        f"  2. Sign in to {app} there (the agent never sees your password)\n"
        f"  3. Re-run this command; the session is reused."
    )


def _vault_state_b64() -> str:
    """The base64 storage_state from the durable vault, or "".

    Kept import-light and failure-proof: a pod with no OpenHands key, or a fresh
    account with no saved session, must fall back to the secret rather than
    crash. `vault_session` lives in `ops/`, which is on sys.path for the rails.
    """
    try:
        import sys  # noqa: PLC0415
        ops = Path(__file__).resolve().parents[2] / "ops"
        if str(ops) not in sys.path:
            sys.path.insert(0, str(ops))
        import vault_session  # noqa: PLC0415
        state = vault_session.load_state()
    except Exception:  # noqa: BLE001
        return ""
    if not state:
        return ""
    import base64  # noqa: PLC0415
    return base64.b64encode(
        json.dumps(state, separators=(",", ":")).encode()).decode()


def connect(playwright):
    """Attach to a browser: the cloud desktop over CDP, or a fresh one in CI.

    Two modes, chosen by the environment:

    * **Cloud desktop (default).** Attach to the running Chromium over CDP. This
      is the interactive route; the operator has signed in once via noVNC.
    * **CI (`AERIS_STORAGE_STATE_B64` or `AERIS_STORAGE_STATE`).** GitHub Actions
      has no desktop and no pod, so it launches its own headless Chromium and
      loads a saved session (see `ops/save_storage_state.py`). This is what makes
      Facebook/TikTok posting runnable on a schedule without a build pod.
    """
    import base64
    import tempfile
    from pathlib import Path

    b64 = os.environ.get("AERIS_STORAGE_STATE_B64")
    path = os.environ.get("AERIS_STORAGE_STATE")
    if not (path and os.path.exists(path)):
        path = None
        # The durable vault holds the *freshest* session and has no size cap,
        # unlike the 48 KB Actions secret (which cannot even hold TikTok's
        # localStorage). Prefer it so a pod sign-in heals CI with no K step; the
        # secret stays the fallback for a fresh account or a missing vault key.
        vault_b64 = _vault_state_b64()
        if vault_b64:
            b64 = vault_b64
    if b64 and not path:
        path = str(Path(tempfile.gettempdir()) / "aeris-storage-state.json")
    if path or b64:
        if b64 and not os.path.exists(path):
            Path(path).parent.mkdir(parents=True, exist_ok=True)
            Path(path).write_bytes(base64.b64decode(b64))
        launch_kwargs = dict(
            headless=True, args=["--no-sandbox", "--disable-dev-shm-usage"])
        # CI installs Playwright's own Chromium; a pod without it can point at
        # the system build so the same path is testable outside Actions.
        exe = os.environ.get("AERIS_CHROMIUM")
        if exe:
            launch_kwargs["executable_path"] = exe
        browser = playwright.chromium.launch(**launch_kwargs)
        context = browser.new_context(
            storage_state=path, locale="th-TH",
            viewport={"width": 1280, "height": 900})
        return browser, context
    if not cdp_alive():
        raise RuntimeError(
            "no cloud desktop found on " + CDP_DEFAULT +
            "\n  start it with: aeris938-1/scripts/desktop.sh up"
        )
    browser = playwright.chromium.connect_over_cdp(CDP_DEFAULT)
    context = browser.contexts[0] if browser.contexts else browser.new_context()
    return browser, context


def page_for(context, url: str, *, reuse_host: str | None = None):
    """Return a page already on the app, else navigate a spare tab to it."""
    pages = context.pages
    if reuse_host:
        for pg in pages:
            if reuse_host in (pg.url or ""):
                return pg
    pg = pages[0] if pages else context.new_page()
    if url not in (pg.url or ""):
        pg.goto(url, wait_until="domcontentloaded", timeout=60_000)
    return pg


SIGNIN_MARKERS = (
    "sign in", "signin", "log in", "login", "เข้าสู่ระบบ",
    "ลงชื่อเข้าใช้", "continue with google", "sign up",
)


def looks_signed_out(text: str) -> bool:
    low = (text or "").lower()
    return any(m in low for m in SIGNIN_MARKERS)


def save_blob(page, blob_url: str, out: Path) -> int:
    """Pull a blob:/data: URL out of the page and write it to disk.

    Blob URLs only resolve inside the page that made them, so the bytes are read
    in page context and handed back as base64.
    """
    out = Path(out)
    out.parent.mkdir(parents=True, exist_ok=True)
    b64 = page.evaluate(
        """async (url) => {
             const r = await fetch(url);
             const buf = new Uint8Array(await r.arrayBuffer());
             let s = '';
             for (let i = 0; i < buf.length; i++) s += String.fromCharCode(buf[i]);
             return btoa(s);
           }""",
        blob_url,
    )
    import base64
    data = base64.b64decode(b64)
    if not data:
        raise RuntimeError(f"blob was empty: {blob_url[:80]}")
    out.write_bytes(data)
    return len(data)
