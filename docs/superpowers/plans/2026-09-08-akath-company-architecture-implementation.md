# AKATH Company Architecture Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enforce the K → AKATH → AX operating model across canonical state, task registry, runtime/rehydration, evidence, reporting, and repository documentation without creating competing sources of truth.

**Architecture:** Preserve the existing AKATH runtime and A MASTER BRAIN layout. Strengthen the boundaries between company identity, durable knowledge, canonical task state, execution state, and evidence; then make runtime/reporting consume those boundaries deterministically. Resolve existing documentation/manifest inconsistencies only where verified references show they are stale or contradictory.

**Tech Stack:** Python 3.12, PowerShell, JSON/Markdown, GitHub Actions, self-hosted Windows runner, existing repository-native acceptance tests.

**Spec:** `docs/superpowers/specs/2026-09-08-akath-company-architecture-design.md`

## Global Constraints

- `K` is Final Authority; `AKATH` is the company; `AX` is executive management/orchestration.
- `A MASTER BRAIN` stores durable knowledge and accumulated experience and is not the current-state authority.
- `AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json` is the only authoritative task catalog.
- `1 task_id = 1 task = 1 canonical task record`.
- Every task is exactly `SYSTEM` or `MISSION`; MISSION tasks declare `details.target`.
- Exactly one active `current_work` pointer may exist and it must reference an existing task.
- Task count equals `len(tasks)` at read time; never pad, invent, merge, or infer tasks.
- Execute requires evidence; completion requires verification; timestamps must never be fabricated.
- Rehydration never authorizes execution and model/chat memory is non-authoritative.
- Financial/live-money execution remains disabled unless separately authorized and verified by K-controlled policy.
- Existing verified functionality must remain passing.

---

### Task 1: Establish canonical architecture map and documentation consistency

**Files:**
- Modify: `README.md`
- Modify: `AKATH/STATUS.md`
- Modify: `AX_MASTER_BRAIN/AX_MASTER_BRAIN_SPEC.md`
- Modify: `AX_MASTER_BRAIN/AX_CONTINUOUS_REFLECTION_SPEC.md`
- Create: `docs/ARCHITECTURE.md`
- Test: `tests/AKATH_ARCHITECTURE_DOCUMENTATION.Tests.ps1`

**Interfaces:**
- Consumes: canonical identity and authority rules from `AX_MASTER_BRAIN/AX_MASTER_STATE.json` and the approved design spec.
- Produces: one human-readable architecture map that names the same authority boundaries used by runtime and tests.

- [ ] **Step 1: Write the failing documentation assertions**

Create `tests/AKATH_ARCHITECTURE_DOCUMENTATION.Tests.ps1` with assertions that `README.md`, `AKATH/STATUS.md`, `AX_MASTER_BRAIN/AX_MASTER_BRAIN_SPEC.md`, and the reflection spec do not declare AERIS as the current company/executive identity; assert the canonical chain contains `K`, `AKATH`, `AX`, and `A MASTER BRAIN` with distinct roles; assert `docs/ARCHITECTURE.md` exists and contains the five-layer names.

- [ ] **Step 2: Run the documentation test and verify failure**

Run:

```powershell
pwsh -NoProfile -File tests/AKATH_ARCHITECTURE_DOCUMENTATION.Tests.ps1
```

Expected: FAIL because `AX_CONTINUOUS_REFLECTION_SPEC.md` still contains obsolete A/M identity wording and the architecture map does not yet exist.

- [ ] **Step 3: Implement the documentation changes**

Normalize only active identity statements to the approved model. Keep legacy compatibility references explicitly labeled as legacy. Add `docs/ARCHITECTURE.md` with this canonical chain:

```text
K — Final Authority
        ↓
AKATH — Company
        ↓
AX — Executive Management & Orchestration
        ├── A MASTER BRAIN — Knowledge / Experience
        ├── Master Task Registry — Canonical Tasks
        ├── Runtime / Workforce — Execution
        └── Evidence / Verification — Proof
```

Document the five layers: Company, Brain, Management, Execution, Evidence, and explicitly state `KNOWLEDGE ≠ CURRENT STATE ≠ TASK ≠ EXECUTION ≠ EVIDENCE`.

- [ ] **Step 4: Run the documentation test and verify pass**

Run:

