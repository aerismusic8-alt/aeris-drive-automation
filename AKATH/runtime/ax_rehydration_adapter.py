#!/usr/bin/env python3
"""Deterministic A MASTER BRAIN rehydration adapter for AKATH runtime."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any, Mapping

ROOT = Path(__file__).resolve().parents[2]
STATE_PATH = Path(os.getenv("AX_MASTER_STATE_PATH", ROOT / "AX_MASTER_BRAIN" / "AX_MASTER_STATE.json"))
TASK_PATH = Path(os.getenv("AX_MASTER_TASK_REGISTRY_PATH", ROOT / "AX_MASTER_BRAIN" / "AX_MASTER_TASK_REGISTRY_v2.json"))
CONTRACT_PATH = Path(os.getenv("AX_REHYDRATION_CONTRACT_PATH", ROOT / "AX_MASTER_BRAIN" / "AX_REHYDRATION_ADAPTER_SPEC.md"))

REQUIRED_STATE = {
    "storage_role": "A_MASTER_BRAIN_SINGLE_SOURCE_OF_TRUTH",
    "authority": "K_FINAL_AUTHORITY",
    "identity_authority": "A_MASTER_BRAIN",
}


def fail(*reasons: str) -> dict[str, Any]:
    return {
        "rehydration_status": "NOT_VERIFIED",
        "identity": "A",
        "identity_source": str(STATE_PATH),
        "task_registry_source": str(TASK_PATH),
        "evidence_checked": False,
        "verification_checked": False,
        "source_conflicts": [],
        "execution_authorized": False,
        "failure_reasons": list(reasons),
    }


def load_json(path: Path, missing_code: str, malformed_code: str) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    if not path.is_file():
        return None, fail(missing_code)
    try:
        value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        return None, fail(malformed_code)
    if not isinstance(value, dict):
        return None, fail(malformed_code)
    return value, None


def validate_current_work(registry: Mapping[str, Any]) -> dict[str, Any]:
    current = registry.get("current_work")
    errors: list[str] = []
    if not isinstance(current, Mapping):
        errors.append("CURRENT_WORK_MISSING")
        return {"valid": False, "task_id": None, "errors": errors}
    if current.get("active") is not True:
        errors.append("CURRENT_WORK_NOT_ACTIVE")
    task_id = str(current.get("task_id") or "").strip()
    if not task_id:
        errors.append("CURRENT_WORK_TASK_ID_MISSING")
    tasks = registry.get("tasks")
    task_ids = {
        str(task.get("task") or "").strip()
        for task in tasks
        if isinstance(task, Mapping) and str(task.get("task") or "").strip()
    } if isinstance(tasks, list) else set()
    if task_id and task_id not in task_ids:
        errors.append("CURRENT_WORK_TASK_NOT_FOUND")
    return {"valid": not errors, "task_id": task_id or None, "errors": errors}


def extract_current_work(registry: Mapping[str, Any]) -> dict[str, Any]:
    validation = validate_current_work(registry)
    if not validation["valid"]:
        raise ValueError("CURRENT_WORK_INVALID:" + ",".join(validation["errors"]))
    current = registry["current_work"]
    return dict(current)


def rehydrate() -> dict[str, Any]:
    if not CONTRACT_PATH.is_file():
        return fail("REHYDRATION_CONTRACT_MISSING")

    state, error = load_json(STATE_PATH, "MASTER_STATE_MISSING", "MASTER_STATE_MALFORMED")
    if error:
        return error
    tasks, error = load_json(TASK_PATH, "TASK_REGISTRY_MISSING", "TASK_REGISTRY_MALFORMED")
    if error:
        return error
    assert state is not None and tasks is not None

    reasons: list[str] = []
    if state.get("identity", {}).get("name") != "A":
        reasons.append("IDENTITY_NOT_A")
    for key, expected in REQUIRED_STATE.items():
        if state.get(key) != expected:
            reasons.append(f"STATE_{key.upper()}_INVALID")
    if state.get("model_independence") is not True:
        reasons.append("MODEL_INDEPENDENCE_INVALID")
    if str(tasks.get("schema_version")) != "2.1":
        reasons.append("TASK_REGISTRY_VERSION_INVALID")
    if state.get("status") != "VERIFIED":
        reasons.append("MASTER_STATE_NOT_VERIFIED")

    current_validation = validate_current_work(tasks)
    if not current_validation["valid"]:
        reasons.extend(current_validation["errors"])

    if reasons:
        return fail(*reasons)

    current_work = extract_current_work(tasks)
    return {
        "rehydration_status": "VERIFIED",
        "identity": "A",
        "identity_source": str(STATE_PATH),
        "task_registry_source": str(TASK_PATH),
        "evidence_checked": True,
        "verification_checked": True,
        "source_conflicts": [],
        "execution_authorized": False,
        "failure_reasons": [],
        "mission": state.get("identity", {}).get("mission"),
        "task_count": len(tasks.get("tasks", [])) if isinstance(tasks.get("tasks"), list) else None,
        "master_state_version": state.get("schema_version"),
        "current_work": current_work,
        "current_work_task_id": current_work["task_id"],
    }


def main() -> int:
    if len(sys.argv) != 2 or sys.argv[1] != "rehydrate":
        print(json.dumps(fail("INVALID_INVOCATION"), ensure_ascii=False))
        return 2
    result = rehydrate()
    print(json.dumps(result, ensure_ascii=False))
    return 0 if result["rehydration_status"] == "VERIFIED" else 1


if __name__ == "__main__":
    raise SystemExit(main())
