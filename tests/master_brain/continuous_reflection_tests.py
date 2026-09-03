#!/usr/bin/env python3
"""Acceptance tests for the auditable Continuous Reflection layer."""
from __future__ import annotations

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
            claims_reviewed=[
                {"claim": "task started", "kind": "EXECUTING", "classification": "FACT", "supported": False},
                {"claim": "task may finish today", "kind": "PLAN", "classification": "PLAN", "supported": False},
                {"claim": "task may be healthy", "kind": "ASSESSMENT", "classification": "INFERENCE", "supported": False},
            ],
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
        assert {c["classification"] for c in record["claims_reviewed"]} == {"FACT", "INFERENCE", "PLAN"}
        assert "Unsupported execution claims" in record["lessons"][0]

        engine2 = ContinuousReflection(state_path)
        resumed = engine2.load_current()
        assert resumed["reflection_id"] == record["reflection_id"]
        assert resumed["save_point_id"] == "SP-TEST-1"

        with_timestamp = engine2.review(
            trigger="RECOVERY",
            observed_state={"task": "demo", "status": "COMPLETED"},
            claims_reviewed=[{"claim": "task completed", "kind": "EXECUTED_RESULT", "classification": "EXECUTED_RESULT", "supported": True}],
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

        history = engine2.load_history()
        assert len(history) == 1
        assert history[0]["reflection_id"] == record["reflection_id"]
        assert history[0]["lessons"] == record["lessons"]

        try:
            engine2.review(
                trigger="INVALID",
                observed_state={},
                claims_reviewed=[{"claim": "completed", "kind": "COMPLETED", "classification": "EXECUTED_RESULT", "supported": False}],
                evidence_checked=[], conflicts_found=[], corrections_made=[], lessons=[], state_changes=[],
                save_point_id=None, provenance=[], timestamp_utc="2026-09-03T02:00:00Z", timestamp_local=None,
            )
        except ReflectionError as exc:
            assert str(exc) == "COMPLETED_REQUIRES_VERIFICATION"
        else:
            raise AssertionError("unsupported completion claim must fail closed")

        try:
            engine2.review(
                trigger="INVALID_CLASS",
                observed_state={},
                claims_reviewed=[{"claim": "unknown", "kind": "NOTE", "classification": "UNKNOWN", "supported": False}],
                evidence_checked=[], conflicts_found=[], corrections_made=[], lessons=[], state_changes=[],
                save_point_id=None, provenance=[], timestamp_utc=None, timestamp_local=None,
            )
        except ReflectionError as exc:
            assert str(exc) == "REFLECTION_CLASSIFICATION_INVALID"
        else:
            raise AssertionError("invalid classification must fail closed")

        try:
            engine2.review(
                trigger="INVALID_SAVEPOINT",
                observed_state={},
                claims_reviewed=[{"claim": "change", "kind": "NOTE", "classification": "FACT", "supported": True}],
                evidence_checked=[{"evidence_id": "E-2", "verified": True}],
                conflicts_found=[], corrections_made=[], lessons=[],
                state_changes=[{"field": "x", "from": 1, "to": 2}], save_point_id=None,
                provenance=[], timestamp_utc=None, timestamp_local=None,
            )
        except ReflectionError as exc:
            assert str(exc) == "STATE_CHANGE_REQUIRES_SAVE_POINT"
        else:
            raise AssertionError("material state change must require a save point")

    print("CONTINUOUS_REFLECTION_PASS history, classification, unsupported_claims, timestamps, savepoint, recovery")


if __name__ == "__main__":
    main()
