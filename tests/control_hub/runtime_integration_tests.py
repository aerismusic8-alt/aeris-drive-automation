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


def request(base, method, path, payload=None, token=None):
    data = None if payload is None else json.dumps(payload).encode("utf-8")
    req = urllib.request.Request(base + path, data=data, method=method)
    req.add_header("Content-Type", "application/json")
    if token:
        req.add_header("Authorization", f"Bearer {token}")
    try:
        with urllib.request.urlopen(req, timeout=5) as response:
            return response.status, json.loads(response.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        return exc.code, json.loads(exc.read().decode("utf-8"))


def wait_for_health(base):
    for _ in range(50):
        try:
            status, body = request(base, "GET", "/health")
            if status == 200:
                return body
        except (urllib.error.URLError, ConnectionError):
            pass
        time.sleep(0.05)
    raise AssertionError("runtime did not become healthy")


def main():
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        master = root / "AX_MASTER_BRAIN"
        master.mkdir()
        (master / "AX_MASTER_STATE.json").write_text(json.dumps({
            "status": "INITIALIZED_PENDING_VERIFICATION",
            "authority": "K_FINAL_AUTHORITY",
            "identity_authority": "A_MASTER_BRAIN",
            "storage_role": "A_MASTER_BRAIN_SINGLE_SOURCE_OF_TRUTH",
            "model_independence": True,
            "identity": {"name": "A", "role": "AI Executive Orchestrator Master Brain"},
        }), encoding="utf-8")
        (master / "AX_MASTER_TASK_REGISTRY_v2.json").write_text(json.dumps({
            "schema_version": "2.0",
            "tasks": [{"id": "T1", "status": "QUEUED"}],
        }), encoding="utf-8")
        (master / "AX_REHYDRATION_ADAPTER_SPEC.md").write_text("contract", encoding="utf-8")

        env = os.environ.copy()
        env.update({
            "AX_CONTROL_HUB_ROOT": str(root),
            "AX_MASTER_BRAIN_DIR": str(master),
            "AX_MASTER_STATE_PATH": str(master / "AX_MASTER_STATE.json"),
            "AX_MASTER_TASK_REGISTRY_PATH": str(master / "AX_MASTER_TASK_REGISTRY_v2.json"),
            "AX_CONTROL_HUB_USERNAME": "K-test",
            "AX_CONTROL_HUB_PASSWORD": "integration-password",
            "AX_CONTROL_HUB_PORT": "18787",
        })
        base = "http://127.0.0.1:18787"
        proc = subprocess.Popen([sys.executable, str(SERVER)], env=env, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
        try:
            health = wait_for_health(base)
            assert health["health_status"] == "HEALTHY" and health["execution_status"] == "UNKNOWN"  # I1

            status, body = request(base, "GET", "/state")
            assert status == 401 and body["error_code"] == "AUTH_REQUIRED"  # I6

            status, body = request(base, "POST", "/auth/login", {"username": "K-test", "password": "integration-password"})
            assert status == 200 and body["authenticated"] is True  # I2
            token = body["token"]

            status, body = request(base, "GET", "/state", token=token)
            assert status == 200 and body["source"] == "A_MASTER_BRAIN" and body["identity"] == "A"  # I3

            status, body = request(base, "GET", "/tasks", token=token)
            assert status == 200 and body["tasks"][0]["id"] == "T1"  # I4

            status, body = request(base, "POST", "/m-a-check", token=token)
            assert status == 200 and body["source"] == "A_MASTER_BRAIN" and body["identity_under_test"] == "A"  # I5

            request_id = "integration-001"
            command = {"request_id": request_id, "idempotency_key": "integration-key-001", "actor": "K", "command": "health_check", "args": {}}
            status, body = request(base, "POST", "/command", command, token=token)
            assert status == 200 and body["request_id"] == request_id and body["evidence_status"] == "RECORDED"  # I7
            assert body["verification_status"] == "VERIFIED"

            status, body = request(base, "POST", "/command", command, token=token)
            assert status == 409 and body["error_code"] == "DUPLICATE_REQUEST"  # I8

            status, body = request(base, "GET", f"/evidence/{request_id}", token=token)
            assert status == 200 and body["verification_status"] == "VERIFIED"  # I9
            assert body["request_id"] == request_id and body["evidence"]
            assert body["verification"]["financial_live_execution"] is False

            status, body = request(base, "POST", "/auth/logout", token=token)
            assert status == 200 and body["logged_out"] is True  # I10
            status, body = request(base, "GET", "/state", token=token)
            assert status == 401 and body["error_code"] == "AUTH_REQUIRED"

            missing = root / "missing.json"
            env_missing = env.copy()
            env_missing["AX_MASTER_STATE_PATH"] = str(missing)
            bad = subprocess.run([sys.executable, str(SERVER)], env=env_missing, capture_output=True, text=True)
            assert bad.returncode != 0 and "source files are unavailable" in bad.stderr + bad.stdout  # I11

            print("RUNTIME_INTEGRATION_PASS I1-I12")
        finally:
            proc.terminate()
            try:
                proc.wait(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.wait(timeout=3)


if __name__ == "__main__":
    main()
