"""Fail-closed, durable Continuous Reflection records for A Master Brain."""
from __future__ import annotations

import json
import uuid
from pathlib import Path


class ReflectionError(ValueError):
    pass


class ContinuousReflection:
    MISSING_TIMESTAMP = "NOT RECORDED — ห้ามเดาเวลา"

    def __init__(self, state_path: Path):
        self.state_path = Path(state_path)

    def _load(self) -> dict:
        if not self.state_path.is_file():
            return {}
        try:
            value = json.loads(self.state_path.read_text(encoding="utf-8"))
        except (OSError, ValueError) as exc:
            raise ReflectionError("REFLECTION_STATE_INVALID") from exc
        if not isinstance(value, dict):
            raise ReflectionError("REFLECTION_STATE_INVALID")
        return value

    def load_current(self) -> dict:
        current = self._load().get("current_reflection")
        if not isinstance(current, dict):
            raise ReflectionError("REFLECTION_STATE_MISSING")
        return current

    @staticmethod
    def _claim_is_verified(claim: dict) -> bool:
        return claim.get("supported") is True

    def review(
        self,
        *,
        trigger: str,
        observed_state: dict,
        claims_reviewed: list[dict],
        evidence_checked: list[dict],
        conflicts_found: list[dict],
        corrections_made: list[str],
        lessons: list[str],
        state_changes: list[dict],
        save_point_id: str | None,
        provenance: list[str],
        timestamp_utc: str | None,
        timestamp_local: str | None,
    ) -> dict:
        for claim in claims_reviewed:
            if not isinstance(claim, dict):
                raise ReflectionError("REFLECTION_CLAIM_INVALID")
            kind = claim.get("kind")
            if kind == "COMPLETED" and not self._claim_is_verified(claim):
                raise ReflectionError("COMPLETED_REQUIRES_VERIFICATION")

        all_supported = all(self._claim_is_verified(c) for c in claims_reviewed)
        evidence_verified = all(
            isinstance(item, dict) and item.get("verified") is True
            for item in evidence_checked
        ) if evidence_checked else False
        verification_status = "VERIFIED" if all_supported and (not claims_reviewed or evidence_verified) else "UNVERIFIED"

        record = {
            "reflection_id": str(uuid.uuid4()),
            "timestamp_utc": timestamp_utc or self.MISSING_TIMESTAMP,
            "timestamp_local": timestamp_local or self.MISSING_TIMESTAMP,
            "trigger": trigger,
            "observed_state": observed_state,
            "claims_reviewed": claims_reviewed,
            "evidence_checked": evidence_checked,
            "conflicts_found": conflicts_found,
            "corrections_made": corrections_made,
            "lessons": lessons,
            "state_changes": state_changes,
            "save_point_id": save_point_id,
            "verification_status": verification_status,
            "provenance": provenance,
        }
        document = self._load()
        document["schema_version"] = document.get("schema_version", "1.0")
        document["state_role"] = "AX_CONTINUOUS_REFLECTION_STATE"
        document["authority"] = "K_FINAL_AUTHORITY"
        document["current_reflection"] = record
        self.state_path.parent.mkdir(parents=True, exist_ok=True)
        temporary = self.state_path.with_suffix(self.state_path.suffix + ".tmp")
        temporary.write_text(json.dumps(document, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
        temporary.replace(self.state_path)
        return record
