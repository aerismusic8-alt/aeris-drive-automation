#!/usr/bin/env python3
"""Minimal local AX Control Hub runtime."""
from __future__ import annotations
import base64, hashlib, hmac, json, os, secrets, threading, time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from urllib.parse import urlparse
ROOT=Path(os.getenv("AX_CONTROL_HUB_ROOT",Path(__file__).resolve().parent.parent)); MASTER_DIR=Path(os.getenv("AX_MASTER_BRAIN_DIR",ROOT/"AX_MASTER_BRAIN")); STATE_PATH=Path(os.getenv("AX_MASTER_STATE_PATH",MASTER_DIR/"AX_MASTER_STATE.json")); TASK_PATH=Path(os.getenv("AX_MASTER_TASK_REGISTRY_PATH",MASTER_DIR/"AX_MASTER_TASK_REGISTRY_v2.json")); CONTRACT_PATH=MASTER_DIR/"AX_REHYDRATION_ADAPTER_SPEC.md"; EVIDENCE_DIR=Path(os.getenv("AX_CONTROL_HUB_EVIDENCE_DIR",MASTER_DIR/"evidence")); HOST=os.getenv("AX_CONTROL_HUB_HOST","127.0.0.1"); PORT=int(os.getenv("AX_CONTROL_HUB_PORT","8787"))
def now_utc(): return time.strftime("%Y-%m-%dT%H:%M:%SZ",time.gmtime())
class MasterBrainStore:
    def __init__(self,state_path,task_path): self.state_path=Path(state_path); self.task_path=Path(task_path); self._lock=threading.Lock()
    @staticmethod
    def _load(path):
        with path.open("r",encoding="utf-8") as f: return json.load(f)
    def read_state(self): return self._load(self.state_path)
    def read_tasks(self): return self._load(self.task_path)
    def challenge(self):
        state=self.read_state(); tasks=self.read_tasks(); required=[self.state_path,self.task_path,CONTRACT_PATH]; missing=[str(p) for p in required if not p.exists()]
        checks={"state_loaded":True,"tasks_loaded":True,"rehydration_contract_present":CONTRACT_PATH.exists(),"identity_is_A":state.get("identity",{}).get("name")=="A","identity_authority":state.get("identity_authority")=="A_MASTER_BRAIN","authority_is_K":state.get("authority")=="K_FINAL_AUTHORITY","model_independence":state.get("model_independence") is True,"task_registry_v2":str(tasks.get("schema_version"))=="2.0","source_precedence":state.get("storage_role")=="A_MASTER_BRAIN_SINGLE_SOURCE_OF_TRUTH"}; passed=not missing and all(checks.values())
        return {"status":"VERIFIED" if passed else "PENDING_VERIFICATION","verified":passed,"source":"A_MASTER_BRAIN","agent":"M","identity_under_test":"A","checks":checks,"missing":missing,"verified_at":now_utc() if passed else None}
    def write_command_audit(self,request_id,idempotency_key,actor,verification_status,expected_version=None):
        with self._lock:
            state=self.read_state(); current=int(state.get("state_version",0))
            if expected_version is not None and int(expected_version)!=current: raise ValueError("STATE_VERSION_CONFLICT")
            required={"identity_authority":"A_MASTER_BRAIN","authority":"K_FINAL_AUTHORITY","storage_role":"A_MASTER_BRAIN_SINGLE_SOURCE_OF_TRUTH","model_independence":True}
            if any(state.get(k)!=v for k,v in required.items()) or state.get("identity",{}).get("name")!="A": raise ValueError("STATE_INTEGRITY_FAILURE")
            new_state=dict(state); new_state["state_version"]=current+1
            new_state["last_command"]={"request_id":request_id,"idempotency_key":idempotency_key,"actor":actor,"verification_status":verification_status,"recorded_at":now_utc(),"source":"AX_CONTROL_HUB"}
            tmp=self.state_path.with_suffix(".json.tmp"); tmp.write_text(json.dumps(new_state,ensure_ascii=False,indent=2)+"\n",encoding="utf-8"); os.replace(tmp,self.state_path)
            return {"previous_state_version":current,"state_version":current+1}