```powershell
pwsh -NoProfile -File tests/AKATH_ARCHITECTURE_DOCUMENTATION.Tests.ps1
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add README.md AKATH/STATUS.md AX_MASTER_BRAIN/AX_MASTER_BRAIN_SPEC.md AX_MASTER_BRAIN/AX_CONTINUOUS_REFLECTION_SPEC.md docs/ARCHITECTURE.md tests/AKATH_ARCHITECTURE_DOCUMENTATION.Tests.ps1
git commit -m "docs: establish AKATH canonical architecture map"
```

---

### Task 2: Enforce canonical task model and registry integrity

**Files:**
- Modify: `AKATH/runtime/ax_rehydration_adapter.py`
- Modify: `AKATH/tests/rehydration_adapter_tests.py`
- Modify: `tests/master_brain/ax_akath_identity_migration_tests.py`
- Create: `tests/master_brain/ax_task_registry_contract_tests.py`
- Verify: `AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json`

**Interfaces:**
- Consumes: task records from `AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json`.
- Produces: deterministic validation of required fields, task type/category, MISSION targets, unique task IDs, exact count, and single current-work reference.

- [ ] **Step 1: Write failing registry-contract tests**

The new Python test must load the registry and assert every task has `task_id`, `task_type`, `category`, `name`, `objective`, `priority`, `approval_status`, `execution_status`, `timestamp`, and `details`; assert task IDs are unique; assert types are only `SYSTEM`/`MISSION`; assert categories are in the controlled set; assert every MISSION has a mapping at `details.target`; assert exactly one active `current_work` exists and its task ID is in the task IDs; assert the reported count equals `len(tasks)`.

- [ ] **Step 2: Run the new test to establish the baseline**

Run:

```powershell
python -m pytest tests/master_brain/ax_task_registry_contract_tests.py -q
```

Expected: PASS if the current registry already satisfies the structural contract; if it exposes a gap, the test output becomes the exact implementation target rather than an inferred change.

- [ ] **Step 3: Tighten adapter validation only where the tests identify a gap**

Keep the existing interfaces `validate_task_registry`, `validate_current_work`, `get_task_by_id`, and `rehydrate`. Add only missing fail-closed checks. The adapter must continue returning `execution_authorized=false` during rehydration.

- [ ] **Step 4: Run the full rehydration acceptance test**

```powershell
python AKATH/tests/rehydration_adapter_tests.py
```

Expected: PASS with the canonical registry count, SYSTEM/MISSION counts, current-work task, authority boundaries, and missing-registry fail-closed behavior verified.

- [ ] **Step 5: Commit**

```bash
git add AKATH/runtime/ax_rehydration_adapter.py AKATH/tests/rehydration_adapter_tests.py tests/master_brain/ax_akath_identity_migration_tests.py tests/master_brain/ax_task_registry_contract_tests.py
git commit -m "test: enforce AKATH canonical task model"
```

---

### Task 3: Integrate rehydration and runtime source precedence

**Files:**
- Modify: `AKATH/runtime/ax_chatgpt_rehydration.py`
- Modify: `AKATH/runtime/ax_rehydration_adapter.py`
- Modify: `AKATH/runtime/akath_worker.ps1`
- Modify: `AKATH/RUNTIME_CONTRACT.md`
- Modify: `AKATH/tests/rehydration_adapter_tests.py`
- Create: `tests/AKATH_REHYDRATION_RUNTIME_INTEGRATION.Tests.ps1`

**Interfaces:**
- Consumes: `AX_MASTER_STATE.json`, `AX_MASTER_TASK_REGISTRY_v2.json`, rehydration contract, runtime state, and evidence.
- Produces: one failure-closed startup path where current canonical state outranks historical/model-local context and rehydration never grants execution authority.

- [ ] **Step 1: Write failing integration tests**

Add tests that invoke the adapter with valid canonical files and assert `rehydration_status=VERIFIED`, `current_work_task_id=AICS-LIVE-TRADING`, and `execution_authorized=false`. Add a negative fixture where the task registry is absent and assert `NOT_VERIFIED`. Add a negative fixture where a current-work task ID does not exist and assert `NOT_VERIFIED`.

- [ ] **Step 2: Run the integration tests**

```powershell
pwsh -NoProfile -File tests/AKATH_REHYDRATION_RUNTIME_INTEGRATION.Tests.ps1
```

Expected: FAIL only for behaviors not yet enforced by the current runtime path.

- [ ] **Step 3: Implement the minimum runtime integration**

The worker startup path must consume the same adapter result used by the ChatGPT-facing wrapper. It must refuse continuation when the result is `NOT_VERIFIED`. It must never interpret `execution_authorized=false` as a transient failure that can be bypassed.

