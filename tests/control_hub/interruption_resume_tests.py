#!/usr/bin/env python3
"""Acceptance test for interruption during command lifecycle and safe resume."""
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
PORT = "8793"
BASE = f"http://127.0.0.1:{PORT}"


def request(method, path, payload=None, token=None):
    data = json.dumps(payload).encode() if payload is not None else None
    req = urllib.request.Request(BASE + path, data=data, method=method)
    if data is not None:
        req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, json.loads(response.read())
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read())
    except (urllib.error.URLError, ConnectionError):
        return 599, {"error_code": "INTERRUPTED_CONNECTION"}


def start(env):
    proc = subprocess.Popen([sys.executable, str(SERVER)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    for _ in range(50):
        try:
            with urllib.request.urlopen(BASE + "/health", timeout=0.2):
                return proc
        except Exception:
            time.sleep(0.05)
    stderr = proc.stderr.read() if proc.stderr else ""
    proc.terminate()
    raise AssertionError(f"runtime did not become healthy: {stderr}")


def stop(proc):
    if proc.poll() is None:
        proc.terminate()
        proc.wait(timeout=5)


def main():
    with tempfile.TemporaryDirectory() as td:
        root = Path(td)
        mb = root / "AX_MASTER_BRAIN"
        mb.mkdir()
        (mb / "AX_MASTER_STATE.json").write_text(STATE.read_text(encoding="utf-8"), encoding="utf-8")
        (mb / "AX_MASTER_TASK_REGISTRY_v2.json").write_text(TASKS.read_text(encoding="utf-8"), encoding="utf-8")
        (mb / "AX_REHYDRATION_ADAPTER_SPEC.md").write_text(CONTRACT.read_text(encoding="utf-8"), encoding="utf-8")
        evidence_dir = mb / "evidence"
        env = os.environ.copy()
        env.update({
            "AX_CONTROL_HUB_ROOT": str(root),
            "AX_MASTER_BRAIN_DIR": str(mb),
            "AX_MASTER_STATE_PATH": str(mb / "AX_MASTER_STATE.json"),
            "AX_MASTER_TASK_REGISTRY_PATH": str(mb / "AX_MASTER_TASK_REGISTRY_v2.json"),
            "AX_CONTROL_HUB_PORT": PORT,
            "AX_CONTROL_HUB_USERNAME": "K",
            "AX_CONTROL_HUB_PASSWORD": "test-secret",
            "AX_CONTROL_HUB_EVIDENCE_DIR": str(evidence_dir),
            "AX_CONTROL_HUB_INTERRUPT_AFTER_EVIDENCE": "1",
        })
        payload = {
            "request_id": "req-interrupt-001",
            "idempotency_key": "idem-interrupt-001",
            "actor": "K",
            "command": "health_check",
            "args": {},
            "requested_at": "2026-09-03T00:00:00Z",
        }

        proc = start(env)
        try:
            status, login = request("POST", "/auth/login", {"username": "K", "password": "test-secret"})
            assert status == 200
            token = login["token"]
            status, _ = request("POST", "/command", payload, token)
            assert status in {200, 503, 599}
        finally:
            if proc.poll() is None:
                stop(proc)

        evidence_files = list(evidence_dir.glob("*.json"))
        assert len(evidence_files) == 1, "interrupted lifecycle must leave one durable pending record"
        pending = json.loads(evidence_files[0].read_text(encoding="utf-8"))
        assert pending["request_id"] == payload["request_id"]
        assert pending["lifecycle_status"] == "PENDING_STATE_WRITEBACK"

        resume_env = dict(env)
        resume_env.pop("AX_CONTROL_HUB_INTERRUPT_AFTER_EVIDENCE", None)
        proc = start(resume_env)
        try:
            status, login = request("POST", "/auth/login", {"username": "K", "password": "test-secret"})
            assert status == 200
            token = login["token"]
            status, state = request("GET", "/state", token=token)
            assert status == 200
            assert state["last_verified_evidence"]["request_id"] == payload["request_id"]
            status, evidence = request("GET", "/evidence/req-interrupt-001", token=token)
            assert status == 200
            assert evidence["lifecycle_status"] == "COMPLETED"
            assert evidence["verification_status"] == "VERIFIED"
            status, duplicate = request("POST", "/command", payload, token)
            assert status == 409
            assert duplicate["error_code"] == "DUPLICATE_REQUEST"
            assert len(list(evidence_dir.glob("*.json"))) == 1
            print("INTERRUPTION_RESUME_PASS interrupted lifecycle resumed without duplicate execution")
        finally:
            stop(proc)


if __name__ == "__main__":
    main()
