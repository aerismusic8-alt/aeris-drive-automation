#!/usr/bin/env python3
"""Deterministic AKATH/AX rehydration adapter using A MASTER BRAIN as knowledge."""
from __future__ import annotations

import json
import os
import sys
from pathlib import Path
from typing import Any, Mapping

ROOT = Path(__file__).resolve().parents[2]
STATE_PATH = Path(os.getenv("AX_MASTER_STATE_PATH", ROOT / "AX_MASTER_BRAIN" / "AX_MASTER_STATE.json"))
TASK_PATH = Path(os.getenv("AX_MASTER_TASK_REGISTRY_PATH", ROOT / "AX_MASTER_BRAIN" / "AX_MASTER_TASK_REGISTRY_v2.json"))
CONTRACT_PATH = Path(os.getenv("AX_REHYDRATION_CONTRACT_PATH", ROOT / "AX_MASTER_BRAIN" / "AX_REHYDRATION_ADAPTER_SPEC.md"))

REQUIRED_STATE = {"storage_role":"A_MASTER_BRAIN_KNOWLEDGE_AND_EXPERIENCE","authority":"K_FINAL_AUTHORITY","identity_authority":"AKATH_AX","company":"AKATH","executive_identity":"AX"}
ALLOWED_TASK_TYPES = {"SYSTEM", "MISSION"}
ALLOWED_CATEGORIES = {"CORE", "REVENUE", "OPERATIONS", "INFRASTRUCTURE", "FINANCE", "INPUT"}


def fail(*reasons: str) -> dict[str, Any]:
    return {"rehydration_status":"NOT_VERIFIED","identity":"AX","organization":"AKATH","identity_source":str(STATE_PATH),"task_registry_source":str(TASK_PATH),"master_brain_source":str(ROOT/"AX_MASTER_BRAIN"),"identity_verified":False,"authority_verified":False,"master_state_verified":False,"task_registry_verified":False,"current_work_verified":False,"evidence_checked":False,"verification_checked":False,"source_conflicts":[],"chat_memory_authority":False,"model_memory_authority":False,"execution_authorized":False,"failure_reasons":list(reasons)}


def load_json(path: Path, missing_code: str, malformed_code: str) -> tuple[dict[str, Any] | None, dict[str, Any] | None]:
    if not path.is_file(): return None, fail(missing_code)
    try: value = json.loads(path.read_text(encoding="utf-8"))
    except (OSError, UnicodeError, json.JSONDecodeError): return None, fail(malformed_code)
    if not isinstance(value, dict): return None, fail(malformed_code)
    return value, None


def validate_task_registry(registry: Mapping[str, Any]) -> dict[str, Any]:
    tasks = registry.get("tasks"); errors: list[str] = []
    if not isinstance(tasks, list): return {"valid":False,"task_count":0,"task_ids":[],"task_type_counts":{},"errors":["TASK_LIST_MISSING"]}
    task_ids=[]; seen=set(); type_counts={"SYSTEM":0,"MISSION":0}
    for task in tasks:
        if not isinstance(task, Mapping): errors.append("TASK_RECORD_INVALID"); continue
        task_id=str(task.get("task_id") or "").strip()
        if not task_id: errors.append("TASK_ID_MISSING"); continue
        if task_id in seen: errors.append("DUPLICATE_TASK_ID")
        seen.add(task_id); task_ids.append(task_id)
        if not str(task.get("name") or "").strip(): errors.append("TASK_NAME_MISSING")
        task_type=str(task.get("task_type") or "").strip().upper()
        if task_type not in ALLOWED_TASK_TYPES: errors.append(f"TASK_TYPE_INVALID:{task_id}")
        else: type_counts[task_type]+=1
        category=str(task.get("category") or "").strip().upper()
        if category not in ALLOWED_CATEGORIES: errors.append(f"TASK_CATEGORY_INVALID:{task_id}")
        details=task.get("details")
        if not isinstance(details, Mapping): errors.append(f"TASK_DETAILS_MISSING:{task_id}")
        elif task_type=="MISSION" and not isinstance(details.get("target"), Mapping): errors.append(f"MISSION_TARGET_MISSING:{task_id}")
    return {"valid":not errors,"task_count":len(tasks),"task_ids":task_ids,"task_type_counts":type_counts,"errors":errors}