- [ ] **Step 4: Run both adapter and runtime acceptance tests**

```powershell
python AKATH/tests/rehydration_adapter_tests.py
pwsh -NoProfile -File tests/AKATH_REHYDRATION_RUNTIME_INTEGRATION.Tests.ps1
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AKATH/runtime/ax_chatgpt_rehydration.py AKATH/runtime/ax_rehydration_adapter.py AKATH/runtime/akath_worker.ps1 AKATH/RUNTIME_CONTRACT.md AKATH/tests/rehydration_adapter_tests.py tests/AKATH_REHYDRATION_RUNTIME_INTEGRATION.Tests.ps1
git commit -m "feat: unify AKATH runtime rehydration boundaries"
```

---

### Task 4: Normalize evidence and verification linkage

**Files:**
- Modify: `AKATH/runtime/akath_worker.ps1`
- Modify: `AKATH/VERIFICATION/README.md`
- Modify: `.github/workflows/akath-24x7-acceptance-v2.yml`
- Create: `tests/AKATH_EVIDENCE_LINKAGE.Tests.ps1`

**Interfaces:**
- Consumes: runtime state, evidence JSON, verification state, canonical task ID.
- Produces: evidence records that identify the same canonical task ID and distinguish configured/approved/started/executed/verified/completed states.

- [ ] **Step 1: Write failing evidence-linkage assertions**

The test must reject a VERIFIED runtime record without `evidence_ref`, reject evidence whose task ID is absent from the canonical registry, and reject a completion claim without verification status. It must accept a VERIFIED record only when evidence and verification are linked.

- [ ] **Step 2: Run the test**

```powershell
pwsh -NoProfile -File tests/AKATH_EVIDENCE_LINKAGE.Tests.ps1
```

Expected: FAIL until the linkage checks are enforced.

- [ ] **Step 3: Implement the linkage checks**

Every execution evidence record must carry the canonical `task_id`; the runtime must remain `VERIFIED` only when `verification_status=VERIFIED` and `evidence_ref` resolves. Do not change the meaning of existing 24/7 proof files.

- [ ] **Step 4: Run the test plus existing acceptance**

```powershell
pwsh -NoProfile -File tests/AKATH_EVIDENCE_LINKAGE.Tests.ps1
python AKATH/tests/rehydration_adapter_tests.py
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AKATH/runtime/akath_worker.ps1 AKATH/VERIFICATION/README.md .github/workflows/akath-24x7-acceptance-v2.yml tests/AKATH_EVIDENCE_LINKAGE.Tests.ps1
 git commit -m "test: enforce canonical evidence linkage"
```

---

### Task 5: Make dashboard and reporting projections registry-only

**Files:**
- Modify: `AX_MASTER_BRAIN/TASK_REPORTING_PROTOCOL.md`
- Modify: existing AX dashboard/reporting scripts identified by repository references to task lists
- Create: `tests/AX_TASK_REPORTING_CANONICAL.Tests.ps1`

**Interfaces:**
- Consumes: only `AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json` for task count and task identity.
- Produces: reports that are projections and never create competing task records.

- [ ] **Step 1: Write failing reporting tests**

Assert that task count is computed from the registry task array, every reported task ID exists in the registry, and no dashboard/runtime list can be treated as a second master task catalog.

- [ ] **Step 2: Run the test**

```powershell
pwsh -NoProfile -File tests/AX_TASK_REPORTING_CANONICAL.Tests.ps1
```

Expected: FAIL for any report path that still sources master-task identity from a non-canonical list.

- [ ] **Step 3: Route reporting to the registry**

Use the registry path as the only master-task source. Keep runtime ledgers and dashboards as projections keyed by existing `task_id`. Do not change the registry task count merely to satisfy historical dashboard output.

- [ ] **Step 4: Run reporting and regression tests**

```powershell
pwsh -NoProfile -File tests/AX_TASK_REPORTING_CANONICAL.Tests.ps1
pwsh -NoProfile -File tests/AX_AGENT_EXECUTION_CONTRACT.Tests.ps1
pwsh -NoProfile -File tests/AX_AGENT_ROUTING_NO_DUPLICATE.Tests.ps1
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AX_MASTER_BRAIN/TASK_REPORTING_PROTOCOL.md tests/AX_TASK_REPORTING_CANONICAL.Tests.ps1
 git commit -m "feat: make AX reporting registry-only"
```

---

### Task 6: Reconcile File ID manifest and stale references

