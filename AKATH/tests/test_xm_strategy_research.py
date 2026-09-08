def test_research_rejects_strategy_without_positive_out_of_sample_expectancy():
    from xm_strategy_research import accept_candidate
    candidate = {"in_sample_expectancy": 0.8, "out_of_sample_expectancy": -0.1, "max_drawdown_pct": 12}
    result = accept_candidate(candidate)
    assert result["accepted"] is False
