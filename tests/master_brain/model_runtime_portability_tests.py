#!/usr/bin/env python3
"""Acceptance test for model/runtime-independent A rehydration."""
from __future__ import annotations
import json, os, subprocess, sys, tempfile, time, urllib.request
from pathlib import Path
ROOT = Path(__file__).resolve().parents[2]
SERVER = ROOT / "AX_CONTROL_HUB" / "ax_control_hub_server.py"
STATE = ROOT / "AX_MASTER_BRAIN" / "AX_MASTER_STATE.json"
TASKS = ROOT / "AX_MASTER_BRAIN" / "AX_MASTER_TASK_REGISTRY_v2.json"
CONTRACT = ROOT / "AX_MASTER_BRAIN" / "AX_REHYDRATION_ADAPTER_SPEC.md"
def request(url, method="GET", body=None, token=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(url, data=data, method=method)
    if data is not None: req.add_header("Content-Type", "application/json")
    if token: req.add_header("Authorization", f"Bearer {token}")
    with urllib.request.urlopen(req, timeout=5) as response:
        return response.status, json.loads(response.read().decode())
def wait_health(base):
    for _ in range(50):
        try:
            status, payload = request(base + "/health")
            if status == 200 and payload.get("health_status") == "HEALTHY": return
        except Exception: time.sleep(0.1)
    raise AssertionError("runtime did not become healthy")
def run_profile(tmp, port, profile):
    runtime_root = tmp / profile
    runtime_root.mkdir(parents=True, exist_ok=True)
    state = runtime_root / "AX_MASTER_STATE.json"
    tasks = runtime_root / "AX_MASTER_TASK_REGISTRY_v2.json"
    contract = runtime_root / "AX_REHYDRATION_ADAPTER_SPEC.md"
    state.write_text(STATE.read_text(encoding="utf-8"), encoding="utf-8")
    tasks.write_text(TASKS.read_text(encoding="utf-8"), encoding="utf-8")
    contract.write_text(CONTRACT.read_text(encoding="utf-8"), encoding="utf-8")
    env = os.environ.copy()
    env.update({"AX_CONTROL_HUB_HOST":"127.0.0.1","AX_CONTROL_HUB_PORT":str(port),"AX_MASTER_BRAIN_DIR":str(runtime_root),"AX_MASTER_STATE_PATH":str(state),"AX_MASTER_TASK_REGISTRY_PATH":str(tasks),"AX_CONTROL_HUB_EVIDENCE_DIR":str(runtime_root/"evidence"),"AX_CONTROL_HUB_USERNAME":"portability-test","AX_CONTROL_HUB_PASSWORD":"portability-test-password","AX_RUNTIME_PROFILE":profile})
    proc = subprocess.Popen([sys.executable, str(SERVER)], cwd=str(ROOT), env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    base = f"http://127.0.0.1:{port}"
    try:
        wait_health(base)
        _, login = request(base + "/auth/login", "POST", {"username":"portability-test","password":"portability-test-password"})
        token = login["token"]
        _, state_payload = request(base + "/state", token=token)
        _, tasks_payload = request(base + "/tasks", token=token)
        _, challenge = request(base + "/m-a-check", "POST", {}, token)
        return proc, state_payload, tasks_payload, challenge
    except Exception:
        proc.terminate(); proc.wait(timeout=5); raise
def main():
    with tempfile.TemporaryDirectory() as td:
        tmp = Path(td)
        proc_a, state_a, tasks_a, challenge_a = run_profile(tmp,18788,"MODEL_RUNTIME_A")
        proc_b, state_b, tasks_b, challenge_b = run_profile(tmp,18789,"MODEL_RUNTIME_B")
        try:
            for state_payload, tasks_payload, challenge in ((state_a,tasks_a,challenge_a),(state_b,tasks_b,challenge_b)):
                assert state_payload["identity"] == "A"
                assert state_payload["authority"] == "K_FINAL_AUTHORITY"
                assert state_payload["source"] == "A_MASTER_BRAIN"
                assert state_payload["rehydration_status"] == "VERIFIED"
                assert len(tasks_payload["tasks"]) == 12
                assert challenge["identity_under_test"] == "A"
                assert challenge["verified"] is True
                assert challenge["checks"]["model_independence"] is True
            assert state_a["runtime_profile"] != state_b["runtime_profile"]
            assert challenge_a["runtime_profile"] != challenge_b["runtime_profile"]
            assert challenge_a["checks"] == challenge_b["checks"]
            print("MODEL_RUNTIME_PORTABILITY_PASS two distinct runtime profiles rehydrated the same authoritative A state")
        finally:
            for proc in (proc_a,proc_b):
                proc.terminate(); proc.wait(timeout=5)
if __name__ == "__main__": main()
