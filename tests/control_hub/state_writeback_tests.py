#!/usr/bin/env python3
"""Acceptance test for versioned authoritative A Master Brain state write-back."""
from __future__ import annotations
import json, os, subprocess, sys, tempfile, time, urllib.error, urllib.request
from pathlib import Path

ROOT=Path(__file__).resolve().parents[2]
SERVER=ROOT/"AX_CONTROL_HUB"/"ax_control_hub_server.py"

def request(base, method, path, body=None, token=None):
    data=None if body is None else json.dumps(body).encode()
    req=urllib.request.Request(base+path,data=data,method=method,headers={"Content-Type":"application/json"})
    if token: req.add_header("Authorization",f"Bearer {token}")
    try:
        with urllib.request.urlopen(req,timeout=5) as r: return r.status,json.loads(r.read())
    except urllib.error.HTTPError as e: return e.code,json.loads(e.read())

def main():
    with tempfile.TemporaryDirectory() as td:
        root=Path(td); master=root/"AX_MASTER_BRAIN"; master.mkdir(); evidence=root/"evidence"
        state={"schema_version":"1.3","status":"INITIALIZED_PENDING_VERIFICATION","storage_role":"A_MASTER_BRAIN_SINGLE_SOURCE_OF_TRUTH","identity_authority":"A_MASTER_BRAIN","identity":{"name":"A"},"authority":"K_FINAL_AUTHORITY","model_independence":True}
        tasks={"schema_version":"2.0","tasks":[]}
        (master/"AX_MASTER_STATE.json").write_text(json.dumps(state),encoding="utf-8")
        (master/"AX_MASTER_TASK_REGISTRY_v2.json").write_text(json.dumps(tasks),encoding="utf-8")
        (master/"AX_REHYDRATION_ADAPTER_SPEC.md").write_text("# contract",encoding="utf-8")
        env=os.environ.copy(); env.update({"AX_MASTER_BRAIN_DIR":str(master),"AX_MASTER_STATE_PATH":str(master/"AX_MASTER_STATE.json"),"AX_MASTER_TASK_REGISTRY_PATH":str(master/"AX_MASTER_TASK_REGISTRY_v2.json"),"AX_CONTROL_HUB_EVIDENCE_DIR":str(evidence),"AX_CONTROL_HUB_USERNAME":"k","AX_CONTROL_HUB_PASSWORD":"test-password","AX_CONTROL_HUB_PORT":"8792"})
        p=subprocess.Popen([sys.executable,str(SERVER)],env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE)
        try:
            base="http://127.0.0.1:8792"; time.sleep(.3)
            status,login=request(base,"POST","/auth/login",{"username":"k","password":"test-password"}); assert status==200
            token=login["token"]
            before=json.loads((master/"AX_MASTER_STATE.json").read_text())
            payload={"request_id":"state-writeback-1","idempotency_key":"state-writeback-idem-1","actor":"K","command":"health_check","args":{},"requested_at":"2026-09-03T00:00:00Z"}
            status,result=request(base,"POST","/command",payload,token); assert status==200 and result["verification_status"]=="VERIFIED"
            after=json.loads((master/"AX_MASTER_STATE.json").read_text())
            assert after != before, "authoritative state was not written back"
            assert after.get("last_command",{}).get("request_id")==payload["request_id"]
            assert after.get("last_command",{}).get("idempotency_key")==payload["idempotency_key"]
            assert after.get("last_command",{}).get("verification_status")=="VERIFIED"
            status,dup=request(base,"POST","/command",payload,token); assert status==409 and dup["error_code"]=="DUPLICATE_REQUEST"
            print("STATE_WRITEBACK_PASS authoritative state changed with audit correlation and duplicate protection")
        finally:
            p.terminate(); p.wait(timeout=5)

if __name__=="__main__": main()
