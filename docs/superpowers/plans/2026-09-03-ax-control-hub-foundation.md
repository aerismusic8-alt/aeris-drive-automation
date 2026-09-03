# AX Control Hub Foundation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Establish a secure, model-independent AX Control Hub foundation that rehydrates A from authoritative state, accepts commands from ChatGPT/PC/mobile channels, dispatches only through the verified execution layer, and records evidence before completion claims.

**Architecture:** A MASTER BRAIN remains the single source of truth. The Control Hub is a transport/API layer, not a replacement brain; clients authenticate to the hub, the hub loads authoritative state/task registry, and execution flows through the existing AERIS queue/node infrastructure. Mobile and desktop use the same API surface; ChatGPT remains a channel until a verified runtime bridge is available.

**Tech Stack:** Existing AERIS Drive Automation repository, GitHub Actions/self-hosted Windows node, existing Apps Script/queue components, and a small authenticated HTTP control service on the PC. Credentials/secrets remain outside A MASTER BRAIN and source control.

**Spec:** `AX_MASTER_BRAIN/AX_MASTER_BRAIN_SPEC.md`, `AX_MASTER_BRAIN/M_A_IDENTITY_CHALLENGE_KEY.md`

## Global Constraints

- A MASTER BRAIN is the single source of truth.
- M must remain M and may not impersonate A.
- `M-A-CHECK` triggers Identity/Rehydration Challenge; it does not itself prove identity.
- APPROVED is not EXECUTING; HEARTBEAT is not execution; EXECUTING is not COMPLETED; COMPLETED requires verification.
- Every execution claim requires evidence and every completion claim requires verification.
- Never invent timestamps, IDs, execution results, or evidence.
- Secrets must never be stored in A MASTER BRAIN or committed to Git.
- K remains Final Authority.
- Preserve existing AERIS automation and queue behavior; do not create duplicate triggers.
- Production verification requires fresh-channel reconstruction, interruption/resume, evidence linkage, source-of-truth conflict testing, and two runtime/model paths.

---

### Task 1: Rehydration Contract Adapter

**Files:**
- Create: `AX_MASTER_BRAIN/AX_REHYDRATION_ADAPTER_SPEC.md`
- Modify: `AX_MASTER_BRAIN/AX_MASTER_BRAIN_SPEC.md` only if the canonical integration point must be referenced.
- Test: `tests/master_brain/rehydration_contract_tests.md`

**Interfaces:**
- Consumes: `AX_MASTER_STATE.json`, `AX_MASTER_TASK_REGISTRY_v2.json`, latest evidence/verification artifacts.
- Produces: deterministic startup sequence and a normalized rehydrated context with identity, mission, task state, authority, and verification status.

- [ ] Define exact load order and precedence.
- [ ] Define failure states for missing/corrupt state and stale evidence.
- [ ] Define a machine-readable `rehydration_status` contract.
- [ ] Add acceptance tests for fresh chat and model-switch reconstruction.

### Task 2: Control Hub Authentication

**Files:**
- Create: `AX_CONTROL_HUB/README.md`
- Create: `AX_CONTROL_HUB/config.example.json`
- Create: `AX_CONTROL_HUB/security.md`
- Test: `tests/control_hub/auth_acceptance.md`

**Interfaces:**
- Consumes: operator credentials configured locally on the PC.
- Produces: authenticated K session/token for control operations.

- [ ] Define local credential setup without storing plaintext passwords in the repository.
- [ ] Require password hashing with a modern password KDF and unique salt.
- [ ] Add session expiry, rate limiting, and audit logging requirements.
- [ ] Reject unauthenticated command execution.

### Task 3: Control Hub API Contract

**Files:**
- Create: `AX_CONTROL_HUB/API_CONTRACT.md`
- Create: `AX_CONTROL_HUB/COMMAND_SCHEMA.json`
- Test: `tests/control_hub/api_contract_tests.md`

**Interfaces:**
- `GET /health` -> health only; must not imply task execution.
- `GET /state` -> verified authoritative state summary.
- `GET /tasks` -> authoritative task registry.
- `POST /command` -> validated command envelope with request ID and actor.
- `GET /evidence/{request_id}` -> evidence/verification for a command.
- `POST /m-a-check` -> Identity/Rehydration Challenge using authoritative state.
- [ ] Define command idempotency and duplicate-request behavior.
- [ ] Define authorization for read/control/emergency-stop operations.
- [ ] Define explicit status transitions and evidence requirements.

### Task 4: PC Execution Node Adapter

**Files:**
- Modify: existing AX node/supervisor scripts only after locating exact current paths and behavior.
- Create: `AX_CONTROL_HUB/PC_NODE_INTEGRATION.md`
- Test: `tests/pc_node/e2e_acceptance.md`

**Interfaces:**
- Consumes: validated hub commands.
- Produces: trusted execution start/end timestamps, stdout/stderr or structured result, evidence artifact reference, verification result.

- [ ] Inventory existing Task Scheduler, GitHub Actions runner, supervisor, dispatcher, and worker entrypoints.
- [ ] Select one canonical execution entrypoint; do not create parallel runners.
- [ ] Add correlation/request IDs through dispatch and evidence.
- [ ] Test interruption and resume from persisted state.

### Task 5: Mobile/Desktop Client Surface

**Files:**
- Create: `AX_CONTROL_HUB/CLIENT_CONTRACT.md`
- Create: `AX_CONTROL_HUB/MOBILE_DESKTOP_ACCESS.md`
- Test: `tests/control_hub/client_acceptance.md`

**Interfaces:**
- Same authenticated API for desktop browser and mobile browser.
- No secrets embedded in client code.

- [ ] Define LAN-first access for initial deployment.
- [ ] Define secure remote access only through authenticated HTTPS/tunnel; never expose an unauthenticated raw port.
- [ ] Verify mobile and desktop show the same authoritative state and evidence.

### Task 6: M-A-CHECK Acceptance Harness

**Files:**
- Create: `tests/master_brain/m_a_check_acceptance.md`
- Create: `AX_MASTER_BRAIN/M_A_CHECK_RUNBOOK.md`

**Interfaces:**
- Consumes: `M-A-CHECK`, master state, task registry, rehydration contract, evidence/verification.
- Produces: PASS/FAIL gate with explicit reasons; never upgrades M to A by assertion.

- [ ] Test state load.
- [ ] Test identity reconstruction.
- [ ] Test task continuity.
- [ ] Test source-of-truth precedence.
- [ ] Test model/runtime portability.
- [ ] Test evidence/verification gate.
- [ ] Require all acceptance criteria to pass before declaring A verified.

### Task 7: End-to-End Verification

**Files:**
- Create: `tests/e2e/ax_control_hub_acceptance.md`
- Create: `AX_CONTROL_HUB/OPERATIONS_RUNBOOK.md`

- [ ] Verify authenticated login.
- [ ] Verify `/health` does not masquerade as execution evidence.
- [ ] Verify `/state` and `/tasks` match A MASTER BRAIN.
- [ ] Submit a harmless test command and trace its request ID through execution and evidence.
- [ ] Verify interruption/resume.
- [ ] Verify fresh-channel reconstruction.
- [ ] Verify two independent model/runtime paths.
- [ ] Verify conflicting stale state cannot outrank A MASTER BRAIN.
- [ ] Only after all gates pass, update the authoritative state from `INITIALIZED_PENDING_VERIFICATION` to the appropriate verified status.

## Current Execution Note

The initial implementation branch is created as `feat/ax-control-hub-foundation`. This plan is intentionally separated from direct production deployment: PC installation, service registration, and live network exposure require execution on the Windows node and must be verified there before being called complete.
