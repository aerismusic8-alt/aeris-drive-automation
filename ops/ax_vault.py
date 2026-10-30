#!/usr/bin/env python3
"""AX knowledge vault — durable storage that outlives a sandbox.

A sandbox is disposable: the home directory, /workspace and every file in them
go away when the session ends. Anything learned there is lost unless it is
copied into an account-scoped store. This tool does that copy.

Where it lives
--------------
The OpenHands automation KV store, reached at
``POST/GET/DELETE {host}/api/automation/v1/kv/{key}?automation_id={id}``.
It is account-scoped, survives sandbox death, is readable *and* writable, and
caps each value at 65536 bytes. The vault packs a tar.gz, splits it into
chunks under that cap, and keeps an index key describing the contents.

The anchor automation is found by name so a fresh session needs no prior
knowledge of an id. If it is absent, ``ensure`` creates it disabled — a vault
must never cost a token or run on a schedule.

Usage
-----
    python3 ops/ax_vault.py ensure            # create/confirm the anchor automation
    python3 ops/ax_vault.py pack              # copy the knowledge set into the vault
    python3 ops/ax_vault.py list              # show the index: files, sizes, hashes
    python3 ops/ax_vault.py restore DIR       # rebuild the knowledge set under DIR
    python3 ops/ax_vault.py verify            # compare local files against the index
    python3 ops/ax_vault.py bootstrap         # print the one-line recovery command

Credentials are never packed. See ``EXCLUDE`` below.
"""
from __future__ import annotations

import argparse
import re
import base64
import hashlib
import io
import json
import os
import sys
import tarfile
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path

HOST = os.environ.get("OPENHANDS_HOST", "https://app.all-hands.dev").rstrip("/")
API_KEY = os.environ.get("OPENHANDS_API_KEY", "")
ANCHOR_NAME = "AX KNOWLEDGE VAULT (do not delete)"
INDEX_KEY = "axvault:index"
CHUNK_KEY = "axvault:d:{i}"
# 60000 leaves room for the JSON envelope under the 65536-byte value cap.
CHUNK_CHARS = 60000

# The knowledge set. Paths are relative to the workspace root.
KNOWLEDGE = [
    # The whole skills tree, not one skill: a new skill added next to the old one
    # must be packed without editing this list (ax-pc1-ops was missed this way).
    ".agents/skills",
    ".openhands/memory",
    "ops",
    "scripts_th",
    "library/ch2/ready",
    # The PC1 repair path. Named files, not the whole AX_PC_CONTROL tree: that
    # tree is large and mostly unrelated, and these two are what recovers a PC1
    # whose MCP auth is broken.
    "AX_PC_CONTROL/pc1-mcp-repair.ps1",
    ".github/workflows/ax-pc1-mcp-repair.yml",
]

# Never pack these: credentials, caches, and anything regenerable or large.
EXCLUDE_DIRS = {"__pycache__", ".git", "node_modules", ".venv"}
EXCLUDE_NAMES = {".env", "gh-app.pem", "gh-app.json", "token.json", "credentials.json"}
EXCLUDE_SUFFIX = {".pyc", ".pyo", ".pem", ".key"}
# Any file whose name carries these is treated as a credential. A token file
# slipped into the first pack this way, so the rule is name-based and broad.
EXCLUDE_NAME_PARTS = ("token", "secret", "credential", "password", "passwd", "apikey")
# Content that marks a file as carrying a credential even if its name looks plain.
# Each pattern requires a real token shape — a prefix followed by a long run of
# token characters — so that source files merely mentioning a prefix (including
# this one) are not mistaken for credentials.
SECRET_PATTERNS = (
    r"ghu_[A-Za-z0-9]{30,}",
    r"ghp_[A-Za-z0-9]{30,}",
    r"ghs_[A-Za-z0-9]{30,}",
    r"github_pat_[A-Za-z0-9_]{30,}",
    r"ya29\.[A-Za-z0-9_\-]{20,}",
    r"-----BEGIN [A-Z ]*PRIVATE KEY-----",
    r"AIza[A-Za-z0-9_\-]{30,}",
    r"sk-[A-Za-z0-9]{30,}",
    r"xox[bp]-[A-Za-z0-9\-]{20,}",
    r"1//0[A-Za-z0-9_\-]{30,}",
)
# Skip media big enough to make the vault unwieldy; the vault is for knowledge,
# and a finished episode is rebuilt or re-uploaded rather than stored here.
MAX_FILE_BYTES = 2_000_000


