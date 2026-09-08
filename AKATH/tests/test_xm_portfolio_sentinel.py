def test_sentinel_kills_on_terminal_disconnect():
    from xm_portfolio_sentinel import sentinel_decision
    result = sentinel_decision({"terminal_connected": False, "equity": 1000, "balance": 1000})
    assert result["kill_switch"] is True
