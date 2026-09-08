def test_stale_heartbeat_forces_kill():
    from xm_risk_engine import evaluate_risk
    result = evaluate_risk({"equity": 1000, "balance": 1000, "drawdown_pct": 0, "heartbeat_age_sec": 120})
    assert result["decision"] == "KILL"
