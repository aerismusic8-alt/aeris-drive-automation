def test_report_requests_kill_when_sentinel_is_kill():
    from xm_ax_report import build_report
    report = build_report({"sentinel": {"decision": "KILL"}, "strategy": {"accepted": True}})
    assert report["next_action"] == "KILL"
