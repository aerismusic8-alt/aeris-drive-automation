# AX Autonomous Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a persistent AX Runtime/Supervisor that can continue operating after the ChatGPT session closes, with PC1 as the main execution node and evidence-backed state transitions.

**Architecture:** AX Runtime/Supervisor is an external process hosted on PC1. It owns the runtime loop, reads the canonical task registry, leases eligible jobs, dispatches them to the local Specialist/PC1 executor adapter, records append-only evidence, verifies results, applies deadline/recovery rules, and persists runtime state so restart resumes from the last verified point. ChatGPT/AX remains the executive interface and does not need to stay open for the runtime loop to continue.

**Tech Stack:** Node.js 20+ standard library only for the first runtime; JSON state files and JSONL evidence; local process execution for the PC1 worker adapter; no new GitHub Actions workflow and no external package dependency in the foundation runtime.

**Spec:** `AKATH_CORE/AX_RUNTIME_CONTRACT.md`, `AKATH_CORE/AX_EXECUTION_LOOP.md`, `AKATH_CORE/AX_TIME_GOVERNANCE.md`

## Global Constraints

- One canonical branch: `main`.
- PC1 is the Main execution node.
- No new GitHub Actions workflow is introduced for the runtime.
- No duplicate task registry; `AKATH_CORE/CANONICAL_TASK_REGISTRY.json` remains the canonical task source.
- Historical A MASTER BRAIN task records never become current work automatically.
- Every leased job has a deadline, checkpoint, completion criteria, evidence, and verification result.
- OVERDUE requires cause analysis and corrective action before retry.
- DONE requires result + evidence + verification.
- Runtime restart must recover from persisted state without requiring the ChatGPT session.
- Foundation E2E must be non-destructive and must not perform live financial or irreversible external actions.

---

### Task 1: Define runtime state and evidence contracts

**Files:**
- Create: `AKATH_CORE/runtime/AX_RUNTIME_STATE.schema.json`
- Create: `AKATH_CORE/runtime/AX_EVIDENCE.schema.json`
- Create: `AKATH_CORE/runtime/runtime-state.json`
- Create: `AKATH_CORE/runtime/evidence.jsonl`
- Test: `AKATH_CORE/runtime/runtime-contract.test.mjs`

**Interfaces:**
- Runtime state contains `schemaVersion`, `runtimeStatus`, `nodeId`, `lastHeartbeatAt`, `activeJob`, `lastVerifiedJob`, and `recovery`.
- Evidence record contains `jobId`, `event`, `timestamp`, `nodeId`, `result`, and `verification`.

- [ ] Write tests that reject runtime state without `runtimeStatus`, `nodeId`, or `lastHeartbeatAt`.
- [ ] Write tests that reject evidence without `jobId`, `event`, or `verification`.
- [ ] Run the test and verify it fails before implementation.
- [ ] Add the minimal schemas and initial empty state/evidence files.
- [ ] Run the test again and verify it passes.

### Task 2: Implement canonical job lifecycle

**Files:**
- Create: `AKATH_CORE/runtime/task-store.mjs`
- Test: `AKATH_CORE/runtime/task-store.test.mjs`

**Interfaces:**
- `loadRegistry(path)` returns the canonical registry object.
- `claimNextEligibleJob(registry, now)` returns the next eligible job or `null`.
- `transitionJob(job, nextStatus, metadata)` validates legal transitions and returns the updated job.
- `persistRegistry(path, registry)` writes the canonical registry atomically.

- [ ] Write tests for empty registry, claim, EXECUTING, COMPLETED, VERIFIED, DONE, OVERDUE, and recovery transitions.
- [ ] Run tests and verify the lifecycle tests fail for the missing functions.
- [ ] Implement only the transitions required by the runtime contract.
- [ ] Run tests and verify they pass.

### Task 3: Implement evidence and verification

**Files:**
- Create: `AKATH_CORE/runtime/evidence-store.mjs`
- Create: `AKATH_CORE/runtime/verifier.mjs`
- Test: `AKATH_CORE/runtime/evidence-store.test.mjs`
- Test: `AKATH_CORE/runtime/verifier.test.mjs`

**Interfaces:**
- `appendEvidence(path, record)` appends one JSONL evidence record.
- `readJobEvidence(path, jobId)` returns evidence for one job.
- `verifyJobResult(job, evidence)` returns `{ verified: boolean, reasons: string[] }`.