def api(method: str, path: str, body=None, ctype="application/json"):
    data = None
    if body is not None:
        data = body if isinstance(body, bytes) else json.dumps(body).encode()
    req = urllib.request.Request(
        HOST + path, data=data, method=method,
        headers={"Authorization": f"Bearer {API_KEY}", "Accept": "application/json",
                 "Content-Type": ctype},
    )
    try:
        with urllib.request.urlopen(req, timeout=90) as r:
            raw = r.read()
            return r.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            return e.code, json.loads(raw)
        except Exception:
            return e.code, raw.decode(errors="replace")[:300]


def find_anchor():
    """Return the anchor automation id, or None. Found by name, not by id."""
    st, d = api("GET", "/api/automation/v1")
    if st != 200:
        raise SystemExit(f"cannot list automations: {st} {d}")
    for a in d.get("automations", []):
        if a.get("name") == ANCHOR_NAME:
            return a["id"]
    return None


def ensure_anchor():
    """Confirm the anchor exists, creating it disabled if it does not."""
    aid = find_anchor()
    if aid:
        return aid
    # A one-line no-op tarball. Disabled below, so it never runs; the script
    # exists only because the API requires an entrypoint.
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        main = b"print('AX knowledge vault anchor; nothing to do')\n"
        info = tarfile.TarInfo("main.py")
        info.size = len(main)
        tf.addfile(info, io.BytesIO(main))
    st, up = api("POST", "/api/automation/v1/uploads?name=ax-knowledge-vault",
                 body=buf.getvalue(), ctype="application/gzip")
    if st not in (200, 201):
        raise SystemExit(f"upload failed: {st} {up}")
    st, res = api("POST", "/api/automation/v1", {
        "name": ANCHOR_NAME,
        "description": "Durable home of the AX knowledge vault. Read it with ops/ax_vault.py. "
                       "Disabled on purpose so it never runs or costs a token.",
        "trigger": {"type": "cron", "schedule": "0 0 1 1 *", "timezone": "UTC"},
        "tarball_path": up["tarball_path"],
        "entrypoint": "python3 main.py",
        "enabled": False,
    })
    if st not in (200, 201):
        raise SystemExit(f"create failed: {st} {res}")
    aid = res.get("id")
    if res.get("enabled"):
        api("PATCH", f"/api/automation/v1/{aid}", {"enabled": False})
    return aid


def kv_get(aid, key):
    st, d = api("GET", f"/api/automation/v1/kv/{urllib.parse.quote(key)}?automation_id={aid}")
    if st == 404:
        return None
    if st != 200:
        raise SystemExit(f"kv get {key}: {st} {d}")
    # The service echoes the stored envelope: {"key": k, "value": {"value": V}}.
    v = d.get("value")
    if isinstance(v, dict) and set(v.keys()) == {"value"}:
        return v["value"]
    return v


def kv_put(aid, key, value):
    st, d = api("PUT", f"/api/automation/v1/kv/{urllib.parse.quote(key)}?automation_id={aid}",
                {"value": value})
    if st not in (200, 201):
        raise SystemExit(f"kv put {key}: {st} {d}")


def kv_del(aid, key):
    api("DELETE", f"/api/automation/v1/kv/{urllib.parse.quote(key)}?automation_id={aid}")


def kv_keys(aid):
    st, d = api("GET", f"/api/automation/v1/kv?automation_id={aid}&limit=1000")
    if st != 200:
        raise SystemExit(f"kv list: {st} {d}")
    return [k if isinstance(k, str) else k.get("key") for k in d.get("keys", [])]


def skipped(rel: Path) -> bool:
    if any(part in EXCLUDE_DIRS for part in rel.parts):
        return True
    if rel.name in EXCLUDE_NAMES or rel.suffix in EXCLUDE_SUFFIX:
        return True
    low = rel.name.lower()
    return any(part in low for part in EXCLUDE_NAME_PARTS)


