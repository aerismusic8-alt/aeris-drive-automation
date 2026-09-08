import json
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
STATE = ROOT / "AX_MASTER_BRAIN" / "AX_MASTER_STATE.json"
TASKS = ROOT / "AX_MASTER_BRAIN" / "AX_MASTER_TASK_REGISTRY_v2.json"


def load_json(path):
    return json.loads(path.read_text(encoding="utf-8"))


def test_akath_is_company_and_ax_is_executive():
    state = load_json(STATE)
    assert state["company"] == "AKATH"
    assert state["executive_identity"] == "AX"
    assert state["identity_authority"] == "AKATH_AX"


def test_master_brain_is_knowledge_and_experience_layer():
    state = load_json(STATE)
    brain = state["master_brain"]
    assert brain["role"] == "KNOWLEDGE_AND_ACCUMULATED_EXPERIENCE"
    assert brain["authoritative_for_current_company_state"] is False
    assert brain["used_by"] == "AX"


def test_k_remains_final_authority_and_m_is_not_ax():
    state = load_json(STATE)
    assert state["authority"] == "K_FINAL_AUTHORITY"
    assert state.get("executive_identity") != "M"
    assert state.get("support_agent", {}).get("name") != "AX"


def test_task_registry_is_managed_by_ax_for_akath():
    tasks = load_json(TASKS)
    assert tasks["authority"] == "K_FINAL_AUTHORITY"
    assert tasks["managed_by"] == "AX"
    assert tasks["organization"] == "AKATH"
