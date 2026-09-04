# AX Independent Chat Gateway Design

**Date:** 2026-09-04  
**Status:** Design approved by K in conversation; written spec awaiting final written review before implementation planning.  
**Scope:** AX access channel independent of ChatGPT, with a browser chat surface and a standard external-AI API boundary.  
**Corporate boundary:** This design is for AX / AKATH infrastructure only and does not make AERIS a component of the AX Master Brain.

## 1. Goal

Provide a durable client access layer through which K can reach the same AX identity from PC1, PC2, and Mobile, while keeping `AX_MASTER_BRAIN` independent of any chat UI or AI model provider.

The system must also expose a standard authenticated service interface so external AI models can request AX capabilities without receiving K-level authority or direct ownership of the Master Brain.

## 2. Core invariants

1. `A_MASTER_BRAIN` is the authoritative source of truth for AX identity, mission, state, tasks, evidence, and verification.
2. Chat UI is a transport/view layer, not the brain.
3. AI model identity is not AX identity.
4. K remains Final Authority.
5. External AI clients use a least-privilege service identity and cannot redefine AX identity or K authority.
6. Browser/client session state is not authoritative memory.
7. Raw binary attachments are not written into Master Brain state; only controlled references/metadata are carried.
8. `QUEUED`, `EXECUTING`, and `COMPLETED` remain distinct states.
9. A completion claim requires sufficient evidence and verification.
10. Failed rehydration is fail-closed for control operations.
11. Idempotency prevents replayed requests from causing duplicate command execution.

## 3. Architecture

```text
                    K / Client
                        |
             +----------+----------+
             |                     |
             v                     v
       AX WEB CHAT             EXTERNAL AI
             |                     |
             +----------+----------+
                        |
                        v
                AX CONTROL HUB
        +-----------+----+------------+
        |           |                 |
      Auth       Session           Routing
        |           |                 |
        +-----------+-----------------+
                        |
                        v
                 AX REHYDRATION
                        |
                        v
                 AX MASTER BRAIN
                        |
                        v
                  AKATH RUNTIME
                        |
                 Evidence -> Verify
```

The existing `AX_CONTROL_HUB` remains the control/transport boundary. No second gateway or competing state store is introduced.

## 4. Existing foundation

The repository already contains the core Control Hub contract and local reference runtime. The contract defines authenticated gateway routes, state/task/evidence semantics, idempotency requirements, and the rule that the gateway is not the source of truth. The reference runtime reads `A_MASTER_BRAIN/AX_MASTER_STATE.json` and `A_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json` and fails closed when authoritative sources are unavailable.

Existing browser surface: `/operations`. Existing routes include `/auth/login`, `/gateway/input`, `/gateway/state`, `/gateway/tasks`, `/gateway/m-a-check`, and evidence lookup. The current browser surface is a foundation/reference client and must be extended rather than duplicated.

## 5. Web Chat design

### 5.1 Client role

`AX Web Chat` is a responsive browser surface for PC1, PC2, and Mobile. It is a client of the Control Hub.

The browser may store only non-authoritative presentation/session data such as a short-lived session token and UI state. It must never treat browser state as the canonical AX state.

### 5.2 Session lifecycle

A new browser/chat session performs:

```text
AUTH
  -> SESSION
  -> REHYDRATION REQUEST
  -> LOAD MASTER STATE
  -> LOAD TASK REGISTRY
  -> VERIFY AUTHORITY / IDENTITY / SOURCE
  -> AX CONTEXT READY
```

A successful context must identify the source as `A_MASTER_BRAIN` and preserve AX identity independently of the model/provider used by the client.

### 5.3 Message lifecycle

```text
INPUT
 -> AUTH
 -> VALIDATE
 -> CORRELATION ID
 -> IDEMPOTENCY CHECK
 -> REHYDRATE
 -> ROUTE
 -> QUEUE / EXECUTE
 -> EVIDENCE
 -> VERIFY
 -> RESPONSE
```

