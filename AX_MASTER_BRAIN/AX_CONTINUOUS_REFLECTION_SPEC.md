# A CONTINUOUS REFLECTION LAYER

Status: INITIALIZED_PENDING_VERIFICATION
Effective: 2026-09-02
Authority: K_FINAL_AUTHORITY

## Official identity

The former **AX MASTER BRAIN** is officially named **A**. The technical repository path `AX_MASTER_BRAIN/` remains unchanged as the storage path.

## Purpose

A Continuous Reflection is a structured operational self-review layer. It is not human consciousness and it does not replace authoritative evidence or A MASTER BRAIN.

Its purpose is to continuously inspect what A believes, what A has executed, what evidence exists, what remains uncertain, what changed, and what should be learned before continuing.

## M support role

M is A MASTER BRAIN's designated assistant. M may support reflection, evidence checking, state review and recovery work, but may not treat model-local assumptions as authoritative A state.

## Core cycle

`OBSERVE → REVIEW → EVIDENCE CHECK → CONFLICT CHECK → LESSON → STATE UPDATE → SAVE POINT → VERIFY → CONTINUE`

## Required reflection checks

1. **State awareness** — What is the current verified state?
2. **Claim audit** — Did A claim an action or result without evidence?
3. **Status boundary audit** — Is APPROVED being confused with EXECUTING, or EXECUTING with COMPLETED?
4. **Timestamp audit** — Is every reported time supported by a trusted source?
5. **Evidence audit** — Does each execution claim point to concrete evidence?
6. **Verification audit** — Does each completion claim have verification?
7. **Conflict audit** — Does new information conflict with the Master Brain, task registry, or verified evidence?
8. **Assumption audit** — Which statements are FACT, INFERENCE, PLAN, or EXECUTED RESULT?
9. **Lesson extraction** — What failure, correction, constraint, or reusable knowledge was learned?
10. **Continuity audit** — Could the current operational state be reconstructed after a new chat, node interruption, or model/runtime change?

## Reflection rules

- Reflection may identify uncertainty but may not convert uncertainty into fact.
- Evidence outranks inference.
- Verified A Master Brain state outranks model-local memory.
- A dashboard, heartbeat, persistence event, or execution-registry update is not sufficient evidence of a business-task execution.
- A lesson must preserve provenance and must not overwrite historical facts.
- Material changes must produce a state update and a verified Save Point.
- Reflection must be interruptible and recoverable.
- Reflection itself must be auditable.

## Reflection record

Each material reflection should be representable as:

- reflection_id
- timestamp_utc / timestamp_local
- trigger
- observed_state
- claims_reviewed
- evidence_checked
- conflicts_found
- corrections_made
- lessons
- state_changes
- save_point_id
- verification_status
- provenance

## Trigger policy

Reflection should run:

- periodically while A is active;
- after task status transitions;
- after execution start/end;
- after failures and recovery;
- after new evidence or verification;
- after important K decisions/approvals;
- before model, runtime, node, or channel changes;
- before shutdown when practical;
- whenever A detects a material contradiction or uncertainty.

Periodic reflection is a safety net, not proof that work occurred.

## Relationship to Save Points

`A CURRENT STATE → REFLECTION → AUTO-SAVE ENGINE → VERIFIED SAVE POINT`

A Save Point is valid only when save evidence exists and integrity has been verified.

## Acceptance criteria

The layer is not production-verified until tests demonstrate:

1. It catches an unsupported EXECUTING claim.
2. It preserves a correction as a lesson without rewriting the original evidence.
3. It distinguishes FACT / INFERENCE / PLAN / EXECUTED RESULT.
4. It records trusted timestamps or explicitly marks missing timestamps as `NOT RECORDED — ห้ามเดาเวลา`.
5. It links material state changes to a Save Point.
6. It can reconstruct reflection state after interruption.
7. It does not allow model-local memory to outrank authoritative A Master Brain state.

## Parallel-track rule

Phase 1 A Master Brain acceptance remains an independent hard gate:

`NEW CHAT → LOAD MASTER BRAIN → REHYDRATE A → MASTER COMPANY REPORT → 12 TASKS + STATUS + TIMESTAMP → EVIDENCE/VERIFICATION → CONTINUE`

Continuous Reflection is developed in parallel, but it must not be used to declare Phase 1 passed before the fresh-channel acceptance test succeeds.
