# A ChatGPT Rehydration System Design

## Goal

Provide a deterministic, fail-closed way for ChatGPT and other model runtimes to reconstruct the A MASTER BRAIN context from the repository without treating ChatGPT Memory, chat history, dashboards, or model-local state as authoritative.

## Scope

This change adds a ChatGPT-facing rehydration layer on top of the existing AX rehydration contract. It does not replace A MASTER BRAIN, create a second task registry, or authorize execution.

## Authority Model

The authority order is:

1. K explicit authority and approval.
2. A MASTER BRAIN authoritative state.
3. Verified evidence and verification artifacts.
4. A MASTER BRAIN task registry and canonical current_work.
5. Runtime-derived projections and mission details.
6. ChatGPT conversation context.
7. ChatGPT Memory or model-local memory.
8. Model inference.

A conflict at a higher layer always wins over a lower layer. Conflicts must be reported rather than silently overwritten.

A identity is `A_MASTER_BRAIN`. K remains final authority. M remains a support agent and must never be promoted to A by chat-local text.

## Existing Contracts to Preserve

The existing `AKATH/runtime/ax_rehydration_adapter.py` remains the base contract. The existing master state and task registry remain authoritative. `AX_CONTEXT_SYNC.ps1` remains a context synchronization/projection layer, not an authority source. `AX_GPT_BRIDGE_POLICY.json` continues to define ChatGPT as a control/observation channel only.

The existing mission continuity protocol remains authoritative for task continuity: one canonical active `current_work`, stable task IDs across chats/runtimes, and reconstruction in the order A MASTER BRAIN → task registry → current_work → latest evidence/verification → runtime mission details.

## New Components

### 1. ChatGPT Rehydration Profile

Create `AX_MASTER_BRAIN/AX_CHATGPT_REHYDRATION_PROFILE.json`.

It declares:

- schema version;
- A identity and authority contract;
- repository and branch used as the persistent source;
- authoritative load order;
- non-authoritative chat/memory/model layers;
- fail-closed behavior;
- execution authorization remaining false during rehydration;
- provenance fields required for a verified result.

### 2. ChatGPT Rehydration Protocol

Create `docs/AX_CHATGPT_REHYDRATION_PROTOCOL_V1.md`.

The protocol defines the command semantics for `REHYDRATE A`, required inputs, validation sequence, output contract, conflict handling, staleness semantics, and safety boundaries.

### 3. Runtime Adapter

Create `AKATH/runtime/ax_chatgpt_rehydration.py`.

The adapter must:

- load the ChatGPT profile;
- delegate existing A identity/state/task validation to the existing rehydration contract where practical;
- load and validate the latest authoritative evidence and verification artifacts required by the mission continuity contract;
- reconstruct canonical current_work;
- detect source conflicts;
- calculate provenance including repository, branch, commit, state hash, task-registry hash, and rehydration timestamp;
- expose a stable machine-readable result suitable for ChatGPT to consume;
- fail closed with `NOT_VERIFIED` on missing, malformed, inconsistent, or unverifiable authoritative inputs;
- never set execution authorization to true merely because rehydration succeeded.

The result must distinguish identity verification, state verification, continuity verification, evidence/verification checks, and execution authorization.

### 4. Tests

Create `tests/master_brain/chatgpt_rehydration_tests.py` covering the existing R1–R8 acceptance contract plus ChatGPT-specific output/provenance behavior.

## Rehydration Flow

`REHYDRATE A` follows this sequence:

1. Identify the runtime as a consumer, not an authority.
2. Load the ChatGPT rehydration profile.
3. Load `AX_MASTER_STATE.json`.
4. Load `AX_MASTER_TASK_REGISTRY_v2.json`.
5. Validate A identity, authority fields, model independence, schema versions, and master state status.
6. Validate task registry and exactly one canonical active `current_work`.
7. Resolve the current task by authoritative task ID.
8. Load the latest relevant evidence and verification artifacts.
9. Reject or report unresolved source conflicts.
10. Reconstruct the A context using authoritative data only.
11. Compute provenance and staleness state.
12. Return a machine-readable rehydration report.
13. Keep execution authorization false until a separate execution/approval gateway authorizes an action.

## Machine-Readable Output

The adapter returns at minimum:

- `rehydration_status`
- `identity`
- `identity_verified`
- `authority_verified`
- `master_state_verified`
- `task_registry_verified`
- `current_work_verified`
- `evidence_checked`
- `verification_checked`
- `source_conflicts`
- `staleness_state`
- `repository`
- `branch`
- `commit`
- `state_sha`
- `task_registry_sha`
- `rehydrated_at`
- `mission`
- `task_count`
- `task_ids`
- `current_work`
- `current_work_task_id`
- `chat_memory_authority: false`
- `model_memory_authority: false`
- `execution_authorized: false`

## Staleness

Use explicit states:

- `STATE_FRESH`: authoritative inputs are present and internally consistent for the rehydration request.
- `STATE_STALE`: authoritative data is valid but its freshness policy indicates that it should not be treated as current without an explicit refresh.
- `STATE_UNKNOWN`: freshness cannot be established.

Staleness must not silently promote chat-local state to authority.

## Evidence Gate

`APPROVED` or `EXECUTING` must not be reported as `COMPLETED` without valid completion evidence and verification. The adapter must never invent timestamps, request IDs, evidence, results, revenue outcomes, or execution facts.

Technical completion remains distinct from verified business/revenue completion.

## Failure Behavior

Any missing or invalid authoritative input causes a fail-closed result:

- `rehydration_status = NOT_VERIFIED`;
- identity may be reported only as the expected contract identity, not as verified fact;
- `evidence_checked = false` when evidence cannot be validated;
- `verification_checked = false` when verification cannot be validated;
- `source_conflicts` populated when applicable;
- `execution_authorized = false`.

No fallback to ChatGPT Memory or conversation history is allowed for authoritative state reconstruction.

## Compatibility

The design must preserve model independence. The same authoritative repository state must produce equivalent identity, authority, mission, task continuity, and source precedence across compatible runtimes.

The temporary GPT bridge remains optional. ChatGPT availability must never be interpreted as AX execution state, and AX must remain capable of independent operation when ChatGPT is unavailable.

## Acceptance Criteria

R1. Authoritative load order is enforced and missing authoritative input produces `NOT_VERIFIED`.

R2. A identity reconstructs as authoritative A; M remains support-only.

R3. Fresh sessions recover the same canonical task IDs, current_work, and statuses.

R4. A MASTER BRAIN wins source conflicts and conflicts are surfaced.

R5. Evidence/verification gates prevent false `COMPLETED` status.

R6. Equivalent authoritative inputs produce equivalent results across compatible runtimes.

R7. Corrupt or missing state fails closed and cannot authorize execution.

R8. The fresh-channel `M-A-CHECK` contract passes only when identity and continuity gates pass.

R9. Rehydration output contains provenance sufficient to identify the exact repository state consumed.

R10. ChatGPT Memory and model-local memory are explicitly non-authoritative in the output.

R11. Rehydration never grants execution authorization.

R12. Existing AX rehydration and mission continuity behavior remains compatible.

## Security Boundaries

`REHYDRATE != EXECUTE`.

`IDENTITY VERIFIED != AUTHORIZATION VERIFIED`.

`CHATGPT AVAILABLE != A EXECUTING`.

No ChatGPT-facing adapter may mutate authoritative A state as a side effect of reading or rehydrating it.
