# AX Excellent Active Operations & Revenue Control Loop — Design Specification

**Date:** 2026-09-09  
**Status:** APPROVED DIRECTION / DESIGN BASELINE  
**Authority:** K_FINAL_AUTHORITY  
**Canonical company:** AKATH  

## 1. Objective

Upgrade AX from passive task dispatch/heartbeat behavior into an Excellent Active operations controller that continuously moves company work toward verified outcomes, with revenue and liquidity treated as urgent operating priorities.

The controller must use every AI, tool, runtime, and execution capability that is actually available and authorized as one workforce pool. AX selects, orders, retries, reroutes, verifies, escalates, and records work without requiring K to manually coordinate ordinary execution.

## 2. Non-Negotiable Operating Principles

1. Result over report: progress is counted only from action, result, evidence, and verification.
2. No Silent Stop: every non-completed task has a reason and a next action.
3. No executor lock-in: an executor may be replaced when it fails, stalls, lacks capability, or becomes unavailable.
4. K is not the routine operations bottleneck: ordinary work must self-route; K blockers receive explicit escalation and follow-up state.
5. Evidence gates completion: heartbeat, approval, planning, or executor claims are not completion evidence.
6. Canonical task identity is preserved: every execution attaches to the existing stable task_id.
7. Financial/high-risk boundaries remain enforced: workforce orchestration cannot create authorization that does not exist.
8. Failure closed: missing authority, invalid state, conflicting state, or insufficient evidence prevents unsafe progression.
9. Revenue-first priority: cash survival, revenue generation/collection, and revenue-enabling operations outrank speculative expansion.
10. Continuous improvement: execution outcomes feed executor scoring and routing decisions.

## 3. Central Controller

Introduce a single conceptual authority: `AX_EXCELLENT_ACTIVE_CONTROLLER`.

Inputs:
- canonical master state
- canonical task registry
- agent capability registry
- execution history/evidence
- runtime/node health
- deadlines and urgency
- revenue/cash risk signals
- K-blocker state

Outputs:
- prioritized execution queue
- executor selection
- execution lease/idempotency identity
- retry/reroute decision
- escalation state
- verified result/write-back
- next action

The controller owns orchestration, not business authority. It cannot override K_FINAL_AUTHORITY, risk controls, security controls, or explicit live-financial authorization boundaries.

## 4. Workforce Pool

All currently authorized execution-capable workers are represented through a common workforce abstraction. Initial known executors include OPENAI, GEMINI_API, GEMINI_CLOUDFLARE, and GEMINI_LIVE_CODE_STREAM, subject to their live registry status and connector availability.

The pool is dynamic. Discovery does not imply authorization, and registry metadata does not imply current execution.

Each candidate is evaluated on:
- capability match
- availability
- execution_enabled state
- connector health
- recent verified success rate
- recent failure/stall rate
- evidence quality
- dependency readiness
- execution limits/cost where observable
- task criticality

## 5. Routing and Recovery Loop

For each executable task:

`ASSESS → SELECT → ACCEPT → EXECUTE → VERIFY → WRITE_BACK → NEXT_ACTION`

Failure path:

`FAIL/STALL → DIAGNOSE → RETRY → ALTERNATE EXECUTOR → FALLBACK → ESCALATE`

The controller must not treat an executor invocation as task completion. Existing execution-contract markers remain mandatory where applicable:
`AGENT_TASK_ACCEPTED`, `AGENT_TASK_EXECUTING`, `AGENT_TASK_RESULT`, `AGENT_EVIDENCE_VERIFIED`, `AGENT_WRITE_BACK_VERIFIED`.

## 6. Priority and Urgency

Priority is evaluated continuously, not only at startup.

Highest urgency classes:
- CASH_SURVIVAL
- REVENUE_BLOCKER
- PAYMENT/DEADLINE RISK
- CRITICAL INFRASTRUCTURE FAILURE
- K_BLOCKER
- EXECUTION SAFETY/RISK EVENT

The controller must re-evaluate the queue when a critical signal changes. Long-running low-value work cannot starve urgent revenue or continuity work.

