# AKATH Autonomous Runtime Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Convert the existing AERIS/AX execution substrate into AKATH's GPT-independent autonomous runtime and prove a repeatable 24/7 execution loop.

**Architecture:** Preserve A MASTER BRAIN as authoritative state, AX as executive orchestrator, and the existing Control Hub contract. Add an AKATH runtime layer around the existing queue/state/runner mechanisms with an explicit wake-up, lease/lock, heartbeat, recovery, and evidence contract so ChatGPT is a control interface rather than a runtime dependency.

**Tech Stack:** GitHub repository, GitHub Actions, existing self-hosted runner infrastructure, existing AX Control Hub/API contract, repository-native scripting already used by the project, persistent state/evidence files or existing state stores.

**Spec:** `docs/superpowers/specs/2026-09-03-akath-autonomous-company-design.md`

## Global Constraints

- `AKATH` is the company identity; corporate description is `Autonomous AI Company`.
- `A MASTER BRAIN` remains the authoritative source of truth.
- `AX` remains the executive orchestration layer.
- ChatGPT must not be required for ordinary autonomous job-to-job continuation.
- Preserve existing AERIS/AX components unless verification shows a necessary change.
- Every completion claim requires execution evidence and verification.
- K remains Final Authority for high-risk actions, financial execution, permission expansion, and major architecture changes.
- No secrets may be committed to the repository.
- Prefer self-hosted runners for continuous execution; do not assume private GitHub-hosted minutes are unlimited.

---

### Task 1: Establish AKATH runtime contract

**Files:**
- Create: `AKATH/README.md`
- Create: `AKATH/RUNTIME_CONTRACT.md`
- Create: `AKATH/config.example.json`
- Test: `AKATH/tests/contract_validation.md`

**Interfaces:**
- Consumes: existing AX Control Hub semantics in `AX_CONTROL_HUB/API_CONTRACT.md`.
- Produces: stable AKATH runtime states `READY`, `RUNNING`, `WAITING`, `RECOVERING`, `BLOCKED`, `FAILED`, `VERIFIED` and required evidence fields `run_id`, `job_id`, `started_at`, `finished_at`, `verification_status`, `heartbeat_at`.

- [ ] **Step 1: Write the runtime contract test cases**

```text
PASS cases:
READY -> RUNNING -> VERIFIED
RUNNING -> WAITING
RUNNING -> RECOVERING -> RUNNING
RUNNING -> FAILED

FAIL cases:
health=OK without execution evidence must not become VERIFIED
queued job must not become EXECUTING without an execution event
completed job must not become VERIFIED without verification evidence
```

- [ ] **Step 2: Run the contract review test**

Run: `git diff --check` and manually compare each state transition against `AX_CONTROL_HUB/API_CONTRACT.md`.
Expected: no whitespace errors; no state transition contradicts the existing contract.

- [ ] **Step 3: Write the minimum runtime contract and example configuration**

The contract must define:

```text
runtime_id
state
run_id
job_id
heartbeat_at
lease_owner
attempt
verification_status
evidence_ref
error_class
next_action
```

The example configuration must contain placeholders only and no credentials.

- [ ] **Step 4: Run documentation validation**

Run: `git diff --check`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AKATH/README.md AKATH/RUNTIME_CONTRACT.md AKATH/config.example.json AKATH/tests/contract_validation.md
git commit -m "feat: define AKATH runtime contract"
```

### Task 2: Implement autonomous runtime worker entrypoint

**Files:**
- Create: `AKATH/runtime/akath_worker.ps1`
- Create: `AKATH/runtime/akath_worker_config.example.json`
- Create: `AKATH/tests/worker_contract.md`

**Interfaces:**
- Consumes: AKATH runtime contract and existing repository command/queue mechanisms.
- Produces: one idempotent worker cycle with explicit `acquire -> execute -> verify -> persist -> release` behavior.

- [ ] **Step 1: Define worker test vectors**

```text
No job available -> persist WAITING and exit successfully
Valid job -> RUNNING -> execute -> verify -> persist VERIFIED
Execution error -> persist RECOVERING or FAILED with error_class
Duplicate run/lease -> do not execute concurrently
Verification failure -> never mark VERIFIED
```

- [ ] **Step 2: Run the test-vector review**

Run: `git diff --check`
Expected: PASS.

- [ ] **Step 3: Implement worker entrypoint**

The worker must:

```powershell
param([string]$ConfigPath = "AKATH/runtime/akath_worker_config.json")

# Load config, establish a run id, acquire a persisted lease,
# obtain one authoritative job, execute the existing command path,
# verify evidence, persist the final state, release the lease,
# and exit with a machine-readable status code.
```

It must not call ChatGPT, depend on conversation state, or embed secrets.

- [ ] **Step 4: Run static PowerShell validation**

Run: `pwsh -NoProfile -Command "Get-Command pwsh; [scriptblock]::Create((Get-Content 'AKATH/runtime/akath_worker.ps1' -Raw)) | Out-Null"`
Expected: script parses successfully.

- [ ] **Step 5: Commit**

```bash
git add AKATH/runtime/akath_worker.ps1 AKATH/runtime/akath_worker_config.example.json AKATH/tests/worker_contract.md
git commit -m "feat: add AKATH autonomous worker"
```

### Task 3: Add watchdog/heartbeat and recovery

**Files:**
- Create: `AKATH/runtime/akath_watchdog.ps1`
- Create: `AKATH/tests/watchdog_contract.md`
- Modify: `AKATH/RUNTIME_CONTRACT.md`

**Interfaces:**
- Consumes: worker heartbeat and persisted run state.
- Produces: stale-run detection, recovery transition, and evidence record without falsely claiming execution completion.

- [ ] **Step 1: Define heartbeat failure vectors**

```text
fresh heartbeat -> no recovery
stale heartbeat + RUNNING -> RECOVERING
stale heartbeat + VERIFIED -> no rollback
missing state -> BLOCKED with SOURCE_STATE_UNAVAILABLE
```

- [ ] **Step 2: Write watchdog behavior**

```text
read authoritative state
compare heartbeat_at to threshold
if stale and active:
  persist RECOVERING
  create recovery evidence
