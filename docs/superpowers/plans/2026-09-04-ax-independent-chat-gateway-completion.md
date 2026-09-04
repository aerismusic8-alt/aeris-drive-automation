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
- No unrelated workflow is added to this feature.

## Tasks

### Task 1 — RED acceptance tests — IMPLEMENTED
Focused acceptance tests and a dedicated CI workflow were added first so the intended new behaviors had a RED/GREEN path.

### Task 2 — Gateway session + capability boundary — IMPLEMENTED
Added explicit K/SERVICE/READ_ONLY identities, capability reporting, `/gateway/session`, `/gateway/capabilities`, and HTTP authorization mapping while preserving the K password login flow.

### Task 3 — Idempotency + fail-closed input lifecycle — IMPLEMENTED
Gateway input now requires an idempotency key, rejects duplicates, fails closed on unverified rehydration, and validates request/task identifiers before persistence. The durable inbox enforces idempotency atomically under its write lock.

### Task 4 — AX Web Chat client — IMPLEMENTED
The existing `/operations` surface is now responsive AX Web Chat. It rehydrates session/state/tasks through the gateway, runs M-A-CHECK, submits text plus attachment references, and keeps the token in session storage rather than treating browser state as authoritative.

### Task 5 — External-AI standard API contract — IMPLEMENTED
Gateway contract v1.1 documents provider-neutral routes and K/SERVICE/READ_ONLY capabilities. External clients are constrained to the API boundary and direct Master Brain access remains prohibited.

### Task 6 — Integration verification — IN PROGRESS
Local core verification was executed for the final gateway/queue logic: Python compilation plus lifecycle/idempotency/fail-closed checks passed. A draft PR #10 was opened for repository CI/review. GitHub currently reports no completed status checks for the head commit, so full repository CI and PC1/PC2/Mobile runtime acceptance are not yet evidenced and the feature is not marked production-complete.