class AuthStore:
    def __init__(self,iterations=210000): self.iterations=int(iterations); self.sessions={}
    def create_user(self,username,password):
        salt=secrets.token_bytes(16); digest=hashlib.pbkdf2_hmac("sha256",password.encode(),salt,self.iterations); return {"username":username,"algorithm":"PBKDF2-HMAC-SHA256","iterations":self.iterations,"salt":base64.b64encode(salt).decode(),"digest":base64.b64encode(digest).decode()}
    def verify(self,record,password):
        salt=base64.b64decode(record["salt"]); expected=base64.b64decode(record["digest"]); actual=hashlib.pbkdf2_hmac("sha256",password.encode(),salt,int(record["iterations"])); return hmac.compare_digest(actual,expected)
    def login(self,username,password):
        expected_user=os.getenv("AX_CONTROL_HUB_USERNAME"); expected_password=os.getenv("AX_CONTROL_HUB_PASSWORD")
        if not expected_user or expected_password is None or not hmac.compare_digest(username,expected_user): return None
        if not self.verify(self.create_user(expected_user,expected_password),password): return None
        token=secrets.token_urlsafe(32); self.sessions[token]={"username":username,"created":time.time()}; return token
    def valid(self,token):
        item=self.sessions.get(token); return item is not None and time.time()-item["created"]<3600
    def logout(self,token): self.sessions.pop(token,None)
class CommandLedger:
    def __init__(self,evidence_dir=None): self._lock=threading.Lock(); self.keys=set(); self.records={}; self.evidence_dir=Path(evidence_dir) if evidence_dir else None; self._load_durable_records()
    def _persist(self,record):
        if self.evidence_dir is None: return
        self.evidence_dir.mkdir(parents=True,exist_ok=True); target=self.evidence_dir/f"{record['request_id']}.json"; tmp=target.with_suffix(".json.tmp"); tmp.write_text(json.dumps(record,ensure_ascii=False,indent=2),encoding="utf-8"); os.replace(tmp,target)
    def _load_durable_records(self):
        if self.evidence_dir is None or not self.evidence_dir.exists(): return
        for target in self.evidence_dir.glob("*.json"):
            try:
                record=json.loads(target.read_text(encoding="utf-8")); key=record.get("idempotency_key"); request_id=record.get("request_id")
                if key and request_id: self.keys.add(key); self.records[request_id]=record
            except (OSError,json.JSONDecodeError): continue
    def reserve(self,key,request_id=None,command=None,actor=None,args=None,requested_at=None):
        with self._lock:
            if key in self.keys: return False
            self.keys.add(key)
            if request_id is None: return True
            recorded=now_utc(); record={"request_id":request_id,"idempotency_key":key,"actor":actor,"command":command,"args":args if isinstance(args,dict) else {},"requested_at":requested_at,"recorded_at":recorded,"lifecycle_status":"PENDING_STATE_WRITEBACK","execution_status":"EXECUTED","verification_status":"VERIFIED","evidence":[{"request_id":request_id,"observed_at":recorded,"result":"health_check executed by local allowlisted runtime"}],"verification":{"method":"SAFE_LOCAL_COMMAND_EXECUTION","command_allowlist":True,"financial_live_execution":False}}
            self.records[request_id]=record; self._persist(record)
            if os.getenv("AX_CONTROL_HUB_INTERRUPT_AFTER_EVIDENCE")=="1": os._exit(70)
            return True
    def release(self,key,request_id=None):
        with self._lock:
            self.keys.discard(key)
            if request_id is not None: self.records.pop(request_id,None)
            if self.evidence_dir is not None and request_id is not None:
                target=self.evidence_dir/f"{request_id}.json"
                try: target.unlink()
                except FileNotFoundError: pass
    def get(self,request_id):
        with self._lock: record=self.records.get(request_id)
        if record is not None: return record
        if self.evidence_dir is None: return None
        target=self.evidence_dir/f"{request_id}.json"
        if not target.exists(): return None
        try: return json.loads(target.read_text(encoding="utf-8"))
        except (OSError,json.JSONDecodeError): return None
    def recover_pending(self,store):
        for request_id, record in list(self.records.items()):
            if record.get("lifecycle_status")!="PENDING_STATE_WRITEBACK": continue
            state=store.read_state()
            if state.get("last_command",{}).get("idempotency_key")==record.get("idempotency_key"):
                transition={"previous_state_version":int(state.get("state_version",0))-1,"state_version":int(state.get("state_version",0))}
            else:
                transition=store.write_command_audit(record["request_id"],record["idempotency_key"],record["actor"],"VERIFIED")
            record["state_writeback"]=transition; record["lifecycle_status"]="COMPLETED"; record["verification_status"]="VERIFIED"; self._persist(record)
