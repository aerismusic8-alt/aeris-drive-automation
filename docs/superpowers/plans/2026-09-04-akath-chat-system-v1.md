# AKATH Chat System v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a portable, PC-first and mobile-first AKATH Chat System with independent storage/library, selective retrieval, evidence traceability, scheduled local backup, restore/migration, measurable performance, and centralized AX Job Control.

**Architecture:** The mobile browser/PWA is a client/control surface over a PC-hosted AKATH core. Runtime state and files remain outside the chat UI; A_MASTER_BRAIN remains authoritative. Track A is isolated from the separate A_MASTER_BRAIN connection/execution workstream. AX Job Control is part of Track A infrastructure and governs job lifecycle without becoming a second Brain.

**Tech Stack:** Existing AKATH/AERIS repository, Python runtime components, PowerShell on PC1/PC2, browser/PWA client, filesystem-backed storage, GitHub version control, automated tests.

**Spec:** `docs/AKATH_CHAT_SYSTEM_V1_DESIGN.md`

## Global Constraints

- A_MASTER_BRAIN remains the only canonical Brain.
- Chat is a client/control surface, not the source of truth.
- PC-first infrastructure; mobile-first operational use.
- Data must be searchable, inspectable, exportable, movable, and restorable.
- Local backup is mandatory and scheduled.
- Large binary files stay outside hot chat context and load on demand.
- Important execution follows Request → Execution → Evidence → Verification → Response.
- No completion claim without evidence and verification.
- Builder/provider lock-in must not prevent migration.
- Performance is an architecture requirement.
- Track A must not silently solve Track B.
- AX Job Control controls job lifecycle; it does not replace or modify A_MASTER_BRAIN authority.
- Existing unrelated jobs must not be automatically stopped, modified, retried, or adopted by Track A.
- New autonomous work must have an explicit Job Control authorization before execution.
- Emergency stop must fail closed and must not corrupt persistent state or evidence.

---

### Task 1: Repository baseline and architecture skeleton

**Files:**
- Create: `AKATH/chat/` focused runtime modules as required by the existing codebase
- Create: `tests/akath_chat/`
- Create: `docs/AKATH_CHAT_SYSTEM_V1_BASELINE.md`

**Interfaces:**
- Consumes: existing AKATH runtime contracts and design spec.
- Produces: stable module boundaries and test entry points for storage, library, retrieval, backup, API, mobile client, Job Control, and performance instrumentation.

- [ ] Map existing runtime/API boundaries before changing code.
- [ ] Write failing baseline tests proving A_MASTER_BRAIN is not replaced by chat state.
- [ ] Write failing Job Control tests for authorization, lifecycle ownership, and isolation from unrelated jobs.
- [ ] Run the baseline tests and record expected failures.
- [ ] Create the minimum directory/module skeleton.
- [ ] Run baseline tests again and verify only intended failures remain.
- [ ] Commit the skeleton and baseline documentation.

### Task 2: Portable filesystem-backed storage layer

**Files:**
- Create: `AKATH/chat/storage/`
- Create: `tests/akath_chat/test_storage.py`
- Create: `docs/AKATH_STORAGE_LAYOUT.md`

**Interfaces:**
- Produces: stable File ID, metadata, version, timestamps, source, related request/task, location, and integrity hash APIs.
- Provides: portable storage root configurable by environment/configuration.

- [ ] Write failing tests for create/read/update/version/hash behavior.
- [ ] Verify failures.
- [ ] Implement the minimal filesystem storage abstraction.
- [ ] Add atomic writes and corruption-safe metadata handling.
- [ ] Verify tests pass.
- [ ] Commit.

### Task 3: Library ingestion and selective retrieval

**Files:**
- Create: `AKATH/chat/library/`
- Create: `tests/akath_chat/test_library.py`
- Create: `docs/AKATH_LIBRARY_CONTRACT.md`

**Interfaces:**
- Consumes: storage layer.
- Produces: indexed metadata, search, locate, preview/read, and on-demand original-file retrieval.

