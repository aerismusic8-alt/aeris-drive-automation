# AI Worker Feasibility & Dispatch System — Design Specification

**Date:** 2026-09-02
**Status:** APPROVED FOR SPECIFICATION REVIEW
**Owner:** AX / K final authority

## 1. Objective

Add a non-blocking task-intake layer in which K can provide AX with an objective and deadline. Before dispatching work, AX evaluates feasibility, required resources, worker allocation, expected completion time, risks/dependencies, and probability of success. AX dispatches only after K approval.

Every completed task must pass the universal success gate: Execute → Output → Verify → Evidence → Success.

## 2. Non-Interference Rule

The new intake/feasibility system is additive and must not interrupt, cancel, delay, or overwrite existing jobs that are already running or waiting for output.

Active jobs retain priority. New workers/resources may be used to accelerate active work only when doing so is safe, isolated, and does not create collisions or resource contention.

## 3. Feasibility Gate

For each new task AX records:

- Problem
- Cause / complexity
- Solution approach
- Required resources
- Gemini role
- Copilot role
- Other worker roles
- Estimated time
- Risks / dependencies
- Probability of success
- Verification method
- Evidence expected

No dispatch occurs until K approves the proposed execution plan.

## 4. Worker Qualification

Any additional AI worker must pass a qualification test before becoming an approved executor.

Required report fields:

- AI name
- Capability
- Suitable tasks
- Integration method
- AX controllability
- Execution speed
- Output quality
- Evidence capability
- Cost
- Account required?
- Permission required?
- Risk
- Expected acceleration
- Test result
- Recommendation

Classification:

- GREEN — account/permission ready and testable
- YELLOW — K action required for account/permission
- RED — poor controllability, unverifiable execution, or unacceptable risk

“100% controllable” is treated as a testable system property within granted permissions, not an assumption.

## 5. Dispatch Architecture

```text
K: Objective + Deadline
        ↓
AX Feasibility Gate
        ├─ Problem / Cause
        ├─ Solution
        ├─ Resources
        ├─ Worker allocation
        ├─ Time estimate
        ├─ Risks / dependencies
        ├─ Verification plan
        └─ Success probability
        ↓
K APPROVE
        ↓
AX DISPATCH
        ↓
Execute → Verify → Evidence
        ↓
Verified Success / Failed / Needs Rework
```

## 6. Worker Roles

- AX — commander, feasibility authority, dispatcher, verification coordinator, executive reporting.
- Gemini — coding/technical execution where qualified and available.
- Microsoft Copilot — Microsoft/Business/Workflow/Data execution where qualified and available.
- Additional AI workers — specialist execution only after qualification and approval.
- GitHub Actions / self-hosted runners — deterministic execution substrate where applicable.

Workers must not concurrently modify the same execution area without an explicit isolation/coordination mechanism.

## 7. Universal Success Gate

A task is successful only when all stages are satisfied:

```text
TASK
↓
EXECUTE
↓
OUTPUT
↓
VERIFY
↓
EVIDENCE
↓
SUCCESS
```

`NOT VERIFIED ≠ SUCCESS`.

Failed verification is recorded as `FAILED` or `NEEDS_REWORK`, not success.

## 8. Existing Work Protection

The feasibility/dispatch layer must observe the current active execution registry and queue state before allocating workers. It must avoid duplicate triggers, conflicting edits, and unnecessary resource competition.

If a qualified worker can safely accelerate an existing job, AX may use that worker without changing the job’s objective or verification requirements.

## 9. Account and Permission Handling

Existing delegated accounts may be used only where the target service accepts them and the required permissions are actually available.

AX must not assume that possession of delegated email access automatically creates a new AI-service account or grants service/API permissions. Service-specific signup, OAuth, API keys, billing, phone verification, or other approval requirements remain explicit dependencies and must be surfaced in the feasibility report.

## 10. Evidence Requirements

Each dispatched task should retain sufficient evidence to establish:

1. What was requested.
2. What was dispatched.
3. Which worker executed it.
4. What output was produced.
5. What verification was performed.
6. Where the evidence is stored.
7. Whether the final state passed the success gate.

## 11. Acceptance Criteria

The design is accepted when the implemented system can demonstrate, with evidence:

- New task intake with objective and deadline.
- Feasibility report generated before dispatch.
- K approval gate respected.
- Existing jobs remain uninterrupted.
- Qualified workers can be assigned by capability.
- Worker collisions are prevented or detected.
- Verification is mandatory before success status.
- Evidence is persisted and traceable.
- Additional AI workers are classified by qualification status.
- Failure/rework states are explicit.

## 12. Implementation Boundary

This document defines the approved architecture. Implementation must be planned separately and executed only after the implementation plan is reviewed under the project’s development workflow.
