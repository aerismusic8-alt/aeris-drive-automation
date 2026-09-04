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

        rc, result = run("rehydrate", env=env)
        assert rc == 0, result
        assert result["rehydration_status"] == "VERIFIED", result
        assert result["identity"] == "A", result
        assert result["identity_source"].endswith("AX_MASTER_STATE.json"), result
        assert result["task_registry_source"].endswith("AX_MASTER_TASK_REGISTRY_v2.json"), result
        assert result["evidence_checked"] is True and result["verification_checked"] is True, result
        assert result["source_conflicts"] == [], result

        tasks.unlink()
        rc, result = run("rehydrate", env=env)
        assert rc != 0, result
        assert result["rehydration_status"] == "NOT_VERIFIED", result
        assert result["execution_authorized"] is False, result
        assert "TASK_REGISTRY_MISSING" in result["failure_reasons"], result

    print("REHYDRATION_ADAPTER_PASS authoritative load + fail-closed missing registry")


if __name__ == "__main__":
    main()
