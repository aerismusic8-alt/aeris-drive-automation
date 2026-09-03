# AX Control Hub — PC Runtime Adapter Specification

## Role

The PC Runtime Adapter is the local Windows boundary between the AX Control Hub API and existing AERIS execution infrastructure. It is an adapter, not a second Master Brain.

## Source-of-truth order

1. A Master Brain authoritative state
2. A Master Task Registry
3. Rehydration contract and latest evidence/verification
4. Controlled runtime state/evidence produced by execution
5. Dashboard/heartbeat views for health only
6. Chat-local/model-local memory is non-authoritative

## Startup

`START → LOAD MASTER STATE → LOAD TASK REGISTRY → LOAD REHYDRATION CONTRACT → LOAD LATEST EVIDENCE/VERIFICATION → REHYDRATE A → VERIFY → SERVE`

Any required authoritative input that is missing, corrupt, contradictory, or unverifiable causes fail-closed startup.

## Adapter boundary

The adapter may:

- read authoritative A state;
- expose authenticated Control Hub endpoints;
- validate authorization and command schema;
- enforce idempotency and guardrails;
- create request/evidence correlation records;
- dispatch approved commands to an existing execution boundary;
- read back execution evidence and verification results.

The adapter must not:

- redefine A identity;
- promote M to A;
- treat heartbeat as execution proof;
- bypass the existing AERIS queue/dispatcher;
- store plaintext credentials;
- enable live financial execution;
- overwrite authoritative master state without an explicit controlled state-write contract.

## Existing AERIS integration

The current node runner already communicates with the existing Apps Script/node boundary using node registration, heartbeat, pull, execution, and completion flows. The Control Hub adapter must integrate above that boundary rather than replacing it in this phase.

## API mapping

- `GET /health` → local process health only.
- `POST /auth/login` → session establishment.
- `POST /auth/logout` → session revocation.
- `GET /state` → authoritative A state snapshot.
- `GET /tasks` → authoritative task registry.
- `POST /m-a-check` → rehydration/identity challenge.
- `POST /command` → validated, authorized, idempotent command dispatch.
- `GET /evidence/{request_id}` → correlated evidence and verification.
- emergency stop → separately authorized, audited control path.

## Runtime result states

`STARTING`, `READY`, `DEGRADED`, `BLOCKED`, `STOPPED`.

`READY` means the adapter itself passed startup gates. It does not mean A has passed the complete identity/continuity challenge unless `/m-a-check` reports verified evidence.

## Evidence contract

Each externally meaningful command must preserve:

`request_id → idempotency_key → actor → accepted_at → execution_started_at → execution_result → evidence → verification → final_status`

Missing trusted timestamps or verification evidence must prevent a `COMPLETED` claim.

## Security

Default bind is loopback/LAN-only. Remote/mobile access requires authenticated HTTPS or a secure authenticated tunnel. Raw unauthenticated public exposure is prohibited.

Secrets are supplied through protected OS/environment mechanisms and never committed to the repository.

## Acceptance

Implementation is not considered verified until `tests/control_hub/pc_runtime_acceptance.md` T1–T12 have actual runtime evidence. GitHub branch state alone is not runtime proof.
