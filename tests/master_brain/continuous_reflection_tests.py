#!/usr/bin/env python3
"""Acceptance tests for the auditable Continuous Reflection layer."""
from __future__ import annotations

import json
import sys
import tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT))

from AX_CONTROL_HUB.continuous_reflection import ContinuousReflection, ReflectionError


def main() -> None:
    with tempfile.TemporaryDirectory() as tmp:
        root = Path(tmp)
        state_path = root / "reflection_state.json"
        engine = ContinuousReflection(state_path)

        record = engine.review(
            trigger="TEST",
            observed_state={"task": "demo", "status": "EXECUTING"},
            claims_reviewed=[{"claim": "task started", "kind": "EXECUTING", "supported": False}],
            evidence_checked=[],
            conflicts_found=[],
            corrections_made=[],
            lessons=["Unsupported execution claims must remain unverified."],
            state_changes=[],
            save_point_id="SP-TEST-1",
            provenance=["test"],
            timestamp_utc="2026-09-03T02:00:00Z",
            timestamp_local="2026-09-03T09:00:00+07:00",
        )
        assert record["verification_status"] == "UNVERIFIED"
        assert record["claims_reviewed"][0]["supported"] is False
        assert "Unsupported execution claims" in record["lessons"][0]

        engine2 = ContinuousReflection(state_path)
        resumed = engine2.load_current()
        assert resumed["reflection_id"] == record["reflection_id"]
        assert resumed["save_point_id"] == "SP-TEST-1"

        with_timestamp = engine2.review(
            trigger="RECOVERY",
            observed_state={"task": "demo", "status": "COMPLETED"},
            claims_reviewed=[{"claim": "task completed", "kind": "EXECUTED_RESULT", "supported": True}],
            evidence_checked=[{"evidence_id": "E-1", "verified": True}],
            conflicts_found=[],
            corrections_made=["Changed unsupported claim to UNVERIFIED."],
            lessons=["Evidence verification is required before completion."],
            state_changes=[{"field": "status", "from": "EXECUTING", "to": "COMPLETED"}],
            save_point_id="SP-TEST-2",
            provenance=["test", "recovery"],
            timestamp_utc=None,
            timestamp_local=None,
        )
        assert with_timestamp["timestamp_utc"] == "NOT RECORDED — ห้ามเดาเวลา"
        assert with_timestamp["timestamp_local"] == "NOT RECORDED — ห้ามเดาเวลา"
        assert with_timestamp["verification_status"] == "VERIFIED"

        try:
            engine.review(
                trigger="INVALID",
                observed_state={},
                claims_reviewed=[{"claim": "completed", "kind": "COMPLETED", "supported": False}],
                evidence_checked=[], conflicts_found=[], corrections_made=[], lessons=[], state_changes=[],
                save_point_id=None, provenance=[], timestamp_utc="2026-09-03T02:00:00Z", timestamp_local=None,
            )
        except ReflectionError as exc:
            assert str(exc) == "COMPLETED_REQUIRES_VERIFICATION"
        else:
            raise AssertionError("unsupported completion claim must fail closed")

    print("CONTINUOUS_REFLECTION_PASS unsupported_claims, lessons, classification, timestamps, recovery")


if __name__ == "__main__":
    main()