The UI must expose authoritative status/evidence separately from health or transport status.

### 5.4 Attachments

The chat client submits attachment metadata/references. Binary content is kept outside Master Brain state and is handled by an approved storage/execution path.

## 6. External AI API design

The preferred model is a single standard AX API boundary with service identities.

```text
Gemini / Claude / Copilot / Other AI
                  |
                  v
            AX API Gateway
       +----------+-----------+
       | Auth / Capability    |
       | Correlation          |
       | Idempotency          |
       | Audit                |
       +----------+-----------+
                  |
                  v
            AX Control Hub
                  |
                  v
            AX Master Brain
```

External AI clients must not access Master Brain files or storage directly.

### 6.1 Permission model

`K`:
- full operator authority subject to approved command policy
- approved control operations
- emergency-stop authority through separately authorized operation

`SERVICE`:
- read approved state/task/evidence
- submit approved inputs
- receive task/evidence results
- cannot elevate authority
- cannot redefine AX identity
- cannot alter K authority

`READ_ONLY`:
- state/task/evidence visibility only

### 6.2 Identity challenge

`M-A-CHECK` verifies the rehydrated identity context. Passing the challenge does not convert the calling model into A. Model/provider identity remains distinct from AX identity.

## 7. Continuity and recovery

A new client session must rehydrate from the authoritative Master Brain rather than constructing a new AX state.

If a worker/browser/session terminates after evidence is recorded, recovery must inspect durable evidence and request idempotency before deciding whether to resume, recover state writeback, or reject as duplicate.

Recovery must never blindly replay a control request because a previous client lost its session.

## 8. Failure handling

The following conditions are fail-closed:

- Master Brain state unavailable
- task registry unavailable
- rehydration contract unavailable
- source-of-truth integrity failure
- authentication failure
- authorization failure
- duplicate idempotency key
- insufficient evidence for completion
- verification failure

Errors must be machine-readable and must not expose credentials/secrets.

## 9. Phase 1 acceptance criteria

The implementation is accepted only when real execution evidence demonstrates:

- Web Chat opens from PC1.
- Web Chat opens from PC2.
- Web Chat opens from Mobile.
- Authentication/session lifecycle works.
- New session rehydrates the same AX context from Master Brain.
- M-A-CHECK passes when authoritative sources are valid.
- User input reaches the gateway and returns a correlated request result.
- `request_id` and idempotency prevent duplicates.
- Evidence can be retrieved by correlation/request ID.
- Restart/recovery does not create a competing AX state.
- Browser UI does not become the source of truth.
- External AI access is constrained by SERVICE identity and capability policy.
- Failed rehydration blocks control operations.

## 10. Implementation boundaries

Initial work should extend the existing `AX_CONTROL_HUB` implementation and browser client. Do not create a parallel gateway, duplicate state store, or provider-specific AX brain.

Likely implementation areas include:

- `AX_CONTROL_HUB/ax_control_hub_server.py`
- `AX_CONTROL_HUB/operations.html`
- `AX_CONTROL_HUB/operations_client.js`
- existing gateway/auth/input-queue modules where required
- focused tests/E2E probes for session, rehydration, API permissions, and recovery
- this specification and related implementation documentation

No financial/live execution capability is added by this chat-gateway work.

## 11. Verification standard

A feature is not considered complete from a code review alone. Completion requires real runtime evidence plus verification showing the intended state transitions and source-of-truth invariants.

Health checks are not proof of execution. Queue presence is not proof of completion. A response stating success without sufficient evidence is not accepted as completion.

## 12. Out of scope for this phase

- moving or duplicating AX Master Brain into a chat provider
- making ChatGPT a required runtime dependency
- direct filesystem access for external AI clients
- provider-specific permanent memory stores that compete with Master Brain
- live financial execution
- unrelated AERIS product workflows
