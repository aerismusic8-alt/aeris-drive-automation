# AX Excellent Active Operations & Revenue Control Loop Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Implement a central AX controller that continuously prioritizes canonical work, selects authorized workforce executors, verifies lifecycle evidence, recovers from failures, tracks K blockers, and dispatches the next action without weakening existing safety controls.

**Architecture:** Add a controller layer above the existing dispatcher/routing bridge. Keep canonical task identity and evidence gates authoritative; introduce explicit scoring, execution-attempt state, idempotency/fencing, recovery decisions, and next-action progression. Revenue priority is represented as policy data, while live financial authority remains unchanged.

**Tech Stack:** PowerShell orchestration, JSON canonical/runtime state, existing Python/TypeScript connectors, GitHub Actions tests, existing evidence/write-back and reflection mechanisms.

**Spec:** `docs/superpowers/specs/2026-09-09-ax-excellent-active-operations-revenue-control-loop-design.md`

## Global Constraints

- Result over report: progress requires action, result, evidence, and verification.
- No Silent Stop: every non-completed task has a reason and a next action.
- Canonical task identity is preserved; no competing task IDs.
- Capability metadata never grants execution authority.
- Missing authority, invalid state, conflict, or insufficient evidence fails closed.
- Heartbeat is health evidence only, never task completion evidence.
- Existing execution-contract markers remain mandatory where applicable.
- Retries must not blindly duplicate uncertain side effects.
- Revenue priority cannot authorize live financial activity.
- Unknown timestamps remain `NOT RECORDED`.

---

### Task 1: Define Controller Data Contract

**Files:**
- Create: `AX_EXCELLENT_ACTIVE_CONTROLLER.schema.json`
- Create: `AX_EXCELLENT_ACTIVE_POLICY.json`
- Test: `tests/ax_excellent_active/test_controller_schema.ps1`

**Interfaces:**
- Consumes: canonical task registry, capability registry, existing execution-contract markers.
- Produces: validated controller task/execution/decision structures used by later tasks.

- [ ] **Step 1: Write the failing schema test**

Test that controller records require `task_id`, `execution_id`, `executor`, `status`, `next_action`, and evidence references, and reject records without canonical `task_id`.

- [ ] **Step 2: Run the schema test and verify it fails**

Run: `pwsh -File tests/ax_excellent_active/test_controller_schema.ps1`
Expected: FAIL because the controller schema files do not yet exist.

- [ ] **Step 3: Add the schema and policy**

Define execution identity as `task_id + execution_id + idempotency_key`; define statuses `QUEUED`, `SELECTED`, `ACCEPTED`, `EXECUTING`, `VERIFYING`, `BLOCKED`, `RETRYING`, `REROUTING`, `COMPLETED`, `FAILED`; define priority classes matching the canonical survival/revenue ordering and urgent event classes from the spec.

- [ ] **Step 4: Run the schema test and verify it passes**

Run: `pwsh -File tests/ax_excellent_active/test_controller_schema.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AX_EXCELLENT_ACTIVE_CONTROLLER.schema.json AX_EXCELLENT_ACTIVE_POLICY.json tests/ax_excellent_active/test_controller_schema.ps1
git commit -m "feat: define excellent active controller contract"
```

### Task 2: Implement Workforce Scoring and Selection

**Files:**
- Create: `AX_EXCELLENT_ACTIVE_WORKFORCE.ps1`
- Test: `tests/ax_excellent_active/test_workforce_selection.ps1`
- Modify: `AX_AGENT_CAPABILITY_REGISTRY.json`

**Interfaces:**
- Consumes: capability registry and controller policy.
- Produces: `Select-WorkforceExecutor -TaskId <string> -Candidates <string[]>` returning an executor plus scored rationale, excluding disabled/unavailable connectors.

- [ ] **Step 1: Write failing selection tests**

Cover capability match, `execution_enabled=false`, missing connector, and tie-breaking by verified success rate then evidence quality.

- [ ] **Step 2: Run the tests and verify failure**

Run: `pwsh -File tests/ax_excellent_active/test_workforce_selection.ps1`
Expected: FAIL because `AX_EXCELLENT_ACTIVE_WORKFORCE.ps1` is absent.

