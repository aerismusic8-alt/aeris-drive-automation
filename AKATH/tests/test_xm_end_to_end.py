def test_xm_pipeline_is_fail_closed():
    from xm_risk_engine import evaluate_risk
    from xm_portfolio_sentinel import sentinel_decision
    from xm_ax_report import build_report
    snapshot = {"equity": 1000, "balance": 1000, "heartbeat_age_sec": 120, "terminal_connected": False}
    risk = evaluate_risk(snapshot)
    sentinel = sentinel_decision(snapshot)
    report = build_report({"sentinel": {"decision": sentinel["decision"]}, "strategy": {"accepted": False}})
    assert risk["decision"] == "KILL"
    assert report["next_action"] == "KILL"