def looks_secret(data: bytes) -> bool:
    """True when a file's bytes carry something shaped like a credential."""
    head = data[:8192]
    try:
        text = head.decode("utf-8", errors="ignore")
    except Exception:
        return False
    return any(re.search(pat, text) for pat in SECRET_PATTERNS)


def collect(root: Path):
    """Yield (relative path, bytes) for the knowledge set, skipping the excluded."""
    for entry in KNOWLEDGE:
        base = root / entry
        if not base.exists():
            continue
        if base.is_file():
            if not skipped(Path(entry)):
                yield Path(entry), base.read_bytes()
            continue
        for p in sorted(base.rglob("*")):
            if not p.is_file():
                continue
            rel = p.relative_to(root)
            if skipped(rel):
                continue
            if p.stat().st_size > MAX_FILE_BYTES:
                print(f"  skip (too large): {rel} {p.stat().st_size} B")
                continue
            data = p.read_bytes()
            if looks_secret(data):
                print(f"  skip (looks like a credential): {rel}")
                continue
            yield rel, data


def sha256(b: bytes) -> str:
    return hashlib.sha256(b).hexdigest()


def build_bundle(root: Path):
    """Pack the knowledge set into a tar.gz and return (blob, file manifest)."""
    files = []
    buf = io.BytesIO()
    with tarfile.open(fileobj=buf, mode="w:gz") as tf:
        for rel, data in collect(root):
            info = tarfile.TarInfo(str(rel).replace(os.sep, "/"))
            info.size = len(data)
            info.mtime = 0
            tf.addfile(info, io.BytesIO(data))
            files.append({"path": str(rel).replace(os.sep, "/"),
                          "bytes": len(data), "sha256": sha256(data)})
    return buf.getvalue(), files


def cmd_pack(args):
    aid = ensure_anchor()
    root = Path(args.root).resolve()
    blob, files = build_bundle(root)
    b64 = base64.b64encode(blob).decode()
    chunks = [b64[i:i + CHUNK_CHARS] for i in range(0, len(b64), CHUNK_CHARS)]

    index = {
        "version": 1,
        "created_utc": __import__("datetime").datetime.now(__import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "anchor_automation": ANCHOR_NAME,
        "anchor_automation_id": aid,
        "bundle_bytes": len(blob),
        "bundle_sha256": sha256(blob),
        "chunks": len(chunks),
        "file_count": len(files),
        "files": files,
        "restore_command": f"python3 ops/ax_vault.py restore <DIR>",
        "notes": "Packed by ops/ax_vault.py. Credentials are never included.",
    }

    # Write chunks first, then the index. An interrupted pack then leaves the
    # old index pointing at a complete set rather than a half-written one.
    for i, c in enumerate(chunks):
        kv_put(aid, CHUNK_KEY.format(i=i), c)
    kv_put(aid, INDEX_KEY, index)

    # Drop chunks left over from a larger previous bundle.
    for key in kv_keys(aid):
        if key.startswith("axvault:d:"):
            try:
                n = int(key.rsplit(":", 1)[1])
            except ValueError:
                continue
            if n >= len(chunks):
                kv_del(aid, key)

    print(f"vault packed: {len(files)} files, {len(blob):,} bytes, "
          f"{len(chunks)} chunks, sha256={index['bundle_sha256'][:16]}")
    print(f"anchor: {ANCHOR_NAME} ({aid})")
    return 0


def load_bundle(aid):
    index = kv_get(aid, INDEX_KEY)
    if not index:
        raise SystemExit("vault is empty — run `pack` first")
    parts = []
    for i in range(index["chunks"]):
        c = kv_get(aid, CHUNK_KEY.format(i=i))
        if c is None:
            raise SystemExit(f"chunk {i} missing; the vault is incomplete")
        parts.append(c)
    blob = base64.b64decode("".join(parts))
    got = sha256(blob)
    if got != index["bundle_sha256"]:
        raise SystemExit(f"bundle hash mismatch: got {got[:16]} want {index['bundle_sha256'][:16]}")
    return index, blob


def cmd_list(args):
    aid = find_anchor() or ensure_anchor()
    index = kv_get(aid, INDEX_KEY)
    if not index:
        print("vault is empty")
        return 0
    print(f"anchor : {index['anchor_automation']} ({aid})")
    print(f"created: {index['created_utc']}")
    print(f"bundle : {index['bundle_bytes']:,} bytes  sha256={index['bundle_sha256'][:16]}  "
          f"chunks={index['chunks']}")
    print(f"files  : {index['file_count']}")
    for f in index["files"]:
        print(f"  {f['bytes']:>8,}  {f['path']}")
    return 0


def cmd_restore(args):
    aid = find_anchor()
    if not aid:
        raise SystemExit("anchor automation not found")
    index, blob = load_bundle(aid)
    dest = Path(args.dir).resolve()
    dest.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(blob), mode="r:gz") as tf:
        for m in tf.getmembers():
            if not m.isfile():
                continue
            # Refuse traversal outside the destination.
            target = (dest / m.name).resolve()
            if not str(target).startswith(str(dest)):
                raise SystemExit(f"refusing unsafe path: {m.name}")
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_bytes(tf.extractfile(m).read())
    print(f"restored {index['file_count']} files into {dest}")
    print(f"bundle sha256 verified: {index['bundle_sha256'][:16]}")
    return 0


