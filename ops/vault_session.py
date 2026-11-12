#!/usr/bin/env python3
"""The browser session the CI rails use, kept in the durable vault — not a frozen
GitHub secret.

The defect this fixes
---------------------
The crosspost / admin / dashboard rails post through a signed-in headless
Chromium, loading their cookies from the Actions secret `AERIS_STORAGE_STATE_B64`.
That secret is a *snapshot*: nothing refreshes it on its own, so every few weeks
the cookies inside it die, the rail can no longer post, and the failure pages K to
sign in through noVNC — after which a pod has to run `--push-secret` by hand to
make CI work again. That is a login loop with K in the middle, which is the thing
K called out: "คุกกี้ล้างตลอด ล็อกอินบ่อยแบบนี้จะออโต้ได้ไง".

The vault already holds the *live* cookies (written by `login_vault.py save`, which
any pod sign-in runs) and survives a sandbox recycle. This module is the missing
wire: it turns the vault's cookie set into a Playwright `storage_state` blob, so a
CI run reads the **freshest** session instead of a stale snapshot.

    python3 ops/vault_session.py get-b64     # base64 storage_state for CI
    python3 ops/vault_session.py put FILE    # store a storage_state file
    python3 ops/vault_session.py status      # what is stored, and when

`get-b64` prints nothing and exits 0 when the vault has no session (a fresh
account); the caller then falls back to the secret.
"""
from __future__ import annotations

import argparse
import base64
import gzip
import json
import os
import sys
from datetime import datetime, timezone
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
import ax_vault  # noqa: E402
import login_vault  # noqa: E402

# Where the assembled Playwright storage_state lives, beside the cookie set.
STATE_INDEX_KEY = "axlogin:state:index"
STATE_CHUNK_KEY = "axlogin:state:d:{i}"
# The domains a CI rail needs. Facebook + TikTok post; Shopee is read. Kept equal
# to `save_storage_state.WANT` so the vault blob and the secret hold the same set.
WANT = ("facebook.com", "tiktok.com", "shopee.co.th")
CHUNK_CHARS = ax_vault.CHUNK_CHARS


def _cookie_chunks(aid: str) -> tuple[dict, list[str]]:
    index = ax_vault.kv_get(aid, login_vault.INDEX_KEY)
    if not index:
        return {}, []
    chunks = [ax_vault.kv_get(aid, login_vault.CHUNK_KEY.format(i=i)) or ""
              for i in range(index["count"])]
    return index, chunks


def _storage_origins(aid: str) -> list[dict]:
    """The vault's localStorage dump, as Playwright `origins` entries.

    Playwright's storage_state carries localStorage only (not sessionStorage), so
    the vault's `session` half is dropped — it is empty for these origins anyway.
    """
    index = ax_vault.kv_get(aid, login_vault.LS_INDEX_KEY)
    if not index:
        return []
    chunks = [ax_vault.kv_get(aid, login_vault.LS_CHUNK_KEY.format(i=i)) or ""
              for i in range(index["count"])]
    collected = json.loads(gzip.decompress(
        base64.b64decode("".join(chunks))).decode())
    out: list[dict] = []
    for origin, dump in collected.items():
        if not any(w in origin for w in WANT):
            continue
        entries = [{"name": k, "value": v} for k, v in (dump.get("local") or {}).items()]
        if entries:
            out.append({"origin": origin, "localStorage": entries})
    return out


def _decode_state(aid: str) -> dict | None:
    """The self-contained storage_state written by `save_state`, or None."""
    index = ax_vault.kv_get(aid, STATE_INDEX_KEY)
    if not index:
        return None
    chunks = [ax_vault.kv_get(aid, STATE_CHUNK_KEY.format(i=i)) or ""
              for i in range(index["count"])]
    return json.loads(gzip.decompress(base64.b64decode("".join(chunks))).decode())