**Files:**
- Modify: `AX_MASTER_BRAIN/FILE_ID_MANIFEST.json`
- Create: `tests/AX_FILE_ID_MANIFEST_INTEGRITY.Tests.ps1`
- Verify: all paths listed by `FILE_ID_MANIFEST.json`

**Interfaces:**
- Consumes: manifest entries and current repository paths.
- Produces: a manifest containing only current canonical files with content hashes matching the files at verification time.

- [ ] **Step 1: Write the failing manifest integrity test**

The test must load the manifest, assert every listed path exists, assert file IDs are unique, and recompute SHA-256 for each file and compare it with `content_sha256`.

- [ ] **Step 2: Run the test**

```powershell
pwsh -NoProfile -File tests/AX_FILE_ID_MANIFEST_INTEGRITY.Tests.ps1
```

Expected: FAIL because the current manifest contains stale content hashes and a legacy path that is not present in the current repository.

- [ ] **Step 3: Rebuild the manifest from current canonical files**

Keep existing stable `file_id` values for files that still exist. Remove entries for paths that no longer exist only after verifying there are no active references. Add newly canonical architecture documents with newly generated UUID file IDs. Compute every `content_sha256` from the exact committed UTF-8 content.

- [ ] **Step 4: Run the manifest test**

```powershell
pwsh -NoProfile -File tests/AX_FILE_ID_MANIFEST_INTEGRITY.Tests.ps1
```

Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add AX_MASTER_BRAIN/FILE_ID_MANIFEST.json tests/AX_FILE_ID_MANIFEST_INTEGRITY.Tests.ps1
 git commit -m "fix: reconcile AX file ID manifest"
```

---

### Task 7: Final repository-wide acceptance and source-of-truth verification

**Files:**
- Modify: only files required by verified acceptance failures from Tasks 1-6
- Create: `tests/AKATH_ARCHITECTURE_ACCEPTANCE.ps1`

**Interfaces:**
- Consumes: canonical state, task registry, runtime contract, evidence, verification proof, documentation map, and manifest.
- Produces: one repeatable acceptance command proving the architecture is coherent without model-local memory.

- [ ] **Step 1: Write the acceptance script**

The script must execute these checks in order: canonical identity; master-brain boundary; task registry uniqueness/type/category/target/current-work; rehydration result; evidence linkage; File ID manifest; legacy identity audit; existing runtime/agent regression tests; and presence of persisted 24/7 proof. It must fail closed on any check.

- [ ] **Step 2: Run acceptance before fixes**

```powershell
pwsh -NoProfile -File tests/AKATH_ARCHITECTURE_ACCEPTANCE.ps1
```

Expected: FAIL only if an integration issue remains from the preceding tasks.

- [ ] **Step 3: Fix only acceptance-confirmed defects**

Apply the smallest change that restores the approved specification while preserving canonical task IDs, current-work identity, financial guardrails, and existing runtime behavior.

- [ ] **Step 4: Run the complete verification suite**

```powershell
python -m pytest tests/master_brain -q
python AKATH/tests/rehydration_adapter_tests.py
pwsh -NoProfile -File tests/AKATH_ARCHITECTURE_DOCUMENTATION.Tests.ps1
pwsh -NoProfile -File tests/AKATH_REHYDRATION_RUNTIME_INTEGRATION.Tests.ps1
pwsh -NoProfile -File tests/AKATH_EVIDENCE_LINKAGE.Tests.ps1
pwsh -NoProfile -File tests/AX_TASK_REPORTING_CANONICAL.Tests.ps1
pwsh -NoProfile -File tests/AX_FILE_ID_MANIFEST_INTEGRITY.Tests.ps1
pwsh -NoProfile -File tests/AKATH_ARCHITECTURE_ACCEPTANCE.ps1
```

Expected: PASS for every command.

- [ ] **Step 5: Verify GitHub Actions acceptance**

Confirm the repository's AKATH 24x7 workflow remains passing and the persisted proof still has `acceptance=PASS`; do not replace real scheduled evidence with a manual run.

- [ ] **Step 6: Commit final verified state**

```bash
git status --short
git add .
git commit -m "feat: complete AKATH company architecture enforcement"
```

- [ ] **Step 7: Final review**

Compare the final repository against `docs/superpowers/specs/2026-09-08-akath-company-architecture-design.md`. Verify that the operational chain can be reconstructed as:

```text
K → AKATH → AX → Current State → Canonical Task → Execution → Evidence → Verification → Next Step
```

Only after these checks pass may the architecture implementation be reported as complete.
