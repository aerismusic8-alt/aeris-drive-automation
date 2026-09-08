def test_strategy_ai_prompt_requires_market_and_risk_context():
    from xm_strategy_ai import build_research_prompt
    prompt = build_research_prompt({"symbol": "EURUSD", "timeframe": "M5", "market_state": {"atr": 0.0012}, "risk": {"max_drawdown_pct": 5}})
    assert "EURUSD" in prompt
    assert "M5" in prompt
    assert "max_drawdown_pct" in prompt
