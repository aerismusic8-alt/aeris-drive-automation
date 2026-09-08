# AX 24/7 Autonomous Operation Design

## Authority

K approved the AX 24/7 authorization package. K remains Final Authority. AX receives authority for routine autonomous execution, recovery, persistence, verification, and use of the existing execution infrastructure within the approved scope.

## Objective

AX must continue operating from canonical state without requiring K's chat to trigger each task. The system must recover from routine operational failures and continue toward the highest-priority revenue objectives.

## Boundaries

AX may autonomously perform routine execution, diagnostics, automation, tests, persistence, evidence collection, verification, and operational recovery. K approval remains mandatory for live financial execution, financial transfers, material new capital, material authority/mission changes, and high-risk or irreversible external actions.

XM Live Trade is retired from the active business/execution path. Its historical evidence may remain for audit, but no new live-trading execution should be enabled by the 24/7 architecture.

## Core Design

1. Canonical state and `AX_MASTER_TASK_REGISTRY_v2.json` are the source of current operational task truth.
2. Runtime task selection must not silently consume a stale divergent registry.
3. Agent routing must select only verified executable agents.
4. Runtime endpoint identity must be explicit and validated.
5. The execution cycle is `OBSERVE → DECISION → DISPATCH → EXECUTE → PERSIST → VERIFY → NEXT`, with bounded recovery on operational failure.
6. Evidence is required for execution claims; verification is required for completion claims.
7. Revenue-first scheduling is enforced without creating or padding registry tasks.
8. Chat is a command/approval channel, not the continuous execution trigger.

## Acceptance Criteria

- Runtime and canonical master registry have one consistent task source.
- Exactly one valid current_work pointer exists.
- Routing contains no stale executor that is absent from the verified capability registry.
- Runtime URL identity is verified and consistent for each dispatch path.
- Operational failure can be recovered without a new K chat message.
- State, evidence, and verification survive interruption/restart.
- Revenue-first priority is preserved.
- XM Live Trade cannot become an active execution target through the 24/7 loop.
- No live-money execution or financial transfer is enabled by this change.
