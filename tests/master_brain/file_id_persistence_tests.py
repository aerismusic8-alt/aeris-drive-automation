#!/usr/bin/env python3
"""Acceptance tests for model-independent File ID persistence."""
import hashlib
import json
import tempfile
from pathlib import Path
import sys


ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from AX_CONTROL_HUB.file_id_registry import FileIdPersistenceError, FileIdRegistry


def sha256_file(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def expect_error(code: str, fn) -> None:
    try:
        fn()
    except FileIdPersistenceError as exc:
        assert str(exc) == code, f"expected {code}, got {exc}"
    else:
        raise AssertionError(f"expected FileIdPersistenceError({code})")


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

        registry = FileIdRegistry.load(manifest)
        resolved = registry.resolve("a-master-state-immutable-001", root)
        assert resolved == source.resolve()

        # Verification evidence must preserve the logical ID independently of content hash.
        evidence = registry.verification_evidence("a-master-state-immutable-001", root)
        assert evidence["file_id"] == "a-master-state-immutable-001"
        assert evidence["verification_status"] == "VERIFIED"
        assert evidence["path"] == "AX_MASTER_STATE.json"
        assert evidence["content_sha256"] == digest

        # Stable logical ID must survive a fresh process and point to the same file.
        fresh_registry = FileIdRegistry.load(manifest)
        assert fresh_registry.resolve("a-master-state-immutable-001", root) == source.resolve()
        fresh_evidence = fresh_registry.verification_evidence("a-master-state-immutable-001", root)
        assert fresh_evidence["file_id"] == evidence["file_id"]

        # Content tampering must fail verification rather than silently preserve trust.
        source.write_text(source.read_text(encoding="utf-8") + "\nTAMPER", encoding="utf-8")
        expect_error(
            "FILE_CONTENT_TAMPERED",
            lambda: fresh_registry.resolve("a-master-state-immutable-001", root),
        )
        expect_error(
            "FILE_CONTENT_TAMPERED",
            lambda: fresh_registry.verification_evidence("a-master-state-immutable-001", root),
        )

        # Duplicate logical IDs must fail closed during manifest load.
        tampered_manifest = root / "DUPLICATE_FILE_ID_MANIFEST.json"
        entry = json.loads(manifest.read_text(encoding="utf-8"))["entries"][0]
        tampered_manifest.write_text(json.dumps({"schema_version": "1.0", "entries": [entry, entry]}), encoding="utf-8")
        expect_error("DUPLICATE_FILE_ID", lambda: FileIdRegistry.load(tampered_manifest))

        # Path traversal must fail closed.
        escape_manifest = root / "ESCAPE_MANIFEST.json"
        escape_manifest.write_text(json.dumps({
            "schema_version": "1.0",
            "entries": [{"file_id": "escape-001", "path": "../outside.txt", "content_sha256": digest}],
        }), encoding="utf-8")
        expect_error("FILE_PATH_ESCAPES_ROOT", lambda: FileIdRegistry.load(escape_manifest).resolve("escape-001", root))

        # Missing manifest must fail closed.
        expect_error("FILE_ID_MANIFEST_MISSING", lambda: FileIdRegistry.load(root / "missing.json"))

    print("FILE_ID_PERSISTENCE_PASS stable_id, fresh_process, evidence_identity, tamper_detection, duplicate_detection, path_guard, missing_manifest")


if __name__ == "__main__":
    main()
