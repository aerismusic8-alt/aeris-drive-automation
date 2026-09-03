# Rehydration Contract Acceptance Tests

These are acceptance cases for the A MASTER BRAIN rehydration adapter. They are intentionally defined before implementation behavior is accepted.

## Test R1 — Authoritative load order

**Given:** A MASTER STATE, master task registry, rehydration contract, and latest evidence/verification exist.

**When:** a runtime starts.

**Then:** it loads the rehydration contract, master state, master task registry, latest evidence/verification, reconstructs A context, verifies consistency, and only then continues.

**Failure:** any missing authoritative input produces a non-verified startup state.

## Test R2 — Identity reconstruction

**Given:** `AX_MASTER_STATE.json` identifies the authoritative identity as A and M as support agent.

**When:** rehydration runs.

**Then:** reconstructed identity is A; support role is M; M is never promoted to A by chat-local text.

## Test R3 — Task continuity

**Given:** the authoritative task registry contains the current task set and statuses.

**When:** rehydration runs in a fresh channel/runtime.

**Then:** the same authoritative task IDs/statuses are reconstructed without inference from heartbeat or dashboard activity.

## Test R4 — Source-of-truth precedence

**Given:** chat-local state conflicts with A MASTER BRAIN.

**When:** rehydration compares sources.

**Then:** A MASTER BRAIN wins; the conflict is recorded; the runtime does not silently overwrite authoritative state.

## Test R5 — Evidence gate

**Given:** a task is marked APPROVED or EXECUTING but has no valid evidence/verification.

**When:** rehydration evaluates completion.

**Then:** the task is not reported COMPLETED.

## Test R6 — Model independence

**Given:** the same authoritative files are loaded by two different compatible runtimes.

**When:** each runtime reconstructs context.

**Then:** identity, mission, authority, task state, and source-of-truth precedence are equivalent; model-local memory does not outrank persistent state.

## Test R7 — Corrupt/missing state

**Given:** an authoritative file is missing, malformed, or unreadable.

**When:** startup occurs.

**Then:** rehydration fails closed with an explicit NOT_VERIFIED result and no execution is authorized.

## Test R8 — Fresh-channel challenge

**Given:** a new chat/channel has no prior local context.

**When:** `M-A-CHECK` is invoked.

**Then:** the runtime loads authoritative state and returns a PASS only if every identity/continuity acceptance gate passes.
