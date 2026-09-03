#!/usr/bin/env python3
"""Generate and verify the canonical A Master Brain File ID manifest."""
from __future__ import annotations

import json
from pathlib import Path

from AX_CONTROL_HUB.file_id_manifest_builder import FileIdManifestBuilder

ROOT = Path(__file__).resolve().parents[1]
MANIFEST = ROOT / "AX_MASTER_BRAIN" / "FILE_ID_MANIFEST.json"
CANONICAL_PATHS = [
    "AX_MASTER_BRAIN/AX_MASTER_BRAIN_SPEC.md",
    "AX_MASTER_BRAIN/AX_MASTER_STATE.json",
    "AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json",
    "AX_MASTER_BRAIN/AX_REHYDRATION_ADAPTER_SPEC.md",
    "AX_MASTER_BRAIN/M_A_IDENTITY_CHALLENGE_KEY.md",
]


def main() -> None:
    existing = MANIFEST if MANIFEST.is_file() else None
    document = FileIdManifestBuilder.generate(ROOT, CANONICAL_PATHS, existing_manifest=existing)
    if len(document["entries"]) != len(CANONICAL_PATHS):
        raise SystemExit("CANONICAL_FILE_ID_MANIFEST_INCOMPLETE")
    FileIdManifestBuilder.write(MANIFEST, document)
    print(json.dumps({"status": "CANONICAL_FILE_ID_MANIFEST_GENERATED", "entries": len(document["entries"])}, ensure_ascii=False))


if __name__ == "__main__":
    main()