never convert an unverified run to VERIFIED
```

- [ ] **Step 3: Parse-check watchdog**

Run: `pwsh -NoProfile -Command "[scriptblock]::Create((Get-Content 'AKATH/runtime/akath_watchdog.ps1' -Raw)) | Out-Null"`
Expected: PASS.

- [ ] **Step 4: Commit**

```bash
git add AKATH/runtime/akath_watchdog.ps1 AKATH/tests/watchdog_contract.md AKATH/RUNTIME_CONTRACT.md
git commit -m "feat: add AKATH heartbeat recovery"
```

### Task 4: Add GitHub Actions wake-up workflow

**Files:**
- Create: `.github/workflows/akath-runtime.yml`
- Create: `AKATH/tests/akath-runtime-workflow.md`

**Interfaces:**
- Consumes: GitHub schedule/manual dispatch and self-hosted runner labels available in the repository.
- Produces: autonomous worker invocation without ChatGPT.

- [ ] **Step 1: Define workflow triggers**

```yaml
on:
  workflow_dispatch:
  schedule:
    - cron: "*/5 * * * *"
```

The schedule is a wake-up mechanism, not the sole continuity mechanism.

- [ ] **Step 2: Route execution to self-hosted runner**

Use the repository's existing self-hosted runner label only after verifying it from actual repository configuration. Do not invent labels.

- [ ] **Step 3: Invoke worker and publish evidence**

The workflow must run the worker, preserve its exit code, and expose a concise execution result in the workflow log.

- [ ] **Step 4: Validate workflow syntax and repository assumptions**

Run repository-native CI validation if present. Otherwise use a YAML parser available in the runner environment and inspect the workflow manually for trigger, permissions, runner, and secret usage.

Expected: no secret literals; no GitHub-hosted runner selected for continuous operation; schedule is at most once per 5 minutes.

- [ ] **Step 5: Commit**

```bash
git add .github/workflows/akath-runtime.yml AKATH/tests/akath-runtime-workflow.md
git commit -m "feat: add AKATH autonomous wake-up workflow"
```

### Task 5: Wire the first end-to-end autonomous proof job

**Files:**
- Create: `AKATH/probes/akath_e2e_probe.ps1`
- Create: `AKATH/tests/e2e-proof.md`
- Modify: `AKATH/README.md`

**Interfaces:**
- Consumes: runtime worker, watchdog, GitHub Actions, existing evidence/verification path.
- Produces: a harmless repeatable probe job proving continuation without a GPT message.

- [ ] **Step 1: Define a non-financial probe**

The probe must update only AKATH runtime test state/evidence and must not spend money, publish publicly, modify production secrets, or perform financial execution.

- [ ] **Step 2: Implement probe**

The probe must emit:

```text
probe_run_id
job_id
started_at
completed_at
verification_status=VERIFIED
next_job_ready=true
```

only after the local verification checks pass.

- [ ] **Step 3: Execute probe manually once**

Run the probe through `workflow_dispatch` and verify the run reaches `VERIFIED`.

- [ ] **Step 4: Verify autonomous continuation**

Allow the scheduled wake-up to create at least three successive verified cycles without a ChatGPT message being used between cycles. Record workflow run IDs, timestamps, job IDs, and evidence references in the test log.

- [ ] **Step 5: Commit evidence summary**

```bash
git add AKATH/probes/akath_e2e_probe.ps1 AKATH/tests/e2e-proof.md AKATH/README.md
git commit -m "test: add AKATH autonomous e2e proof"
```

### Task 6: Review against 24/7 acceptance criteria

**Files:**
- Modify: `AKATH/README.md`
- Modify: `AKATH/tests/e2e-proof.md`
- Create: `AKATH/STATUS.md`

**Interfaces:**
- Consumes: evidence from Tasks 1-5.
- Produces: explicit `VERIFIED`, `PARTIALLY VERIFIED`, or `NOT VERIFIED` status; never infer 24/7 capability from a single successful workflow.

- [ ] **Step 1: Compare evidence to each acceptance criterion**

Check trigger independence, authoritative job selection, runner execution, verification, automatic continuation, recovery, heartbeat persistence, and ChatGPT control-only behavior.

- [ ] **Step 2: Mark each criterion with evidence**

Use a table with columns `criterion`, `evidence`, `status`, `timestamp`.

- [ ] **Step 3: Set overall status**

Set `VERIFIED` only when every required criterion has direct evidence. Otherwise record exactly what remains unverified.

- [ ] **Step 4: Commit status**

```bash
git add AKATH/README.md AKATH/tests/e2e-proof.md AKATH/STATUS.md
git commit -m "docs: record AKATH autonomous runtime verification"
```
