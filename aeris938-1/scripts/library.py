"""Asset library with manifests.

The library is the point: images, music and covers are keyed by a stable id and
recorded in a manifest, so a later run can reuse an asset instead of paying to
regenerate it, and a missing asset is a lookup miss rather than a guess.
"""
from __future__ import annotations

import hashlib
import json
import os
import time
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
LIBRARY = ROOT / "library"

KINDS = {
    "img": LIBRARY / "img",
    "music": LIBRARY / "music",
    "cover": LIBRARY / "covers",
}

# Bump when an entry's shape changes so old manifests stay readable.
SCHEMA_VERSION = 1


def sha256_file(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for block in iter(lambda: fh.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def manifest_path(kind: str) -> Path:
    if kind not in KINDS:
        raise ValueError(f"unknown kind {kind!r}; expected one of {sorted(KINDS)}")
    return KINDS[kind] / "manifest.json"


def load(kind: str) -> dict:
    path = manifest_path(kind)
    if not path.exists():
        return {"schema_version": SCHEMA_VERSION, "kind": kind, "entries": []}
    with open(path, encoding="utf-8") as fh:
        data = json.load(fh)
    data.setdefault("entries", [])
    return data


def save(kind: str, data: dict) -> Path:
    path = manifest_path(kind)
    path.parent.mkdir(parents=True, exist_ok=True)
    data["schema_version"] = SCHEMA_VERSION
    data["updated_at"] = time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())
    tmp = path.with_suffix(".json.tmp")
    with open(tmp, "w", encoding="utf-8") as fh:
        json.dump(data, fh, ensure_ascii=False, indent=2)
    os.replace(tmp, path)
    return path


def entry_id(kind: str, key: str) -> str:
    slug = "".join(c if c.isalnum() or c in "-_" else "-" for c in key).strip("-").lower()
    return f"{kind}-{slug}"


def find(kind: str, key: str) -> dict | None:
    """Look an asset up by its id. Returns None on a miss; never guesses."""
    want = entry_id(kind, key)
    for entry in load(kind)["entries"]:
        if entry.get("id") == want:
            return entry
    return None


def add(kind: str, key: str, file: Path, **fields) -> dict:
    """Record an asset. A file that is not there is a hard error, not a warning."""
    file = Path(file)
    if not file.exists():
        raise FileNotFoundError(f"cannot record missing asset: {file}")
    if file.stat().st_size == 0:
        raise ValueError(f"refusing to record zero-byte asset: {file}")
    data = load(kind)
    eid = entry_id(kind, key)
    entry = {
        "id": eid,
        "kind": kind,
        "file": str(file.relative_to(ROOT)) if file.is_relative_to(ROOT) else str(file),
        "bytes": file.stat().st_size,
        "sha256": sha256_file(file),
        "created_at": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
    }
    entry.update({k: v for k, v in fields.items() if v is not None})
    # Re-recording the same id replaces it, so a retry never duplicates.
    data["entries"] = [e for e in data["entries"] if e.get("id") != eid]
    data["entries"].append(entry)
    save(kind, data)
    return entry


def all_entries(kind: str) -> list[dict]:
    return load(kind)["entries"]


def summary() -> dict:
    out = {}
    for kind in KINDS:
        entries = all_entries(kind)
        out[kind] = {
            "count": len(entries),
            "bytes": sum(int(e.get("bytes") or 0) for e in entries),
        }
    return out
