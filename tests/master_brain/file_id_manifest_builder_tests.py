#!/usr/bin/env python3
"""TDD acceptance tests for canonical File ID manifest generation."""
import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from AX_CONTROL_HUB.file_id_manifest_builder import FileIdManifestBuilder


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        brain = root / "AX_MASTER_BRAIN"
        brain.mkdir()
        (brain / "AX_MASTER_STATE.json").write_text('{"identity_authority":"A_MASTER_BRAIN"}\n', encoding="utf-8")
        (brain / "AX_MASTER_TASK_REGISTRY_v2.json").write_text('{"schema_version":"2.0"}\n', encoding="utf-8")
        manifest = root / "FILE_ID_MANIFEST.json"

        first = FileIdManifestBuilder.generate(root, [
            "AX_MASTER_BRAIN/AX_MASTER_STATE.json",
            "AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json",
        ])
        FileIdManifestBuilder.write(manifest, first)
        loaded = json.loads(manifest.read_text(encoding="utf-8"))
        ids_first = {entry["path"]: entry["file_id"] for entry in loaded["entries"]}
        assert len(ids_first) == 2
        assert all(ids_first.values())
        assert all(entry["content_sha256"] for entry in loaded["entries"])

        second = FileIdManifestBuilder.generate(root, list(ids_first))
        ids_second = {entry["path"]: entry["file_id"] for entry in second["entries"]}
        assert ids_second == ids_first, "logical IDs must persist across regeneration"

        (brain / "AX_MASTER_STATE.json").write_text('{"identity_authority":"A_MASTER_BRAIN","v":2}\n', encoding="utf-8")
        third = FileIdManifestBuilder.generate(root, list(ids_first))
        by_path = {entry["path"]: entry for entry in third["entries"]}
        assert by_path["AX_MASTER_BRAIN/AX_MASTER_STATE.json"]["file_id"] == ids_first["AX_MASTER_BRAIN/AX_MASTER_STATE.json"]
        assert by_path["AX_MASTER_BRAIN/AX_MASTER_STATE.json"]["content_sha256"] != loaded["entries"][0]["content_sha256"]

    print("FILE_ID_MANIFEST_BUILDER_PASS stable_ids, hashes, regeneration")


if __name__ == "__main__":
    main()
