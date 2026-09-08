#!/usr/bin/env python3
"""Acceptance tests for the AKATH -> A_MASTER_BRAIN rehydration adapter."""
from __future__ import annotations
import json
import subprocess
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / "AKATH" / "runtime" / "ax_rehydration_adapter.py"
STATE = ROOT / "AX_MASTER_BRAIN" / "AX_MASTER_STATE.json"
TASKS = ROOT / "AX_MASTER_BRAIN" / "AX_MASTER_TASK_REGISTRY_v2.json"
CONTRACT = ROOT / "AX_MASTER_BRAIN" / "AX_REHYDRATION_ADAPTER_SPEC.md"


def run(*args: str, env: dict[str, str] | None = None) -> tuple[int, dict]:
    p = subprocess.run(
        [sys.executable, str(ADAPTER), *args],
        cwd=ROOT,
        env=env,
        text=True,
        capture_output=True,
    )
    out = json.loads(p.stdout or "{}")
    return p.returncode, out


def main() -> None:
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        state = root / "AX_MASTER_STATE.json"
        tasks = root / "AX_MASTER_TASK_REGISTRY_v2.json"
        contract = root / "AX_REHYDRATION_ADAPTER_SPEC.md"
        state.write_text(STATE.read_text(encoding="utf-8"), encoding="utf-8")
        tasks.write_text(TASKS.read_text(encoding="utf-8"), encoding="utf-8")
        contract.write_text(CONTRACT.read_text(encoding="utf-8"), encoding="utf-8")
        env = __import__("os").environ.copy()
        env.update({
            "AX_MASTER_STATE_PATH": str(state),
            "AX_MASTER_TASK_REGISTRY_PATH": str(tasks),
            "AX_REHYDRATION_CONTRACT_PATH": str(contract),
        })

        registry = json.loads(tasks.read_text(encoding="utf-8"))
        assert registry["schema_version"] == "2.2", registry
        assert isinstance(registry.get("tasks"), list), registry
        assert len(registry["tasks"]) == 12, len(registry["tasks"])
        ids = [task.get("task_id") for task in registry["tasks"]]
        assert all(ids), ids
        assert len(ids) == len(set(ids)), ids
        assert registry["current_work"]["task_id"] in ids, registry["current_work"]
        current = next(task for task in registry["tasks"] if task["task_id"] == registry["current_work"]["task_id"])
        assert current["details"]["current_step"] == "CONTROL_PLANE_BLOCKER_REPAIR", current
        assert current["details"]["next_step"] == "RUN_SELF_HOSTED_XM_VERIFICATION", current

        rc, result = run("rehydrate", env=env)
        assert rc == 0, result
        assert result["rehydration_status"] == "VERIFIED", result
        assert result["identity"] == "A", result
        assert result["identity_source"].endswith("AX_MASTER_STATE.json"), result
        assert result["task_registry_source"].endswith("AX_MASTER_TASK_REGISTRY_v2.json"), result
        assert result["evidence_checked"] is True and result["verification_checked"] is True, result
        assert result["source_conflicts"] == [], result
        assert result["task_count"] == 12, result
        assert result["task_ids"] == ids, result
        assert result["current_work_task_id"] == registry["current_work"]["task_id"], result
        assert result["current_work"] == current, result

        tasks.unlink()
        rc, result = run("rehydrate", env=env)
        assert rc != 0, result
        assert result["rehydration_status"] == "NOT_VERIFIED", result
        assert result["execution_authorized"] is False, result
        assert "TASK_REGISTRY_MISSING" in result["failure_reasons"], result

    print("REHYDRATION_ADAPTER_PASS authoritative task registry + exact count + fail-closed missing registry")


if __name__ == "__main__":
    main()