def load_state() -> dict | None:
    """The vault's session as a Playwright storage_state, or None when absent.

    Prefers the self-contained blob written by `save_state` (cookies + the
    localStorage origins). Falls back to assembling cookies from the older
    `login_vault` cookie set, so a vault populated before this module existed
    still yields a usable session.
    """
    aid = ax_vault.ensure_anchor()
    state = _decode_state(aid)
    if state and state.get("cookies"):
        # A storage_state taken straight off a CDP context can come back with no
        # origins, losing TikTok's localStorage (its device-trust token). Backfill
        # from the login_vault storage dump when the blob is missing them.
        if not state.get("origins"):
            state["origins"] = _storage_origins(aid)
        return state
    index, chunks = _cookie_chunks(aid)
    if not index or not chunks:
        return None
    cookies = [c for c in login_vault.unpack(index, chunks)
               if any(w in (c.get("domain") or "") for w in WANT)]
    if not cookies:
        return None
    return {"cookies": cookies, "origins": _storage_origins(aid)}


def save_state(state: dict) -> int:
    """Store a Playwright storage_state (cookies + origins) in the vault."""
    cookies = [c for c in state.get("cookies", [])
               if any(w in (c.get("domain") or "") for w in WANT)]
    if not cookies:
        print("no facebook/tiktok/shopee cookies in the state; nothing stored")
        return 1
    origins = [o for o in state.get("origins", [])
               if any(w in (o.get("origin") or "") for w in WANT)]
    blob = json.dumps({"cookies": cookies, "origins": origins},
                      separators=(",", ":")).encode()
    b64 = base64.b64encode(gzip.compress(blob)).decode()
    chunks = [b64[i:i + CHUNK_CHARS] for i in range(0, len(b64), CHUNK_CHARS)] or [""]
    aid = ax_vault.ensure_anchor()
    for i, c in enumerate(chunks):
        ax_vault.kv_put(aid, STATE_CHUNK_KEY.format(i=i), c)
    ax_vault.kv_put(aid, STATE_INDEX_KEY, {
        "count": len(chunks),
        "n_cookies": len(cookies),
        "n_origins": len(origins),
        "saved_at": datetime.now(timezone.utc).isoformat(timespec="seconds"),
    })
    print(f"stored session: {len(cookies)} cookies, {len(origins)} origins")
    return 0


def get_b64() -> int:
    """Print the base64 storage_state for CI, or nothing when the vault is empty."""
    state = load_state()
    if not state:
        return 0
    raw = json.dumps(state, separators=(",", ":")).encode()
    sys.stdout.write(base64.b64encode(raw).decode())
    return 0


def write_state(path: str) -> int:
    """Write the vault session as a raw Playwright storage_state JSON file.

    CI reads it through `AERIS_STORAGE_STATE` (a path), not an env var: the blob
    is ~680 KB and TikTok's localStorage alone is far past any single env-var or
    Actions-secret limit. Exit 1 when the vault has no session, so the caller can
    fall back to the secret.
    """
    state = load_state()
    if not state:
        return 1
    Path(path).write_text(json.dumps(state, separators=(",", ":")), encoding="utf-8")
    print(f"wrote {len(state['cookies'])} cookies to {path}")
    return 0


def status() -> int:
    aid = ax_vault.ensure_anchor()
    index = ax_vault.kv_get(aid, STATE_INDEX_KEY)
    if not index:
        print("no vault session (vault_session.put has never run)")
        return 0
    print(f"stored session: {index['n_cookies']} cookies, "
          f"{index.get('n_origins', 0)} origins at {index['saved_at']}")
    return 0


def main(argv: list[str]) -> int:
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("command", choices=["get-b64", "put", "status", "write-state"])
    ap.add_argument("file", nargs="?", help="storage_state JSON file for `put`, or the output path for `write-state`")
    args = ap.parse_args(argv)
    if args.command == "get-b64":
        return get_b64()
    if args.command == "status":
        return status()
    if args.command == "write-state":
        if not args.file:
            ap.error("write-state needs an output path")
        return write_state(args.file)
    if not args.file:
        ap.error("put needs a storage_state JSON file")
    return save_state(json.loads(Path(args.file).read_text(encoding="utf-8")))


if __name__ == "__main__":
    raise SystemExit(main(sys.argv[1:]))
