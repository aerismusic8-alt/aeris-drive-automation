#!/usr/bin/env python3
"""Minimal local AX Control Hub runtime.

The hub is a transport boundary. A_MASTER_BRAIN files remain authoritative;
this service does not synthesize or silently rewrite master state.
"""

from __future__ import annotations

import base64
import hashlib
import hmac
import json
import os
import secrets
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse

ROOT = Path(os.getenv("AX_CONTROL_HUB_ROOT", Path(__file__).resolve().parent.parent))
MASTER_DIR = Path(os.getenv("AX_MASTER_BRAIN_DIR", ROOT / "AX_MASTER_BRAIN"))
STATE_PATH = Path(os.getenv("AX_MASTER_STATE_PATH", MASTER_DIR / "AX_MASTER_STATE.json"))
TASK_PATH = Path(os.getenv("AX_MASTER_TASK_REGISTRY_PATH", MASTER_DIR / "AX_MASTER_TASK_REGISTRY_v2.json"))
REFLECTION_PATH = MASTER_DIR / "AX_CONTINUOUS_REFLECTION_STATE.json"
CONTRACT_PATH = MASTER_DIR / "AX_REHYDRATION_ADAPTER_SPEC.md"
HOST = os.getenv("AX_CONTROL_HUB_HOST", "127.0.0.1")
PORT = int(os.getenv("AX_CONTROL_HUB_PORT", "8787"))


def now_utc():
    return time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime())


class MasterBrainStore:
    def __init__(self, state_path: Path, task_path: Path):
        self.state_path = Path(state_path)
        self.task_path = Path(task_path)

    @staticmethod
    def _load(path: Path):
        with path.open("r", encoding="utf-8") as f:
            return json.load(f)

    def read_state(self):
        return self._load(self.state_path)

    def read_tasks(self):
        return self._load(self.task_path)

    def challenge(self):
        state = self.read_state()
        tasks = self.read_tasks()
        required = [STATE_PATH, TASK_PATH, CONTRACT_PATH]
        missing = [str(p) for p in required if not p.exists()]
        checks = {
            "state_loaded": True,
            "tasks_loaded": True,
            "rehydration_contract_present": CONTRACT_PATH.exists(),
            "identity_is_A": state.get("identity", {}).get("name") == "A",
            "identity_authority": state.get("identity_authority") == "A_MASTER_BRAIN",
            "authority_is_K": state.get("authority") == "K_FINAL_AUTHORITY",
            "model_independence": state.get("model_independence") is True,
            "task_registry_v2": str(tasks.get("schema_version")) == "2.0",
            "source_precedence": state.get("storage_role") == "A_MASTER_BRAIN_SINGLE_SOURCE_OF_TRUTH",
        }
        passed = not missing and all(checks.values())
        return {
            "status": "VERIFIED" if passed else "PENDING_VERIFICATION",
            "verified": passed,
            "source": "A_MASTER_BRAIN",
            "agent": "M",
            "identity_under_test": "A",
            "checks": checks,
            "missing": missing,
            "verified_at": now_utc() if passed else None,
        }


class AuthStore:
    def __init__(self, iterations=210000):
        self.iterations = int(iterations)
        self.sessions = {}

    def create_user(self, username, password):
        salt = secrets.token_bytes(16)
        digest = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, self.iterations)
        return {
            "username": username,
            "algorithm": "PBKDF2-HMAC-SHA256",
            "iterations": self.iterations,
            "salt": base64.b64encode(salt).decode(),
            "digest": base64.b64encode(digest).decode(),
        }

    def verify(self, record, password):
        salt = base64.b64decode(record["salt"])
        expected = base64.b64decode(record["digest"])
        actual = hashlib.pbkdf2_hmac("sha256", password.encode(), salt, int(record["iterations"]))
        return hmac.compare_digest(actual, expected)

    def login(self, username, password):
        expected_user = os.getenv("AX_CONTROL_HUB_USERNAME")
        expected_password = os.getenv("AX_CONTROL_HUB_PASSWORD")
        if not expected_user or expected_password is None or not hmac.compare_digest(username, expected_user):
            return None
        # The password is converted to an adaptive verifier for the process;
        # no plaintext password is persisted.
        record = self.create_user(expected_user, expected_password)
        if not self.verify(record, password):
            return None
        token = secrets.token_urlsafe(32)
        self.sessions[token] = {"username": username, "created": time.time()}
        return token

    def valid(self, token):
        item = self.sessions.get(token)
        return item is not None and time.time() - item["created"] < 3600

    def logout(self, token):
        self.sessions.pop(token, None)