- [ ] Write failing tests for representative code, Markdown/text, JSON, document, image, audio, and video assets.
- [ ] Verify failures.
- [ ] Implement metadata-first ingestion without loading large binaries into hot context.
- [ ] Implement search → locate → preview/read → verify flow.
- [ ] Verify tests pass and confirm video/image retrieval is lazy.
- [ ] Commit.

### Task 4: Chat API and fast-path request routing

**Files:**
- Create/modify: `AKATH/chat/api/`
- Create/modify: `AKATH/chat/router/`
- Create: `tests/akath_chat/test_api_router.py`

**Interfaces:**
- Produces: mobile-compatible API for chat, state, library search, task visibility, and control operations.
- Produces: Fast Path for normal chat and asynchronous path for long-running/critical work.
- Integrates with Job Control so only authorized jobs can transition into execution.

- [ ] Write failing API tests for normal chat, complex-job routing, and job-control authorization.
- [ ] Verify failures.
- [ ] Implement minimal request/response contract.
- [ ] Add request IDs and trace state without making chat the source of truth.
- [ ] Route execution lifecycle changes through Job Control.
- [ ] Verify tests pass.
- [ ] Commit.

### Task 5: AX Job Control Plane

**Files:**
- Create: `AKATH/chat/job_control/`
- Create: `tests/akath_chat/test_job_control.py`
- Create: `docs/AKATH_JOB_CONTROL_PLANE.md`

**Interfaces:**
- Produces: centralized Job Registry and lifecycle control for `START`, `PAUSE`, `RESUME`, `STOP`, `CANCEL`, `RETRY`, `PRIORITY`, `QUEUE`, and `EMERGENCY_STOP`.
- Produces: worker authorization tokens/leases or equivalent fail-closed execution grants.
- Produces: lifecycle evidence for every control transition.
- Maintains separation between job lifecycle authority and A_MASTER_BRAIN source-of-truth authority.

- [ ] Write failing tests for job creation, authorization, queueing, lifecycle transitions, ownership, and evidence.
- [ ] Write failing isolation tests proving unrelated legacy jobs are not automatically adopted or modified.
- [ ] Write failing tests for global pause and emergency stop behavior.
- [ ] Write failing tests proving workers cannot execute without an active authorization.
- [ ] Verify failures.
- [ ] Implement the minimal persistent Job Registry and state machine.
- [ ] Implement worker authorization and lease expiry/fail-closed behavior.
- [ ] Implement `START/PAUSE/RESUME/STOP/CANCEL/RETRY/PRIORITY/QUEUE`.
- [ ] Implement `EMERGENCY_STOP` with safe fail-closed semantics.
- [ ] Append evidence for every state transition and control action.
- [ ] Verify tests pass.
- [ ] Commit.

### Task 6: Evidence and response traceability

**Files:**
- Create/modify: `AKATH/chat/evidence/`
- Create: `tests/akath_chat/test_traceability.py`
- Create: `docs/AKATH_CHAT_TRACE_CONTRACT.md`

**Interfaces:**
- Consumes: API/router and existing AKATH evidence semantics.
- Produces: traceable Request → Execution → Evidence → Verification → Response records.
- Correlates Job Control transitions with request/task/evidence IDs.

- [ ] Write failing tests for missing evidence, unverified completion, successful verified response, and missing job-control authorization.
- [ ] Verify failures.
- [ ] Implement append-only trace records with stable request IDs.
- [ ] Enforce no-completion-without-verification.
- [ ] Record Job Control lifecycle and worker authorization evidence.
- [ ] Verify tests pass.
- [ ] Commit.

### Task 7: Scheduled local backup and restore

**Files:**
- Create: `AKATH/chat/backup/`
- Create: `tests/akath_chat/test_backup_restore.py`
- Create: `docs/AKATH_BACKUP_RECOVERY.md`
- Create/modify: PC scheduling scripts under `AKATH/runtime/` only where required.

**Interfaces:**
- Consumes: storage/library/evidence/Job Registry data.
- Produces: background backup snapshots, integrity verification, restore operation, configurable schedule/retention.

- [ ] Write failing tests for snapshot creation, hash verification, missing/corrupt file detection, and restore.
- [ ] Verify failures.
- [ ] Implement non-blocking scheduled backup orchestration.
- [ ] Implement integrity verification and restore into a clean location.
- [ ] Add periodic restore-test command.
- [ ] Verify tests pass.
- [ ] Commit.