def cmd_verify(args):
    aid = find_anchor()
    if not aid:
        raise SystemExit("anchor automation not found")
    index, _ = load_bundle(aid)
    root = Path(args.root).resolve()
    bad = []
    for f in index["files"]:
        p = root / f["path"]
        if not p.exists():
            bad.append(("MISSING", f["path"]))
        elif sha256(p.read_bytes()) != f["sha256"]:
            bad.append(("DIFFERS", f["path"]))
    if not bad:
        print(f"verified: all {index['file_count']} files match the vault")
        return 0
    for kind, path in bad:
        print(f"  {kind}: {path}")
    print(f"{len(bad)} of {index['file_count']} files do not match")
    return 1


def cmd_export(args):
    """Write the knowledge set to a portable file for moving between accounts.

    The KV vault is account-scoped, so it cannot follow K to another OpenHands
    account. This bundle can: a plain tar.gz plus a JSON manifest, carried by
    any means (repo, drive, paste) and loaded with `import` into whichever
    account is current.
    """
    root = Path(args.root).resolve()
    blob, files = build_bundle(root)
    out = Path(args.dir)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_bytes(blob)
    now = __import__("datetime").datetime.now(
        __import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    manifest = {
        "version": 1,
        "created_utc": now,
        "bundle_bytes": len(blob),
        "bundle_sha256": sha256(blob),
        "file_count": len(files),
        "files": files,
        "restore_command": f"python3 ops/ax_vault.py import {out}",
        "notes": "Portable AX knowledge bundle. Contains no credentials. "
                 "Import it into another account to migrate the whole knowledge set.",
    }
    mpath = Path(str(out) + ".manifest.json")
    mpath.write_text(json.dumps(manifest, ensure_ascii=False, indent=2), encoding="utf-8")
    print(f"exported {len(files)} files, {len(blob):,} bytes")
    print(f"  bundle   : {out}")
    print(f"  manifest : {mpath}")
    print(f"  sha256   : {manifest['bundle_sha256'][:16]}")
    return 0


def cmd_import(args):
    """Load a portable bundle into the current account's vault."""
    aid = ensure_anchor()
    src = Path(args.dir)
    blob = src.read_bytes()
    mpath = Path(str(src) + ".manifest.json")
    manifest = json.loads(mpath.read_text(encoding="utf-8")) if mpath.exists() else {}
    want = manifest.get("bundle_sha256")
    if want and sha256(blob) != want:
        raise SystemExit(f"bundle hash mismatch: want {want[:16]} got {sha256(blob)[:16]}")
    b64 = base64.b64encode(blob).decode()
    chunks = [b64[i:i + CHUNK_CHARS] for i in range(0, len(b64), CHUNK_CHARS)]
    for i, c in enumerate(chunks):
        kv_put(aid, CHUNK_KEY.format(i=i), c)
    files = manifest.get("files", [])
    index = {
        "version": 1,
        "created_utc": __import__("datetime").datetime.now(
            __import__("datetime").timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        "anchor_automation": ANCHOR_NAME,
        "anchor_automation_id": aid,
        "bundle_bytes": len(blob),
        "bundle_sha256": sha256(blob),
        "chunks": len(chunks),
        "file_count": manifest.get("file_count", len(files)),
        "files": files,
        "imported_from": str(src),
        "notes": "Imported by ops/ax_vault.py. Credentials are never included.",
    }
    kv_put(aid, INDEX_KEY, index)
    for key in kv_keys(aid):
        if key.startswith("axvault:d:"):
            try:
                n = int(key.rsplit(":", 1)[1])
            except ValueError:
                continue
            if n >= len(chunks):
                kv_del(aid, key)
    print(f"imported {index['file_count']} files, {len(blob):,} bytes, {len(chunks)} chunks")
    print(f"anchor: {ANCHOR_NAME} ({aid})")
    return 0


def cmd_bootstrap(args):
    """Print the recovery path, and (re)store the self-recovery keys."""
    aid = ensure_anchor()
    tool_src = Path(__file__).read_bytes()
    kv_put(aid, "axvault:tool", tool_src.decode())
    readme = f"""# AX KNOWLEDGE VAULT — recovery

You are reading the durable copy. Nothing here is a credential.

The vault holds the AX knowledge set: the youtube-channel-builder skill, the
project memory, the ops rails and the channel scripts. It lives in the
OpenHands automation KV store, which survives a sandbox being destroyed.

Anchor automation : {ANCHOR_NAME}
Anchor id         : {aid}
Index key         : {INDEX_KEY}
Tool key          : axvault:tool  (this tool's own source, plain text)

Recover it with only OPENHANDS_API_KEY, no repo and no prior knowledge:

  # 1. fetch the tool (chicken-and-egg: it is stored before you arrive)
  python3 - <<'EOF'
  import json, os, urllib.request
  host = "https://app.all-hands.dev"
  aid  = "{aid}"
  def kv(key):
      req = urllib.request.Request(
          f"{{host}}/api/automation/v1/kv/{{key}}?automation_id={{aid}}",
          headers={{"Authorization": f"Bearer {{os.environ['OPENHANDS_API_KEY']}}"}})
      with urllib.request.urlopen(req, timeout=60) as r:
          v = json.load(r)["value"]
      return v["value"] if isinstance(v, dict) and set(v) == {{"value"}} else v
  open("ax_vault.py", "w").write(kv("axvault:tool"))
  EOF

  # 2. restore the knowledge set
  python3 ax_vault.py restore /workspace/project

Never pack a credential. The tool refuses files whose name carries "token",
"secret", "credential", "password" or "apikey", and files whose bytes match a
token shape.
"""
    kv_put(aid, "axvault:readme", readme)

    print("AX knowledge vault")
    print(f"  anchor automation : {ANCHOR_NAME}")
    print(f"  anchor id         : {aid}")
    print(f"  host              : {HOST}")
    print()
    print("A fresh sandbox needs no prior knowledge. The anchor automation is visible in")
    print("the automation list, and the secret AX_VAULT_BOOTSTRAP names it. To recover:")
    print(f"  read KV key 'axvault:readme' under automation {aid},")
    print("  write it to ax_vault.py, then run: python3 ax_vault.py restore <DIR>")
    return 0


def main():
    ap = argparse.ArgumentParser(description=__doc__,
                                 formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("command", choices=["ensure", "pack", "list", "restore", "verify",
                                         "bootstrap", "export", "import"])
    ap.add_argument("dir", nargs="?", default=".", help="destination for restore/export/import")
    ap.add_argument("--root", default=os.getcwd(), help="workspace root to pack/verify")
    a = ap.parse_args()
    if not API_KEY:
        raise SystemExit("OPENHANDS_API_KEY is not set")
    return {"ensure": lambda _: (print(ensure_anchor()), 0)[1],
            "pack": cmd_pack, "list": cmd_list,
            "restore": cmd_restore, "verify": cmd_verify,
            "bootstrap": cmd_bootstrap,
            "export": cmd_export, "import": cmd_import}[a.command](a)


if __name__ == "__main__":
    sys.exit(main())
