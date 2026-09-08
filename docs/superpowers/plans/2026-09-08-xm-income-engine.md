# XM Income Engine Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing XM execution bridge into a continuously monitored trading-research and risk-control subsystem for the designated XM portfolio, without duplicating the existing XM account path.

**Architecture:** Reuse `XM_MICRO_K_DESIGNATED_ACCOUNT` and `AX_XM_EXECUTION_QUEUE` as the single broker boundary. Add a strategy-research/risk-evaluation engine that produces evidence-backed signals and reports, plus a real-time portfolio sentinel that can force a kill state; live-money order submission remains disabled until explicit risk gates are met and independently verified.

**Tech Stack:** TypeScript Cloudflare Worker/Durable Objects, Python runtime workers, existing AX queue/ledger contracts, existing self-hosted Windows runners, repository tests.

**Spec:** Existing XM bridge architecture and the approved trading subsystem design in conversation.

## Global Constraints

- `XM_MICRO_K_DESIGNATED_ACCOUNT` remains the only account scope.
- Existing XM bridge remains the broker boundary; do not create a second XM account path.
- `COMPLETED + VERIFIED` is required for technical success.
- A trading result is not business revenue unless independently evidenced as real received funds.
- Live-money autonomous execution must remain fail-closed unless explicit risk gates are satisfied and the account state is independently verified.
- Kill switch defaults to enabled whenever terminal state, risk state, or evidence is stale/unknown.
- AI-generated strategy output is advisory until backtest/walk-forward/paper evidence passes required gates.
- GitHub-hosted Actions are not an execution dependency; use existing self-hosted infrastructure.

---

### Task 1: XM risk snapshot contract

**Files:**
- Create: `AKATH/runtime/xm_risk_engine.py`
- Test: `AKATH/tests/test_xm_risk_engine.py`
- Modify: `cloudflare/ax-control-runtime/src/xm-bridge.ts`

**Interfaces:**
- Consumes: XM heartbeat/account/position snapshots.
- Produces: deterministic risk verdict with `ALLOW`, `REDUCE`, or `KILL`; no broker mutation side effects.

- [ ] **Step 1: Write the failing test**

```python
def test_stale_heartbeat_forces_kill():
    from xm_risk_engine import evaluate_risk
    result = evaluate_risk({"equity": 1000, "balance": 1000, "drawdown_pct": 0, "heartbeat_age_sec": 120})
    assert result["decision"] == "KILL"
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `python -m pytest AKATH/tests/test_xm_risk_engine.py::test_stale_heartbeat_forces_kill -v`
Expected: FAIL because `xm_risk_engine` does not yet expose `evaluate_risk`.

- [ ] **Step 3: Write the minimal implementation**

Implement `evaluate_risk(snapshot)` with deterministic rules: stale/missing heartbeat => `KILL`; non-finite equity/balance => `KILL`; negative equity => `KILL`; otherwise calculate drawdown and return the lowest-risk decision allowed by the supplied snapshot.

- [ ] **Step 4: Run the test and verify it passes**

Run: `python -m pytest AKATH/tests/test_xm_risk_engine.py::test_stale_heartbeat_forces_kill -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AKATH/runtime/xm_risk_engine.py AKATH/tests/test_xm_risk_engine.py
 git commit -m "feat: add XM risk evaluation core"
```

---

### Task 2: Real-time portfolio sentinel

**Files:**
- Create: `AKATH/runtime/xm_portfolio_sentinel.py`
- Test: `AKATH/tests/test_xm_portfolio_sentinel.py`
- Modify: `cloudflare/ax-control-runtime/src/xm-bridge.ts`

**Interfaces:**
- Consumes: `XmHeartbeat`, account state, open positions, and risk policy.
- Produces: normalized sentinel state and a kill-switch decision; can enqueue only protective `CLOSE_POSITION`/`MODIFY_POSITION` requests after verification, never speculative entries.

- [ ] **Step 1: Write the failing test**

```python
def test_sentinel_kills_on_terminal_disconnect():
    from xm_portfolio_sentinel import sentinel_decision
    result = sentinel_decision({"terminal_connected": False, "equity": 1000, "balance": 1000})
    assert result["kill_switch"] is True
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `python -m pytest AKATH/tests/test_xm_portfolio_sentinel.py::test_sentinel_kills_on_terminal_disconnect -v`
Expected: FAIL because the sentinel module does not yet exist.

- [ ] **Step 3: Write minimal implementation**

Implement `sentinel_decision(snapshot)` so unknown/disconnected/stale terminal states force the kill switch and expose reasons/evidence fields. Keep all decisions deterministic and JSON serializable.

- [ ] **Step 4: Run the test and verify it passes**

Run: `python -m pytest AKATH/tests/test_xm_portfolio_sentinel.py::test_sentinel_kills_on_terminal_disconnect -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AKATH/runtime/xm_portfolio_sentinel.py AKATH/tests/test_xm_portfolio_sentinel.py cloudflare/ax-control-runtime/src/xm-bridge.ts
git commit -m "feat: add XM portfolio sentinel"
```

