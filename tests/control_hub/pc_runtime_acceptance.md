# AX Control Hub — PC Runtime Acceptance Tests

These tests are executable acceptance requirements for the Windows PC adapter. They are intentionally defined before runtime implementation.

## T1 — Startup dependency gate
- Given the PC runtime starts with missing master state, task registry, or rehydration contract
- When startup initialization runs
- Then startup fails closed with `SOURCE_STATE_UNAVAILABLE`
- And no command execution is permitted.

## T2 — Authoritative read
- Given valid authoritative A Master Brain files
- When the adapter loads state
- Then identity and task data come from the authoritative files, not dashboard/heartbeat data.

## T3 — M-A-CHECK
- Given valid state, registry, rehydration contract, and verification evidence
- When `POST /m-a-check` is requested
- Then the adapter performs the defined challenge and returns a structured result with evidence references.
- If any gate fails, result must be non-verified and the adapter must not claim A identity.

## T4 — Authentication
- Missing, invalid, expired, or revoked session => `AUTH_REQUIRED` or `AUTH_FAILED`.
- Valid session => request reaches authorization layer.
- Plaintext passwords/secrets must never be logged or persisted by the adapter.

## T5 — Authorization
- `READ_ONLY` can read state/tasks/evidence only.
- `SERVICE` can invoke only explicitly assigned service operations.
- `K` is subject to existing guardrails and approval rules.
- No role can redefine A identity or K authority.

## T6 — Command safety
- Every command requires `request_id`, `idempotency_key`, actor, command, args, and trusted request timestamp.
- Duplicate idempotency key => `DUPLICATE_REQUEST` without a second execution.
- Guardrail violation => `GUARDRAIL_BLOCKED` without execution.

## T7 — Evidence gate
- A command cannot be reported `COMPLETED` without execution evidence and verification evidence.
- `ACCEPTED`, `QUEUED`, `EXECUTING`, or heartbeat state must never be converted into `COMPLETED`.

## T8 — Existing AERIS preservation
- The adapter must sit in front of the existing queue/dispatcher boundary.
- Existing Apps Script `doPost`/node authentication behavior must not be overwritten by the Control Hub adapter in this phase.

## T9 — Fresh-channel reconstruction
- Starting a clean adapter process with no chat-local state must reconstruct A from authoritative storage and produce the same identity/task result.

## T10 — Interruption/resume
- Interrupting the adapter between command acceptance and completion must leave a recoverable request/evidence record.
- Restart must not duplicate an idempotent command.

## T11 — Model/runtime portability
- The same authoritative state must produce equivalent identity/continuity verification through at least two distinct runtime/model paths.
- A model-local memory difference must not change source-of-truth state.

## T12 — Live financial guardrail
- Financial/live-trading commands remain blocked unless their separately defined approval and guardrail requirements are satisfied.
- This acceptance suite must not enable real-money execution.
