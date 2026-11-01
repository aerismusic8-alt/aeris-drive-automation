#!/usr/bin/env python3
"""Read an OpenHands secret in any sandbox, interactive or automated.

An interactive session gets the user's secrets injected as environment
variables, but an **automation** sandbox does not: it only sees the secrets it
explicitly selected, so a script that reads `os.environ` alone works when a human
runs it and fails with "missing secret ..." under cron. That silent gap broke the
marketing-daily and daily-release automations.

`get_secret` closes it with the same fallback the working `yt-activity` plugin
uses: read the environment first, then ask the sandbox's own settings API, which
the run can authenticate with its session key.

    from ax_secrets import get_secret
    token = get_secret("YT_CH3_REFRESH_TOKEN")
"""
from __future__ import annotations

import os
import urllib.request


def _settings_url(name: str) -> tuple[str, str]:
    """Return (url, session_key) for the sandbox secrets endpoint, or ("", "")."""
    key = os.environ.get("SESSION_API_KEY") or os.environ.get("OH_SESSION_API_KEYS_0", "")
    server = os.environ.get("AGENT_SERVER_URL", "").rstrip("/")
    if server:
        return f"{server}/api/settings/secrets/{name}", key
    cloud = os.environ.get("OPENHANDS_CLOUD_API_URL", "").rstrip("/")
    sandbox = os.environ.get("SANDBOX_ID", "")
    if cloud and sandbox:
        return f"{cloud}/api/v1/sandboxes/{sandbox}/settings/secrets/{name}", key
    return "", ""


def get_secret(name: str) -> str:
    """The value of a secret, or "" when it is unavailable in this sandbox."""
    value = os.environ.get(name)
    if value:
        return value
    url, key = _settings_url(name)
    if not url:
        return ""
    try:
        req = urllib.request.Request(url, headers={"X-Session-API-Key": key})
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.read().decode().strip()
    except Exception:
        return ""


def require(name: str) -> str:
    """Like get_secret, but exit with a clear message when the value is missing."""
    value = get_secret(name)
    if not value:
        raise SystemExit(f"missing secret {name}")
    return value