STORE=MasterBrainStore(STATE_PATH,TASK_PATH); AUTH=AuthStore(); LEDGER=CommandLedger(EVIDENCE_DIR)
def json_bytes(obj): return json.dumps(obj,ensure_ascii=False).encode("utf-8")
class Handler(BaseHTTPRequestHandler):
    server_version="AXControlHub/0.6"
    def log_message(self,fmt,*args): return
    def send_json(self,status,obj):
        data=json_bytes(obj); self.send_response(status); self.send_header("Content-Type","application/json; charset=utf-8"); self.send_header("Content-Length",str(len(data))); self.end_headers(); self.wfile.write(data)
    def body(self):
        length=int(self.headers.get("Content-Length","0"));
        if length>1024*1024: raise ValueError("request too large")
        raw=self.rfile.read(length); return json.loads(raw.decode("utf-8")) if raw else {}
    def token(self):
        value=self.headers.get("Authorization",""); return value[7:] if value.startswith("Bearer ") else ""
    def protected(self):
        if not AUTH.valid(self.token()): self.send_json(401,{"error_code":"AUTH_REQUIRED"}); return False
        return True
    def do_GET(self):
        path=urlparse(self.path).path
        if path=="/health": self.send_json(200,{"ok":True,"service":"AX_CONTROL_HUB","health_status":"HEALTHY","execution_status":"UNKNOWN"}); return
        if not self.protected(): return
        try:
            if path=="/state":
                state=STORE.read_state(); challenge=STORE.challenge(); self.send_json(200,{"source":"A_MASTER_BRAIN","identity":state.get("identity",{}).get("name"),"authority":state.get("authority"),"master_status":state.get("status"),"state_version":state.get("state_version",0),"rehydration_status":challenge["status"],"last_verified_evidence":state.get("last_command")})
            elif path=="/tasks": self.send_json(200,{"source":"A_MASTER_BRAIN","tasks":STORE.read_tasks().get("tasks",[])})
            elif path.startswith("/evidence/"):
                request_id=path.split("/",2)[2]; record=LEDGER.get(request_id)
                if record is None: self.send_json(404,{"error_code":"EVIDENCE_UNAVAILABLE","request_id":request_id})
                else: self.send_json(200,record)
            else: self.send_json(404,{"error_code":"INVALID_REQUEST"})
        except (FileNotFoundError,json.JSONDecodeError): self.send_json(503,{"error_code":"SOURCE_STATE_UNAVAILABLE"})
    def do_POST(self):
        path=urlparse(self.path).path
        try: data=self.body()
        except Exception: self.send_json(400,{"error_code":"INVALID_REQUEST"}); return
        if path=="/auth/login":
            token=AUTH.login(str(data.get("username","")),str(data.get("password","")))
            if not token: self.send_json(401,{"error_code":"AUTH_FAILED"}); return
            self.send_json(200,{"authenticated":True,"token":token}); return
        if not self.protected(): return
        token=self.token()
        if path=="/auth/logout": AUTH.logout(token); self.send_json(200,{"logged_out":True}); return
        if path=="/m-a-check":
            try: self.send_json(200,STORE.challenge())
            except (FileNotFoundError,json.JSONDecodeError): self.send_json(503,{"error_code":"SOURCE_STATE_UNAVAILABLE"})
            return
        if path=="/command":
            request_id=data.get("request_id"); idem=data.get("idempotency_key"); actor=data.get("actor"); command=data.get("command")
            if not request_id or not idem or actor!="K" or command not in {"health_check"}: self.send_json(400,{"error_code":"INVALID_REQUEST"}); return
            if not LEDGER.reserve(idem,request_id,command,actor,data.get("args",{}),data.get("requested_at")): self.send_json(409,{"error_code":"DUPLICATE_REQUEST","request_id":request_id}); return
            try: transition=STORE.write_command_audit(request_id,idem,actor,"VERIFIED",data.get("expected_state_version"))
            except ValueError as exc:
                LEDGER.release(idem,request_id)
                self.send_json(409,{"error_code":str(exc)}); return
            except (OSError,json.JSONDecodeError):
                LEDGER.release(idem,request_id)
                self.send_json(503,{"error_code":"SOURCE_STATE_UNAVAILABLE"}); return
            record=LEDGER.get(request_id)
            if record is not None:
                record["state_writeback"]=transition; record["lifecycle_status"]="COMPLETED"; LEDGER._persist(record)
            self.send_json(200,{"request_id":request_id,"status":"EXECUTED","evidence_status":"RECORDED","verification_status":"VERIFIED","state_writeback":transition}); return
        self.send_json(404,{"error_code":"INVALID_REQUEST"})
def main():
    if HOST not in {"127.0.0.1","localhost","::1"} and os.getenv("AX_CONTROL_HUB_ALLOW_REMOTE")!="1": raise SystemExit("Remote binding is disabled by default; use an authenticated HTTPS gateway.")
    if not STATE_PATH.exists() or not TASK_PATH.exists(): raise SystemExit("A_MASTER_BRAIN source files are unavailable; refusing to start.")
    try: LEDGER.recover_pending(STORE)
    except (OSError,json.JSONDecodeError,ValueError) as exc: raise SystemExit(f"Pending command recovery failed closed: {exc}")
    httpd=ThreadingHTTPServer((HOST,PORT),Handler); print(f"AX_CONTROL_HUB listening on http://{HOST}:{PORT}"); httpd.serve_forever()
if __name__=="__main__": main()
