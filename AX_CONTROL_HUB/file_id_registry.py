"""Fail-closed persistent File ID registry for A Master Brain files."""
from __future__ import annotations

import hashlib
import json
from pathlib import Path


class FileIdPersistenceError(ValueError):
    pass


class FileIdRegistry:
    def __init__(self, manifest_path: Path, entries: dict[str, dict]):
        self.manifest_path = Path(manifest_path)
        self.entries = entries

    @classmethod
    def load(cls, manifest_path: Path) -> "FileIdRegistry":
        path = Path(manifest_path)
        if not path.is_file():
            raise FileIdPersistenceError("FILE_ID_MANIFEST_MISSING")
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
            entries = data["entries"]
        except (OSError, ValueError, KeyError, TypeError) as exc:
            raise FileIdPersistenceError("FILE_ID_MANIFEST_INVALID") from exc
        if not isinstance(entries, list):
            raise FileIdPersistenceError("FILE_ID_ENTRIES_INVALID")
        result = {}
        for entry in entries:
            if not isinstance(entry, dict):
                raise FileIdPersistenceError("FILE_ID_ENTRY_INVALID")
            file_id = entry.get("file_id")
            rel_path = entry.get("path")
            digest = entry.get("content_sha256")
            if not all(isinstance(x, str) and x for x in (file_id, rel_path, digest)):
                raise FileIdPersistenceError("FILE_ID_ENTRY_INCOMPLETE")
            if file_id in result:
                raise FileIdPersistenceError("DUPLICATE_FILE_ID")
            result[file_id] = entry
        return cls(path, result)

    def resolve(self, file_id: str, root: Path) -> Path:
        entry = self.entries.get(file_id)
        if entry is None:
            raise FileIdPersistenceError("FILE_ID_NOT_FOUND")
        candidate = (Path(root) / entry["path"]).resolve()
        root_resolved = Path(root).resolve()
        try:
            candidate.relative_to(root_resolved)
        except ValueError as exc:
            raise FileIdPersistenceError("FILE_PATH_ESCAPES_ROOT") from exc
        if not candidate.is_file():
            raise FileIdPersistenceError("FILE_MISSING")
        actual = hashlib.sha256(candidate.read_bytes()).hexdigest()
        if actual != entry["content_sha256"]:
            raise FileIdPersistenceError("FILE_CONTENT_TAMPERED")
        return candidate

    def verification_evidence(self, file_id: str, root: Path) -> dict[str, str]:
        """Resolve and hash-check a file, returning auditable verification evidence."""
        candidate = self.resolve(file_id, root)
        entry = self.entries[file_id]
        return {
            "file_id": file_id,
            "path": entry["path"],
            "content_sha256": entry["content_sha256"],
            "verification_status": "VERIFIED",
        }

    def verify_all(self, root: Path) -> None:
        for file_id in self.entries:
            self.resolve(file_id, root)
