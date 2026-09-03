#!/usr/bin/env python3
"""Acceptance tests for command evidence persistence and verification linkage."""
from __future__ import annotations

import json
import os
import subprocess
import sys
import tempfile
import time
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "AX_CONTROL_HUB" / "ax_control_hub_server.py"
STATE = ROOT / "AX_MASTER_BRAIN" / "AX_MASTER_STATE.json"
TASKS = ROOT / "AX_MASTER_BRAIN" / "AX_MASTER_TASK_REGISTRY_v2.json"
CONTRACT = ROOT / "AX_MASTER_BRAIN" / "AX_REHYDRATION_ADAPTER_SPEC.md"


def post(base, path, payload, token=None):
    req = urllib.request.Request(base + path, data=json.dumps(payload).encode(), method="POST")
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=5) as r:
            return r.status, json.loads(r.read())
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read())


def get(base, path, token):
    req = urllib.request.Request(base + path)
    req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=5) as r:
        return r.status, json.loads(r.read())


def main():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        mb = root / "AX_MASTER_BRAIN"
        mb.mkdir()
        state = json.loads(STATE.read_text(encoding="utf-8"))
        tasks = json.loads(TASKS.read_text(encoding="utf-8"))
        (mb / "AX_MASTER_STATE.json").write_text(json.dumps(state), encoding="utf-8")
        (mb / "AX_MASTER_TASK_REGISTRY_v2.json").write_text(json.dumps(tasks), encoding="utf-8")
        (mb / "AX_REHYDRATION_ADAPTER_SPEC.md").write_text(CONTRACT.read_text(encoding="utf-8"), encoding="utf-8")
        evidence_dir = mb / "evidence"
        env = os.environ.copy()
        env.update({
            "AX_CONTROL_HUB_ROOT": str(root),
            "AX_MASTER_BRAIN_DIR": str(mb),
            "AX_MASTER_STATE_PATH": str(mb / "AX_MASTER_STATE.json"),
            "AX_MASTER_TASK_REGISTRY_PATH": str(mb / "AX_MASTER_TASK_REGISTRY_v2.json"),
            "AX_CONTROL_HUB_PORT": "8791",
            "AX_CONTROL_HUB_USERNAME": "K",
            "AX_CONTROL_HUB_PASSWORD": "test-secret",
            "AX_CONTROL_HUB_EVIDENCE_DIR": str(evidence_dir),
        })
        proc = subprocess.Popen([sys.executable, str(SERVER)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            base = "http://127.0.0.1:8791"
            for _ in range(50):
                try:
                    with urllib.request.urlopen(base + "/health", timeout=0.2):
                        break
                except Exception:
                    time.sleep(0.05)
            _, login = post(base, "/auth/login", {"username": "K", "password": "test-secret"})
            token = login["token"]
            request_id = "req-evidence-001"
            idem = "idem-evidence-001"
            status, command = post(base, "/command", {
                "request_id": request_id,
                "idempotency_key": idem,
                "actor": "K",
                "command": "health_check",
                "args": {},
                "requested_at": "2026-09-03T00:00:00Z",
            }, token)
            assert status == 200
            assert command["request_id"] == request_id
            assert command["evidence_status"] == "RECORDED"
            _, evidence = get(base, "/evidence/" + request_id, token)
            assert evidence["request_id"] == request_id
            assert evidence["execution_status"] == "EXECUTED"
            assert evidence["verification_status"] == "VERIFIED"
            assert evidence["evidence"]
            assert evidence["evidence"][0]["request_id"] == request_id
            assert evidence_dir.exists()
            files = list(evidence_dir.glob("*.json"))
            assert len(files) == 1
            status, duplicate = post(base, "/command", {
                "request_id": "req-evidence-002",
                "idempotency_key": idem,
                "actor": "K",
                "command": "health_check",
                "args": {},
                "requested_at": "2026-09-03T00:01:00Z",
            }, token)
            assert status == 409
            assert duplicate["error_code"] == "DUPLICATE_REQUEST"
            assert len(list(evidence_dir.glob("*.json"))) == 1
            print("EVIDENCE_WRITEBACK_PASS command->evidence->verification and idempotency")
        finally:
            proc.terminate()
            proc.wait(timeout=5)


if __name__ == "__main__":
    main()
