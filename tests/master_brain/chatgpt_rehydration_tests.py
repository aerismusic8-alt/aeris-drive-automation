#!/usr/bin/env python3
from __future__ import annotations
import json
import subprocess
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
ADAPTER = ROOT / "AKATH" / "runtime" / "ax_chatgpt_rehydration.py"


def test_chatgpt_rehydration():
    p = subprocess.run([sys.executable, str(ADAPTER), "rehydrate"], cwd=ROOT, text=True, capture_output=True)
    result = json.loads(p.stdout or "{}")
    assert p.returncode == 0, result
    assert result["rehydration_status"] == "VERIFIED", result
    assert result["identity"] == "AX", result
    assert result["organization"] == "AKATH", result
    assert result["brain_role"] == "KNOWLEDGE_AND_ACCUMULATED_EXPERIENCE", result
    assert result["chat_memory_authority"] is False, result
    assert result["model_memory_authority"] is False, result
    assert result["execution_authorized"] is False, result
    assert result["profile_source"].endswith("AX_CHATGPT_REHYDRATION_PROFILE.json"), result