class CommandLedger:
    def __init__(self):
        self._lock = threading.Lock()
        self.keys = set()

    def reserve(self, key):
        with self._lock:
            if key in self.keys:
                return False
            self.keys.add(key)
            return True


STORE = MasterBrainStore(STATE_PATH, TASK_PATH)
AUTH = AuthStore()
LEDGER = CommandLedger()


def json_bytes(obj):
    return json.dumps(obj, ensure_ascii=False).encode("utf-8")


class Handler(BaseHTTPRequestHandler):
    server_version = "AXControlHub/0.1"

    def log_message(self, fmt, *args):
        return

    def send_json(self, status, obj):
        data = json_bytes(obj)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def body(self):
        length = int(self.headers.get("Content-Length", "0"))
        if length > 1024 * 1024:
            raise ValueError("request too large")
        raw = self.rfile.read(length)
        return json.loads(raw.decode("utf-8")) if raw else {}

    def token(self):
        value = self.headers.get("Authorization", "")
        return value[7:] if value.startswith("Bearer ") else ""

    def protected(self):
        token = self.token()
        if not AUTH.valid(token):
            self.send_json(401, {"error_code": "AUTH_REQUIRED"})
            return False
        return True

    def do_GET(self):
        path = urlparse(self.path).path
        if path == "/health":
            self.send_json(200, {"ok": True, "service": "AX_CONTROL_HUB", "health_status": "HEALTHY", "execution_status": "UNKNOWN"})
            return
        if not self.protected():
            return
        try:
            if path == "/state":
                state = STORE.read_state()
                challenge = STORE.challenge()
                self.send_json(200, {
                    "source": "A_MASTER_BRAIN",
                    "identity": state.get("identity", {}).get("name"),
                    "authority": state.get("authority"),
                    "master_status": state.get("status"),
                    "rehydration_status": challenge["status"],
                    "last_verified_evidence": None,
                })
            elif path == "/tasks":
                self.send_json(200, {"source": "A_MASTER_BRAIN", "tasks": STORE.read_tasks().get("tasks", [])})
            elif path.startswith("/evidence/"):
                self.send_json(200, {"request_id": path.split("/", 2)[2], "execution_status": "NOT_STARTED", "evidence": [], "verification_status": "PENDING"})
            else:
                self.send_json(404, {"error_code": "INVALID_REQUEST"})
        except (FileNotFoundError, json.JSONDecodeError):
            self.send_json(503, {"error_code": "SOURCE_STATE_UNAVAILABLE"})

    def do_POST(self):
        path = urlparse(self.path).path
        try:
            data = self.body()
        except Exception:
            self.send_json(400, {"error_code": "INVALID_REQUEST"})
            return

        if path == "/auth/login":
            token = AUTH.login(str(data.get("username", "")), str(data.get("password", "")))
            if not token:
                self.send_json(401, {"error_code": "AUTH_FAILED"})
                return
            self.send_json(200, {"authenticated": True, "token": token})
            return
        if not self.protected():
            return
        token = self.token()
        if path == "/auth/logout":
            AUTH.logout(token)
            self.send_json(200, {"logged_out": True})
            return
        if path == "/m-a-check":
            try:
                self.send_json(200, STORE.challenge())
            except (FileNotFoundError, json.JSONDecodeError):
                self.send_json(503, {"error_code": "SOURCE_STATE_UNAVAILABLE"})
            return
        if path == "/command":
            request_id = data.get("request_id")
            idem = data.get("idempotency_key")
            actor = data.get("actor")
            command = data.get("command")
            if not request_id or not idem or actor != "K" or command not in {"health_check"}:
                self.send_json(400, {"error_code": "INVALID_REQUEST"})
                return
            if not LEDGER.reserve(idem):
                self.send_json(409, {"error_code": "DUPLICATE_REQUEST", "request_id": request_id})
                return
            # Safe validation command only; no financial/live execution is exposed.
            self.send_json(200, {"request_id": request_id, "status": "QUEUED", "evidence_status": "PENDING"})
            return
        self.send_json(404, {"error_code": "INVALID_REQUEST"})


def main():
    if HOST not in {"127.0.0.1", "localhost", "::1"} and os.getenv("AX_CONTROL_HUB_ALLOW_REMOTE") != "1":
        raise SystemExit("Remote binding is disabled by default; use an authenticated HTTPS gateway.")
    if not STATE_PATH.exists() or not TASK_PATH.exists():
        raise SystemExit("A_MASTER_BRAIN source files are unavailable; refusing to start.")
    httpd = ThreadingHTTPServer((HOST, PORT), Handler)
    print(f"AX_CONTROL_HUB listening on http://{HOST}:{PORT}")
    httpd.serve_forever()


if __name__ == "__main__":
    main()