- [ ] **Step 3: Implement selection**

Load only allowlisted agents; score capability match, availability, connector health, verified success/failure history, evidence quality, dependency readiness, observable limits, and task criticality. Never infer that registry `ACTIVE` means a connector is currently healthy.

- [ ] **Step 4: Run tests and verify pass**

Run: `pwsh -File tests/ax_excellent_active/test_workforce_selection.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AX_EXCELLENT_ACTIVE_WORKFORCE.ps1 AX_AGENT_CAPABILITY_REGISTRY.json tests/ax_excellent_active/test_workforce_selection.ps1
git commit -m "feat: add dynamic workforce executor selection"
```

### Task 3: Add Recovery, Idempotency, and K-Blocker Control

**Files:**
- Create: `AX_EXCELLENT_ACTIVE_RECOVERY.ps1`
- Create: `AX_EXCELLENT_ACTIVE_BLOCKERS.json`
- Test: `tests/ax_excellent_active/test_recovery_and_blockers.ps1`

**Interfaces:**
- Consumes: controller execution state and workforce selection result.
- Produces: `Get-RecoveryDecision`, `New-KBlocker`, `Resolve-KBlocker`, and idempotency/fencing validation results.

- [ ] **Step 1: Write failing recovery tests**

Test fail → retry, retry exhaustion → alternate executor, stale execution → reroute, uncertain side effect → reconciliation required, authority-required step → K blocker, blocker clear → resume.

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tests/ax_excellent_active/test_recovery_and_blockers.ps1`
Expected: FAIL because recovery functions do not exist.

- [ ] **Step 3: Implement recovery**

Use deterministic attempt IDs and idempotency keys; fence stale attempts before side-effecting retry; never claim a side effect is absent when outcome is uncertain. K blockers must store task ID, required action, authority reason, impact, urgency, deadline, status, last follow-up, and next follow-up.

- [ ] **Step 4: Run and verify pass**

Run: `pwsh -File tests/ax_excellent_active/test_recovery_and_blockers.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AX_EXCELLENT_ACTIVE_RECOVERY.ps1 AX_EXCELLENT_ACTIVE_BLOCKERS.json tests/ax_excellent_active/test_recovery_and_blockers.ps1
git commit -m "feat: add failure recovery and K blocker control"
```

### Task 4: Implement Central Excellent Active Controller Loop

**Files:**
- Create: `AX_EXCELLENT_ACTIVE_CONTROLLER.ps1`
- Test: `tests/ax_excellent_active/test_controller_loop.ps1`

**Interfaces:**
- Consumes: canonical registry, workforce selector, existing routing bridge, recovery functions, controller policy.
- Produces: `Invoke-ExcellentActiveCycle -TaskId <string>` with lifecycle evidence and next-action decision.

- [ ] **Step 1: Write failing lifecycle tests**

Test `ASSESS → SELECT → ACCEPT → EXECUTE → VERIFY → WRITE_BACK → NEXT_ACTION`, revenue priority over speculative work, and no completion from heartbeat-only output.

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tests/ax_excellent_active/test_controller_loop.ps1`
Expected: FAIL because the controller loop does not exist.

- [ ] **Step 3: Implement the controller**

Load current canonical task state; rank executable work; select an authorized worker; invoke the existing routing bridge; require the full execution contract; verify evidence; write back state; and emit a concrete next action. On failure/stall call recovery and reroute rather than stopping silently.

- [ ] **Step 4: Run and verify pass**

Run: `pwsh -File tests/ax_excellent_active/test_controller_loop.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AX_EXCELLENT_ACTIVE_CONTROLLER.ps1 tests/ax_excellent_active/test_controller_loop.ps1
git commit -m "feat: implement central excellent active controller"
```

### Task 5: Integrate Existing Routing and Evidence Write-Back

**Files:**
- Modify: `AX_AGENT_ROUTING_BRIDGE.ps1`
- Modify: `AX_AGENT_DISPATCH.ps1`
- Test: `tests/ax_excellent_active/test_routing_integration.ps1`