def get_task_by_id(registry: Mapping[str, Any], task_id: str) -> dict[str, Any]:
    tasks=registry.get("tasks"); matches=[t for t in tasks if isinstance(t,Mapping) and str(t.get("task_id") or "").strip()==str(task_id or "").strip()] if isinstance(tasks,list) else []
    if len(matches)!=1: raise ValueError("TASK_NOT_FOUND_OR_NOT_UNIQUE:"+str(task_id))
    return dict(matches[0])


def validate_current_work(registry: Mapping[str, Any]) -> dict[str, Any]:
    current=registry.get("current_work"); errors=[]
    if not isinstance(current,Mapping): return {"valid":False,"task_id":None,"errors":["CURRENT_WORK_MISSING"]}
    if current.get("active") is not True: errors.append("CURRENT_WORK_NOT_ACTIVE")
    task_id=str(current.get("task_id") or "").strip()
    if not task_id: errors.append("CURRENT_WORK_TASK_ID_MISSING")
    rv=validate_task_registry(registry)
    if not rv["valid"]: errors.extend(rv["errors"])
    elif task_id not in rv["task_ids"]: errors.append("CURRENT_WORK_TASK_NOT_FOUND")
    return {"valid":not errors,"task_id":task_id or None,"errors":errors}


def rehydrate() -> dict[str, Any]:
    if not CONTRACT_PATH.is_file(): return fail("REHYDRATION_CONTRACT_MISSING")
    state,error=load_json(STATE_PATH,"MASTER_STATE_MISSING","MASTER_STATE_MALFORMED")
    if error: return error
    tasks,error=load_json(TASK_PATH,"TASK_REGISTRY_MISSING","TASK_REGISTRY_MALFORMED")
    if error: return error
    assert state is not None and tasks is not None
    reasons=[]; identity=state.get("identity"); brain=state.get("master_brain")
    if not isinstance(identity,Mapping) or identity.get("name")!="AX": reasons.append("IDENTITY_NOT_AX")
    for key,expected in REQUIRED_STATE.items():
        if state.get(key)!=expected: reasons.append(f"STATE_{key.upper()}_INVALID")
    if not isinstance(brain,Mapping) or brain.get("role")!="KNOWLEDGE_AND_ACCUMULATED_EXPERIENCE" or brain.get("used_by")!="AX" or brain.get("authoritative_for_current_company_state") is not False: reasons.append("MASTER_BRAIN_BOUNDARY_INVALID")
    if state.get("model_independence") is not True: reasons.append("MODEL_INDEPENDENCE_INVALID")
    if str(tasks.get("schema_version"))!="2.4": reasons.append("TASK_REGISTRY_VERSION_INVALID")
    if state.get("status")!="VERIFIED": reasons.append("MASTER_STATE_NOT_VERIFIED")
    if tasks.get("organization")!="AKATH" or tasks.get("managed_by")!="AX": reasons.append("TASK_REGISTRY_OWNER_INVALID")
    rv=validate_task_registry(tasks); reasons.extend(rv["errors"] if not rv["valid"] else [])
    cv=validate_current_work(tasks); reasons.extend(cv["errors"] if not cv["valid"] else [])
    if reasons: return fail(*dict.fromkeys(reasons))
    current=get_task_by_id(tasks,cv["task_id"])
    return {"rehydration_status":"VERIFIED","identity":"AX","organization":"AKATH","identity_source":str(STATE_PATH),"task_registry_source":str(TASK_PATH),"master_brain_source":str(ROOT/"AX_MASTER_BRAIN"),"identity_verified":True,"authority_verified":True,"master_state_verified":True,"task_registry_verified":True,"current_work_verified":True,"evidence_checked":False,"verification_checked":False,"source_conflicts":[],"chat_memory_authority":False,"model_memory_authority":False,"execution_authorized":False,"failure_reasons":[],"mission":identity.get("mission"),"task_count":rv["task_count"],"task_ids":rv["task_ids"],"task_type_counts":rv["task_type_counts"],"master_state_version":state.get("schema_version"),"task_registry_version":tasks.get("schema_version"),"current_work":current,"current_work_task_id":current["task_id"],"brain_role":brain.get("role")}


def main() -> int:
    if len(sys.argv)!=2 or sys.argv[1]!="rehydrate":
        print(json.dumps(fail("INVALID_INVOCATION"),ensure_ascii=False)); return 2
    result=rehydrate(); print(json.dumps(result,ensure_ascii=False)); return 0 if result["rehydration_status"]=="VERIFIED" else 1

if __name__=="__main__": raise SystemExit(main())
