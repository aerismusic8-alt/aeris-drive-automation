# AX PC1 Specialist Execution Spec

Status: CANONICAL / DESIGN BASE
Authority: K_FINAL_AUTHORITY
Executive: AX
Execution Main: PC1
Governing principle: PCSEV (Problem -> Cause -> Solution -> Execute -> Evidence -> Verify)

## Purpose

Establish one canonical execution path after repository cleanup. PC1 is the main execution node. Specialist roles are execution capabilities under AX dispatch; they do not create competing task registries or workflow branches.

## Canonical loop

1. OBSERVE — load current canonical state and the single current task.
2. RECOVERY CHECK — detect stale, interrupted, or incomplete execution state before dispatch.
3. DECISION — AX selects the next executable step and specialist capability.
4. DISPATCH — send exactly one canonical task step to the selected specialist on PC1.
5. EXECUTE — specialist performs the assigned step.
6. EVIDENCE — execution emits a durable evidence record containing task_id, step_id, worker, start/end timestamps, result, and artifact/reference.
7. VERIFY — AX verifies the evidence against the expected outcome. No evidence means no execution claim; no verification means no completion claim.
8. WRITE-BACK — persist execution state, evidence, verification, and next step against the same canonical task_id.
9. CONTINUE — only after verification, select the next step.

## Specialist boundary

Specialists are capability executors, not authorities. They may execute assigned work, return output, and emit evidence. AX remains responsible for orchestration, state decisions, verification, recovery, and continuation. K remains final authority.

## State invariants

- One canonical branch: `main`.
- One canonical task registry.
- One canonical current_work.
- One stable task_id per task.
- PC1 is the primary execution node.
- No `v2`, `v3`, `final`, `final2`, or parallel replacement workflows.
- Heartbeat is health evidence only; it is not task execution evidence.
- APPROVED is not EXECUTING.
- EXECUTING is not COMPLETED.
- COMPLETED requires independent verification.
- Interrupted execution resumes from the last verified state rather than restarting blindly.
- Runtime projections may not create competing task identities.

## Minimum evidence contract

Every execution step must produce:

- `task_id`
- `step_id`
- `execution_id`
- `node_id` (`PC1` for main execution)
- `specialist`
- `started_at`
- `finished_at`
- `status`
- `output`
- `evidence_ref`
- `verification_status`

## First acceptance test

Use one deterministic, non-destructive task step on PC1. The acceptance path is:

`OBSERVE -> DECISION -> DISPATCH -> EXECUTE -> EVIDENCE -> VERIFY -> WRITE-BACK`

The test passes only when the evidence and verification records can be retrieved after execution and the next continuation state is derived from the verified result.

## Scope control

Do not restore retired workflows, old branch families, XM execution, or parallel orchestration layers as part of this implementation. Build the smallest working loop first, prove it with evidence, then extend specialist capabilities one at a time.
