"""Generate a canonical logical File ID manifest without embedding secrets."""
from __future__ import annotations

import hashlib
import json
import uuid
from pathlib import Path


class FileIdManifestError(ValueError):
    pass


class FileIdManifestBuilder:
    @staticmethod
    def generate(root: Path, paths: list[str], existing_manifest: Path | None = None) -> dict:
        root = Path(root).resolve()
        existing: dict[str, dict] = {}
        if existing_manifest is not None and Path(existing_manifest).is_file():
            try:
                raw = json.loads(Path(existing_manifest).read_text(encoding="utf-8"))
                for entry in raw.get("entries", []):
                    existing[entry["path"]] = entry
            except (OSError, ValueError, KeyError, TypeError) as exc:
                raise FileIdManifestError("FILE_ID_MANIFEST_INVALID") from exc

        entries = []
        seen_ids: set[str] = set()
        for rel_path in paths:
            if not isinstance(rel_path, str) or not rel_path:
                raise FileIdManifestError("FILE_ID_PATH_INVALID")
            candidate = (root / rel_path).resolve()
            try:
                candidate.relative_to(root)
            except ValueError as exc:
                raise FileIdManifestError("FILE_PATH_ESCAPES_ROOT") from exc
            if not candidate.is_file():
                raise FileIdManifestError("FILE_MISSING")

            prior = existing.get(rel_path)
            file_id = prior.get("file_id") if prior else None
            if not file_id:
                file_id = str(uuid.uuid4())
            if file_id in seen_ids:
                raise FileIdManifestError("DUPLICATE_FILE_ID")
            seen_ids.add(file_id)

            entries.append({
                "file_id": file_id,
                "path": rel_path,
                "content_sha256": hashlib.sha256(candidate.read_bytes()).hexdigest(),
            })

        return {
            "schema_version": "1.0",
            "registry_role": "A_MASTER_BRAIN_FILE_ID_PERSISTENCE",
            "entries": entries,
        }

    @staticmethod
    def write(manifest_path: Path, document: dict) -> None:
        path = Path(manifest_path)
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