## 7. K Blocker Control

When a task genuinely requires K action, create a structured blocker containing:
- task_id
- required K action
- reason AX cannot perform it under current authority
- business/system impact
- urgency
- deadline if known
- status
- last follow-up
- next follow-up

AX may remind/escalate according to the configured communication capability. AX must not fabricate completion or bypass the required authorization.

Once the blocker clears, the controller automatically resumes the task and dispatches the next action.

## 8. Duplicate Execution Protection

Every execution attempt receives an execution identity linked to the canonical task_id. Operations capable of causing side effects must use idempotency/fencing semantics where supported.

The controller must distinguish:
- task identity
- execution attempt
- executor identity
- result/evidence identity

A retry must not blindly duplicate a side effect whose prior outcome is uncertain.

## 9. Revenue Control Loop

The controller continuously watches the revenue mission and related work. For the current survival-mode baseline, revenue work is prioritized ahead of speculative expansion.

The revenue loop is:

`OPPORTUNITY → QUALIFY → ASSIGN → EXECUTE → CUSTOMER/TRANSACTION RESULT → VERIFY → CASH RESULT → IMPROVE/SCALE`

A plan, prospect list, generated copy, or unverified claim is not revenue.

## 10. State and Evidence

The controller writes operational state back to canonical/runtime state without creating competing task identities.

Required state dimensions include:
- current task
- current step
- executor
- execution attempt
- started/finished timestamps when trusted
- status
- blocker
- retry count
- next action
- evidence references
- verification result

Unknown timestamps remain `NOT RECORDED` rather than invented.

## 11. Monitoring Cadence

The architecture supports continuous watchdog evaluation and event-driven re-evaluation. A heartbeat is a health signal only. It is not evidence of task execution.

The controller should detect:
- stale execution
- failed executor
- missing evidence
- task inactivity
- dependency failure
- K blocker aging
- revenue task stagnation
- infrastructure degradation

The exact scheduler/interval is an implementation concern and must respect platform/API limits; the design does not claim a frequency that the runtime cannot actually sustain.

## 12. Existing-System Integration

The design extends rather than replaces the existing canonical controls.

Existing components to integrate:
- `AX_MASTER_BRAIN/AX_MASTER_STATE.json`
- `AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json`
- `AX_AGENT_CAPABILITY_REGISTRY.json`
- `AX_AGENT_DISPATCH.ps1`
- `AX_AGENT_ROUTING_BRIDGE.ps1`
- existing evidence/write-back and continuous-reflection mechanisms

The current dispatcher already verifies an execution contract and falls back when no executable connector satisfies it. The new controller adds continuous prioritization, workforce selection, recovery, escalation, and next-action progression above that contract rather than weakening it.

## 13. Safety Boundaries

The controller must never:
- invent execution evidence
- claim completion from heartbeat
- create authority from capability metadata
- bypass credential/security controls
- disable risk controls
- perform unauthorized live financial actions
- create competing canonical task IDs
- silently resend uncertain side-effecting operations

## 14. Success Criteria

The design is considered operationally successful only when implementation evidence demonstrates all of the following:

1. A canonical task is automatically selected from the queue.
2. An authorized executor is selected from the workforce pool.
3. Execution produces verifiable lifecycle evidence.
4. A failed/stalled executor causes recovery/rerouting without manual task reconstruction.
5. A K blocker is explicitly tracked and escalated rather than silently stopping work.
6. Clearing a blocker causes automatic continuation.
7. Verified results are written back to canonical/runtime state.
8. The next action is dispatched automatically.
9. Duplicate side effects are prevented or reconciled.
10. Revenue-critical work is demonstrably prioritized.
11. Tests prove failure-closed behavior and evidence-gated completion.

## 15. Explicit Non-Goals

This design does not itself authorize live trading, financial transfers, credential handling, or unrestricted OS control. Those remain governed by their existing authorization and safety controls.

This design also does not claim that every discovered AI/tool is currently connected or executable. Workforce membership is based on verified availability and authorization at runtime.
