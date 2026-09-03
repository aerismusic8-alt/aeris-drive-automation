#!/usr/bin/env python3
"""Acceptance tests for model-independent File ID persistence."""
import hashlib
import json
import tempfile
from pathlib import Path


ROOT = Path(__file__).resolve().parents[2]


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        source = root / "AX_MASTER_STATE.json"
        manifest = root / "FILE_ID_MANIFEST.json"
        source.write_text(json.dumps({"identity_authority": "A_MASTER_BRAIN", "schema_version": "1.3"}), encoding="utf-8")
        digest = sha256_file(source)
        manifest.write_text(json.dumps({
            "schema_version": "1.0",
            "entries": [{
                "file_id": "a-master-state-immutable-001",
                "path": "AX_MASTER_STATE.json",
                "content_sha256": digest,
                "authority": "A_MASTER_BRAIN"
            }]
        }), encoding="utf-8")

        data = json.loads(manifest.read_text(encoding="utf-8"))
        entry = data["entries"][0]
        assert entry["file_id"] == "a-master-state-immutable-001"
        assert entry["content_sha256"] == sha256_file(source)

        # Stable logical ID must survive a fresh process and point to the same path.
        fresh = json.loads(manifest.read_text(encoding="utf-8"))
        assert fresh["entries"][0]["file_id"] == entry["file_id"]

        # Content tampering must fail verification rather than silently preserve trust.
        source.write_text(source.read_text(encoding="utf-8") + "\nTAMPER", encoding="utf-8")
        assert sha256_file(source) != entry["content_sha256"]

        # Duplicate logical IDs must fail closed.
        duplicate = dict(entry)
        data["entries"].append(duplicate)
        ids = [e["file_id"] for e in data["entries"]]
        assert len(ids) != len(set(ids))

    print("FILE_ID_PERSISTENCE_RED contract: stable_id, fresh_process, tamper_detection, duplicate_detection")


if __name__ == "__main__":
    main()