- [ ] Write failing tests for append/read and verification requiring result + evidence + verification.
- [ ] Run tests and verify RED.
- [ ] Implement append-only evidence and deterministic verification.
- [ ] Run tests and verify GREEN.

### Task 4: Implement PC1 dispatcher adapter

**Files:**
- Create: `AKATH_CORE/runtime/pc1-adapter.mjs`
- Create: `AKATH_CORE/runtime/dispatcher.mjs`
- Test: `AKATH_CORE/runtime/dispatcher.test.mjs`

**Interfaces:**
- `dispatchToPc1(job, adapter)` sends one non-destructive job to PC1.
- Adapter contract: `execute(job)` returns `{ ok, result, evidence }`.
- No hard-coded historical PC1 URL is allowed; the adapter reads `AX_PC1_EXECUTOR_COMMAND` from the environment and invokes that local command.

- [ ] Write a test using a fake adapter that proves the dispatcher passes only the leased job and returns its evidence.
- [ ] Run test and verify RED.
- [ ] Implement dispatcher and environment-backed adapter.
- [ ] Run test and verify GREEN.

### Task 5: Implement AX Runtime/Supervisor loop

**Files:**
- Create: `AKATH_CORE/runtime/ax-runtime.mjs`
- Create: `AKATH_CORE/runtime/recovery.mjs`
- Create: `AKATH_CORE/runtime/clock.mjs`
- Test: `AKATH_CORE/runtime/ax-runtime.test.mjs`

**Interfaces:**
- `runOnce(deps)` performs one complete cycle: load state → inspect eligible work → claim → dispatch → evidence → verify → persist.
- `startSupervisor(deps)` runs the cycle at a configurable interval and stops cleanly on SIGTERM/SIGINT.
- `recoverJob(job, reason, now)` records root cause and correction before requeueing or failing according to policy.

- [ ] Write a fake-adapter E2E test proving one job reaches DONE only after verification.
- [ ] Write a deadline test proving an overdue job is not silently marked DONE.
- [ ] Run tests and verify RED.
- [ ] Implement the smallest supervisor loop and bounded recovery behavior.
- [ ] Run tests and verify GREEN.

### Task 6: Add PC1 installation/start contract

**Files:**
- Create: `AKATH_CORE/runtime/PC1_INSTALL.md`
- Create: `AKATH_CORE/runtime/start-ax-runtime.ps1`
- Create: `AKATH_CORE/runtime/healthcheck.ps1`

**Interfaces:**
- `start-ax-runtime.ps1` starts the Node supervisor detached from the ChatGPT session.
- `healthcheck.ps1` reports process/runtime state and the last verified job.
- `AX_PC1_EXECUTOR_COMMAND` is the only PC1-specific executor binding required by the runtime.

- [ ] Document exact one-time PC1 setup and environment variable contract.
- [ ] Make the PowerShell launcher fail closed when Node or the executor command is missing.
- [ ] Validate launcher syntax and healthcheck logic locally where possible.

### Task 7: First autonomous E2E acceptance

**Files:**
- Create: `AKATH_CORE/runtime/fixtures/e2e-job.json`
- Create: `AKATH_CORE/runtime/fixtures/fake-pc1-executor.mjs`
- Test: `AKATH_CORE/runtime/e2e.test.mjs`

- [ ] Create a synthetic non-destructive job with a short deadline.
- [ ] Run the supervisor against the fake PC1 executor.
- [ ] Verify dispatch, execution, evidence append, verification, and DONE state.
- [ ] Restart the runtime and verify persisted state is readable without ChatGPT.
- [ ] Record the acceptance evidence and exact runtime timestamps.

### Task 8: PC1 real-runtime activation gate

**Files:**
- Modify: `AKATH_CORE/runtime/PC1_INSTALL.md`
- Modify: `AKATH_CORE/runtime/AX_RUNTIME_STATE.schema.json`

- [ ] Confirm PC1 has Node.js and the executor command available.
- [ ] Start the supervisor as a detached PC1 process.
- [ ] Close the ChatGPT session.
- [ ] From an independent PC1 terminal, run the healthcheck and confirm the supervisor is alive.
- [ ] Submit one non-destructive job and confirm evidence + verification are written while ChatGPT is closed.
- [ ] Mark the autonomous-runtime gate PASS only from fresh evidence.
