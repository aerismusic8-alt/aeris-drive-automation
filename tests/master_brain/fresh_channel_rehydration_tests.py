#!/usr/bin/env python3
"""Fresh-process rehydration acceptance test."""
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
    with urllib.request.urlopen(req,timeout=5) as r: return r.status,json.loads(r.read().decode())
def wait_health(base):
    for _ in range(50):
        try:
            s,p=request(base+"/health")
            if s==200 and p.get("health_status")=="HEALTHY": return
        except Exception: time.sleep(.1)
    raise AssertionError("fresh runtime did not become healthy")
def run_server(env):
    return subprocess.Popen([sys.executable,str(SERVER)],cwd=str(ROOT),env=env,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True)
def main():
    with tempfile.TemporaryDirectory() as td:
        tmp=Path(td); state=tmp/"AX_MASTER_STATE.json"; tasks=tmp/"AX_MASTER_TASK_REGISTRY_v2.json"; contract=tmp/"AX_REHYDRATION_ADAPTER_SPEC.md"
        state.write_text(STATE.read_text(encoding="utf-8"),encoding="utf-8"); tasks.write_text(TASKS.read_text(encoding="utf-8"),encoding="utf-8"); contract.write_text(CONTRACT.read_text(encoding="utf-8"),encoding="utf-8")
        port=18787; env=os.environ.copy(); env.update({"AX_CONTROL_HUB_HOST":"127.0.0.1","AX_CONTROL_HUB_PORT":str(port),"AX_MASTER_BRAIN_DIR":str(tmp),"AX_MASTER_STATE_PATH":str(state),"AX_MASTER_TASK_REGISTRY_PATH":str(tasks),"AX_CONTROL_HUB_USERNAME":"fresh-test","AX_CONTROL_HUB_PASSWORD":"fresh-test-password"})
        proc=run_server(env)
        try:
            base=f"http://127.0.0.1:{port}"; wait_health(base)
            _,login=request(base+"/auth/login","POST",{"username":"fresh-test","password":"fresh-test-password"}); token=login["token"]
            _,sp=request(base+"/state",token=token); _,tp=request(base+"/tasks",token=token); _,ch=request(base+"/m-a-check","POST",{},token)
            assert sp["source"]=="A_MASTER_BRAIN" and sp["identity"]=="A" and sp["authority"]=="K_FINAL_AUTHORITY"
            assert len(tp["tasks"])==12 and ch["identity_under_test"]=="A" and ch["agent"]=="M" and ch["verified"] is True
            print("FRESH_CHANNEL_REHYDRATION_PASS R1-R8-compatible fresh-process identity/task/source checks")
        finally:
            proc.terminate(); proc.wait(timeout=5)
        tasks.unlink(); proc2=run_server(env)
        try:
            time.sleep(.3); assert proc2.poll() is not None, "runtime started despite missing authoritative task registry"; print("FAILURE_CLOSED_PASS missing task registry refused startup")
        finally:
            if proc2.poll() is None: proc2.terminate(); proc2.wait(timeout=5)
if __name__=="__main__": main()