### Task 8: Export and migration package

**Files:**
- Create: `AKATH/chat/migration/`
- Create: `tests/akath_chat/test_migration.py`
- Create: `docs/AKATH_MIGRATION.md`

**Interfaces:**
- Consumes: storage, metadata/index, evidence, Job Registry, and configuration contracts.
- Produces: self-contained portable export and deterministic restore without the original chat UI.

- [ ] Write failing export/restore tests.
- [ ] Verify failures.
- [ ] Implement manifest + files + metadata package format.
- [ ] Include Job Registry and control evidence in portable state.
- [ ] Implement clean-environment restore and index rebuild.
- [ ] Verify migration tests pass.
- [ ] Commit.

### Task 9: Mobile-first responsive client

**Files:**
- Create/modify: `AKATH/chat/client/`
- Create: `tests/akath_chat/test_mobile_client_contract.py`
- Create: `docs/AKATH_MOBILE_CLIENT.md`

**Interfaces:**
- Consumes: chat API and Job Control API.
- Produces: responsive mobile browser/PWA surface for chat, queue/task visibility, approval/control, evidence inspection, Library search/upload, and health.

- [ ] Write contract tests for the required mobile operations, including all safe Job Control lifecycle actions.
- [ ] Verify failures.
- [ ] Implement the smallest usable responsive client.
- [ ] Ensure the client has no independent Brain/state authority.
- [ ] Expose global pause and emergency stop with explicit K authorization and confirmation safeguards.
- [ ] Verify on representative mobile viewport and desktop browser.
- [ ] Commit.

### Task 10: Performance instrumentation and load gates

**Files:**
- Create: `AKATH/chat/performance/`
- Create: `tests/akath_chat/test_performance_contract.py`
- Create: `docs/AKATH_PERFORMANCE_BUDGET.md`

**Interfaces:**
- Produces: request, routing, retrieval, storage, AI, execution, verification, Job Control, and total latency measurements.
- Produces: load-test harness and Fast Path/async-path acceptance metrics.

- [ ] Write failing tests for required latency fields, non-blocking long jobs, and Job Control operations remaining responsive under load.
- [ ] Verify failures.
- [ ] Implement timing instrumentation.
- [ ] Add representative load scenarios for metadata, text/code, image, and large-file workflows.
- [ ] Measure queue/control latency separately from execution latency.
- [ ] Verify metrics and identify bottlenecks before optimization.
- [ ] Optimize only measured bottlenecks.
- [ ] Commit.

### Task 11: End-to-end acceptance and fresh-chat continuity

**Files:**
- Create: `tests/akath_chat/AKATH_CHAT_V1_E2E.md`
- Create/modify: existing E2E runner only as necessary.
- Create: `docs/AKATH_CHAT_SYSTEM_V1_STATUS.md`

**Interfaces:**
- Consumes: all Track A components.
- Produces: reproducible evidence for all v1 acceptance gates.

- [ ] Write the end-to-end acceptance matrix covering mobile access, library retrieval, backup, restore, migration, performance, long-running jobs, Job Control, traceability, and A_MASTER_BRAIN independence.
- [ ] Run the complete test suite.
- [ ] Run clean-environment restore/migration tests.
- [ ] Run representative mobile and performance tests.
- [ ] Verify START/PAUSE/RESUME/STOP/CANCEL/RETRY/PRIORITY/QUEUE and EMERGENCY_STOP behavior against controlled test jobs.
- [ ] Verify unrelated legacy jobs remain untouched unless explicitly adopted/authorized.
- [ ] Record evidence references and failures without masking them.
- [ ] Stop before declaring PASS; K performs final acceptance including fresh-chat continuity.
- [ ] Commit final status documentation.

## Definition of Done

AKATH Chat v1 is implementation-complete only when all automated acceptance gates pass and K independently performs the final acceptance test. A green build, heartbeat, or UI demo alone is insufficient evidence. Job Control is not considered complete until lifecycle authorization, isolation, emergency stop, and evidence-backed control transitions are verified.
