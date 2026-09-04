# AX Independent Chat Gateway Completion Plan

**Spec:** `docs/superpowers/specs/2026-09-04-ax-independent-chat-gateway-design.md`

**Goal:** Complete the existing `AX_CONTROL_HUB` into an AX Web Chat + standard external-AI gateway without creating a second brain, state store, or provider-specific identity.

## Global constraints
- `A_MASTER_BRAIN` remains the sole authoritative AX source.
- Browser/session state is non-authoritative.
- K remains Final Authority; SERVICE is least privilege; READ_ONLY is read-only.
- No raw binary attachments enter Master Brain.
- Rehydration failure is fail-closed for control operations.
- `request_id` plus idempotency prevents duplicate execution.
- `QUEUED`, `EXECUTING`, `COMPLETED` remain distinct and completion requires evidence + verification.
- No AERIS workflow/component is added to this feature.

## Tasks

### Task 1 — RED acceptance tests
Add focused tests for session/rehydration, service identity/capabilities, idempotency, fail-closed behavior, attachment references, and responsive AX Web Chat surface. Add a dedicated CI workflow so the new tests provide observable RED/GREEN evidence.

### Task 2 — Gateway session + capability boundary
Extend the existing auth/gateway boundary with explicit K/SERVICE/READ_ONLY identities, a session/context endpoint, capability reporting, and authorization checks. Preserve the existing K login flow and do not expose secrets.

### Task 3 — Idempotency + fail-closed input lifecycle
Require/normalize idempotency keys for gateway input, persist them with the durable inbox, reject duplicate keys deterministically, and block control input when authoritative rehydration is not VERIFIED.

### Task 4 — AX Web Chat client
Replace the AERIS-labelled operations surface with a responsive AX Web Chat UI. It must load state/tasks from the gateway, create a session/context, run M-A-CHECK, submit messages/attachment references, and expose request/evidence status without storing authoritative brain state in the browser.

### Task 5 — External-AI standard API contract
Document and test the SERVICE/READ_ONLY boundary and provider-neutral API semantics. External models use the gateway only; no direct Master Brain filesystem access is introduced.

### Task 6 — Integration verification
Run the dedicated Control Hub suite plus existing gateway/recovery tests and inspect the CI run. Verify the branch contains only AX/AKATH infrastructure changes and no AERIS dependency.
