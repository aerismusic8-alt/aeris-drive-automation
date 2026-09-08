"""Evidence gate for AI-generated XM strategy candidates."""
from __future__ import annotations

from typing import Mapping, Any

DEFAULT_MAX_DRAWDOWN_PCT = 10.0
DEFAULT_MIN_OBSERVATIONS = 100


def accept_candidate(candidate: Mapping[str, Any], *, max_drawdown_pct: float = DEFAULT_MAX_DRAWDOWN_PCT, min_observations: int = DEFAULT_MIN_OBSERVATIONS) -> dict[str, Any]:
    """Accept only candidates with explicit out-of-sample evidence."""
    reasons: list[str] = []
    oos = candidate.get("out_of_sample_expectancy")
    dd = candidate.get("max_drawdown_pct")
    observations = candidate.get("observations", min_observations)

    if not isinstance(oos, (int, float)) or oos <= 0:
        reasons.append("OOS_EXPECTANCY_NOT_POSITIVE")
    if not isinstance(dd, (int, float)) or dd > max_drawdown_pct:
        reasons.append("DRAWDOWN_LIMIT")
    if not isinstance(observations, int) or observations < min_observations:
        reasons.append("INSUFFICIENT_OBSERVATIONS")

    return {"accepted": not reasons, "reasons": reasons}
