#!/usr/bin/env python3
"""Acceptance test for authoritative source-of-truth conflict handling."""
from __future__ import annotations
import json, os, subprocess, sys, tempfile, time, urllib.request
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
SERVER=ROOT/"AX_CONTROL_HUB"/"ax_control_hub_server.py"
STATE=ROOT/"AX_MASTER_BRAIN"/"AX_MASTER_STATE.json"
TASKS=ROOT/"AX_MASTER_BRAIN"/"AX_MASTER_TASK_REGISTRY_v2.json"
CONTRACT=ROOT/"AX_MASTER_BRAIN"/"AX_REHYDRATION_ADAPTER_SPEC.md"
def request(url,method="GET",body=None,token=None):
    data=json.dumps(body).encode() if body is not None else None
    req=urllib.request.Request(url,data=data,method=method)
    if data is not None: req.add_header("Content-Type","application/json")
    if token: req.add_header("Authorization",f"Bearer {token}")
    try:
        with urllib.request.urlopen(req,timeout=5) as r: return r.status,json.loads(r.read().decode())
    except urllib.error.HTTPError as exc:
        return exc.code,json.loads(exc.read().decode())
def wait_health(base):
    for _ in range(50):
        try:
            s,p=request(base+"/health")
            if s==200 and p.get("health_status")=="HEALTHY": return
        except Exception: time.sleep(.1)
    raise AssertionError("runtime did not become healthy")
def main():
    with tempfile.TemporaryDirectory() as td:
        tmp=Path(td); state=tmp/"AX_MASTER_STATE.json"; tasks=tmp/"AX_MASTER_TASK_REGISTRY_v2.json"; contract=tmp/"AX_REHYDRATION_ADAPTER_SPEC.md"
        state.write_text(STATE.read_text(encoding="utf-8"),encoding="utf-8"); tasks.write_text(TASKS.read_text(encoding="utf-8"),encoding="utf-8"); contract.write_text(CONTRACT.read_text(encoding="utf-8"),encoding="utf-8")
        port=18786; env=os.environ.copy(); env.update({"AX_CONTROL_HUB_HOST":"127.0.0.1","AX_CONTROL_HUB_PORT":str(port),"AX_MASTER_BRAIN_DIR":str(tmp),"AX_MASTER_STATE_PATH":str(state),"AX_MASTER_TASK_REGISTRY_PATH":str(tasks),"AX_REHYDRATION_CONTRACT_PATH":str(contract),"AX_CONTROL_HUB_EVIDENCE_DIR":str(tmp/"evidence"),"AX_CONTROL_HUB_USERNAME":"conflict-test","AX_CONTROL_HUB_PASSWORD":"conflict-test-password","AX_RUNTIME_PROFILE":"SOURCE_OF_TRUTH_CONFLICT"})
        proc=subprocess.Popen([sys.executable,str(SERVER)],cwd=str(ROOT),env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
        try:
            base=f"http://127.0.0.1:{port}"; wait_health(base)
            _,login=request(base+"/auth/login","POST",{"username":"conflict-test","password":"conflict-test-password"}); token=login["token"]
            _,before=request(base+"/state",token=token); expected=int(before["state_version"])
            conflict_status,conflict=request(base+"/command","POST",{"request_id":"conflict-1","idempotency_key":"idem-conflict-1","actor":"K","command":"health_check","expected_state_version":expected+1},token)
            assert conflict_status==409 and conflict["error_code"]=="STATE_VERSION_CONFLICT", json.dumps(conflict,ensure_ascii=False)
            after_conflict=json.loads(state.read_text(encoding="utf-8"))
            assert int(after_conflict.get("state_version",0))==expected, after_conflict
            ok_status,ok=request(base+"/command","POST",{"request_id":"conflict-2","idempotency_key":"idem-conflict-2","actor":"K","command":"health_check","expected_state_version":expected},token)
            assert ok_status==200 and ok["verification_status"]=="VERIFIED", ok
            final_state=json.loads(state.read_text(encoding="utf-8"))
            assert int(final_state["state_version"])==expected+1, final_state
            assert final_state["last_command"]["idempotency_key"]=="idem-conflict-2", final_state
            assert final_state["last_command"]["source"]=="AX_CONTROL_HUB", final_state
            print("SOURCE_OF_TRUTH_CONFLICT_PASS stale write rejected; authoritative master state remained intact and valid write committed")
        finally:
            proc.terminate(); proc.wait(timeout=5)
if __name__=="__main__": main()