---

### Task 3: Strategy research engine

**Files:**
- Create: `AKATH/runtime/xm_strategy_research.py`
- Test: `AKATH/tests/test_xm_strategy_research.py`

**Interfaces:**
- Consumes: market OHLCV/features supplied by the runtime worker.
- Produces: ranked strategy candidates with assumptions, metrics, regime tags, risk limits, and evidence status.

- [ ] **Step 1: Write the failing test**

```python
def test_research_rejects_strategy_without_positive_out_of_sample_expectancy():
    from xm_strategy_research import accept_candidate
    candidate = {"in_sample_expectancy": 0.8, "out_of_sample_expectancy": -0.1, "max_drawdown_pct": 12}
    result = accept_candidate(candidate)
    assert result["accepted"] is False
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `python -m pytest AKATH/tests/test_xm_strategy_research.py::test_research_rejects_strategy_without_positive_out_of_sample_expectancy -v`
Expected: FAIL because `accept_candidate` does not yet exist.

- [ ] **Step 3: Write minimal implementation**

Implement explicit acceptance checks for out-of-sample expectancy, drawdown ceiling, minimum observations, and missing-data rejection. Do not encode a promise of profitability.

- [ ] **Step 4: Run the test and verify it passes**

Run: `python -m pytest AKATH/tests/test_xm_strategy_research.py::test_research_rejects_strategy_without_positive_out_of_sample_expectancy -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AKATH/runtime/xm_strategy_research.py AKATH/tests/test_xm_strategy_research.py
git commit -m "feat: add XM strategy research gate"
```

---

### Task 4: AX periodic trading report and recovery routing

**Files:**
- Create: `AKATH/runtime/xm_ax_report.py`
- Test: `AKATH/tests/test_xm_ax_report.py`
- Modify: `AX_ACTIVE_EXECUTIONS.ps1`

**Interfaces:**
- Consumes: strategy evidence, sentinel state, XM bridge status, task lifecycle state.
- Produces: periodic report plus next action `KEEP`, `RETEST`, `DISABLE`, `KILL`, or `FALLBACK`.

- [ ] **Step 1: Write the failing test**

```python
def test_report_requests_kill_when_sentinel_is_kill():
    from xm_ax_report import build_report
    report = build_report({"sentinel": {"decision": "KILL"}, "strategy": {"accepted": True}})
    assert report["next_action"] == "KILL"
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `python -m pytest AKATH/tests/test_xm_ax_report.py::test_report_requests_kill_when_sentinel_is_kill -v`
Expected: FAIL because the report module does not yet exist.

- [ ] **Step 3: Write minimal implementation**

Implement report generation that prioritizes sentinel safety over strategy recommendations and marks stale/missing evidence explicitly.

- [ ] **Step 4: Run the test and verify it passes**

Run: `python -m pytest AKATH/tests/test_xm_ax_report.py::test_report_requests_kill_when_sentinel_is_kill -v`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AKATH/runtime/xm_ax_report.py AKATH/tests/test_xm_ax_report.py AX_ACTIVE_EXECUTIONS.ps1
git commit -m "feat: add AX XM reporting and recovery routing"
```

---

### Task 5: End-to-end XM verification path

**Files:**
- Create: `AKATH/tests/test_xm_end_to_end.py`
- Modify: `.github/workflows/akath-runtime.yml`
- Modify: `cloudflare/ax-control-runtime/test/xm-bridge.spec.ts`

**Interfaces:**
- Consumes: all prior components.
- Produces: evidence that XM state flows through snapshot -> risk -> sentinel -> report without enabling speculative live-money entries.

- [ ] **Step 1: Write the failing test**

```python
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
```

- [ ] **Step 2: Run the test and verify it fails**

Run: `python -m pytest AKATH/tests/test_xm_end_to_end.py -v`
Expected: FAIL until the full pipeline exists.

- [ ] **Step 3: Wire the pipeline**

Add the minimum self-hosted verification step needed to execute these tests and record the evidence artifact. Keep `live_execution_enabled=false` unless the existing broker handshake and risk evidence are present.

- [ ] **Step 4: Run the full XM test set**

Run: `python -m pytest AKATH/tests/test_xm_risk_engine.py AKATH/tests/test_xm_portfolio_sentinel.py AKATH/tests/test_xm_strategy_research.py AKATH/tests/test_xm_ax_report.py AKATH/tests/test_xm_end_to_end.py -v`
Expected: PASS for all XM tests.

- [ ] **Step 5: Verify repository and runtime state**

Check the resulting workflow run, XM bridge status, and evidence files. A green code test is not sufficient to claim revenue or live-trading success.

- [ ] **Step 6: Commit**

```bash
git add AKATH/tests/test_xm_end_to_end.py .github/workflows/akath-runtime.yml cloudflare/ax-control-runtime/test/xm-bridge.spec.ts
git commit -m "test: verify XM fail-closed trading pipeline"
```