**Interfaces:**
- Consumes: controller-selected executor and execution identity.
- Produces: verified execution contract while preserving existing dispatcher semantics.

- [ ] **Step 1: Write failing integration tests**

Verify custom candidate ordering reaches the dispatcher, failed first executor can be replaced, and a connector lacking required evidence markers is rejected.

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tests/ax_excellent_active/test_routing_integration.ps1`
Expected: FAIL for at least the new candidate-ordering/recovery behavior.

- [ ] **Step 3: Implement minimal integration**

Allow the controller to supply the candidate list and execution identity without weakening registry, route-gate, connector-existence, or full-contract checks. Preserve `TASK_COMPLETION=NOT_CLAIMED` behavior in the routing layer.

- [ ] **Step 4: Run integration tests**

Run: `pwsh -File tests/ax_excellent_active/test_routing_integration.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AX_AGENT_ROUTING_BRIDGE.ps1 AX_AGENT_DISPATCH.ps1 tests/ax_excellent_active/test_routing_integration.ps1
git commit -m "feat: integrate controller with verified routing contract"
```

### Task 6: Add Continuous Watchdog and Queue Re-evaluation

**Files:**
- Create: `AX_EXCELLENT_ACTIVE_WATCHDOG.ps1`
- Test: `tests/ax_excellent_active/test_watchdog.ps1`

**Interfaces:**
- Consumes: controller state, runtime health, blocker age, evidence timestamps, revenue-priority signals.
- Produces: queue re-evaluation events and stale-execution recovery decisions.

- [ ] **Step 1: Write failing watchdog tests**

Cover stale execution, failed executor, missing evidence, aging K blocker, revenue-task stagnation, and infrastructure degradation. Verify heartbeat alone does not trigger completion.

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tests/ax_excellent_active/test_watchdog.ps1`
Expected: FAIL because watchdog does not exist.

- [ ] **Step 3: Implement event-driven watchdog**

Use observable state and platform-supported scheduling; do not claim a one-minute cadence unless the runtime can sustain it. Emit re-evaluation events instead of inventing execution evidence.

- [ ] **Step 4: Run and verify pass**

Run: `pwsh -File tests/ax_excellent_active/test_watchdog.ps1`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AX_EXCELLENT_ACTIVE_WATCHDOG.ps1 tests/ax_excellent_active/test_watchdog.ps1
git commit -m "feat: add excellent active watchdog"
```

### Task 7: End-to-End Acceptance and Runtime Write-Back

**Files:**
- Create: `tests/ax_excellent_active/test_end_to_end.ps1`
- Modify: existing runtime/evidence write-back files identified by the test fixture after inspection.
- Modify: `.github/workflows/*` relevant AX acceptance workflow.

**Interfaces:**
- Consumes: all controller components.
- Produces: machine-verifiable acceptance evidence for success criteria 1–11.

- [ ] **Step 1: Write failing end-to-end acceptance tests**

Exercise automatic task selection, workforce selection, execution evidence, failed-worker recovery, K blocker creation/clear/resume, canonical write-back, next-action dispatch, duplicate-side-effect fencing, revenue priority, and failure-closed behavior.

- [ ] **Step 2: Run and verify failure**

Run: `pwsh -File tests/ax_excellent_active/test_end_to_end.ps1`
Expected: FAIL until all controller components are integrated.

- [ ] **Step 3: Implement only missing integration required by acceptance**

Use the existing canonical state and evidence mechanisms; do not create alternate task registries or bypass live-financial controls.

- [ ] **Step 4: Run the full acceptance suite**

Run: `pwsh -File tests/ax_excellent_active/test_end_to_end.ps1`
Expected: PASS with explicit evidence for each success criterion.

- [ ] **Step 5: Commit**

```bash
git add tests/ax_excellent_active .github/workflows
 git commit -m "test: verify excellent active operations loop"
```

## Final Verification

Run the repository's existing runtime and acceptance tests in addition to the new suite. Verify the current known acceptance blocker is either resolved with evidence or remains explicitly recorded; never convert a failed run into a success claim. Confirm no unauthorized live financial action is introduced.
