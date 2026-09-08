# AKATH / AX / A MASTER BRAIN Migration Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox syntax.

**Goal:** Migrate to AKATH as company, AX as executive management, and A MASTER BRAIN as durable knowledge and accumulated experience.

**Architecture:** Current organizational authority belongs to AKATH/AX under K. A MASTER BRAIN remains the knowledge/experience layer and cannot silently overwrite current canonical state.

**Tech Stack:** Python, JSON, Markdown, pytest, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-08-a-chatgpt-rehydration-system-design.md`

## Global Constraints
- K remains final authority.
- AKATH is the company.
- AX is executive management.
- A MASTER BRAIN is retained as durable knowledge/experience.
- ChatGPT Memory, chat history, dashboards, and model-local memory are non-authoritative.
- `REHYDRATE != EXECUTE`.
- No fabricated timestamps, evidence, verification, task IDs, or outcomes.
- Preserve brain knowledge and historical experience.
- M must not be promoted to AX.

### Task 1: Identity tests
**Files:** Create `tests/master_brain/ax_akath_identity_migration_tests.py`
- [ ] Test AX executive identity, AKATH company identity, A MASTER BRAIN brain role, K final authority, and M non-promotion.
- [ ] Run and confirm failures against old state.
- [ ] Commit red baseline.

### Task 2: Canonical state migration
**Files:** Modify `AX_MASTER_BRAIN/AX_MASTER_STATE.json`, `AX_MASTER_BRAIN/AX_MASTER_BRAIN_SPEC.md`, `AX_MASTER_BRAIN/AX_REHYDRATION_ADAPTER_SPEC.md`
- [ ] Replace obsolete A-as-executive/company semantics with AKATH/AX.
- [ ] Preserve knowledge, experience, lessons, historical decisions, evidence references, and recovery knowledge.
- [ ] Separate current state from historical brain knowledge.
- [ ] Run identity tests and commit.

### Task 3: Runtime rehydration
**Files:** Modify `AKATH/runtime/ax_rehydration_adapter.py`; create/update `tests/master_brain/chatgpt_rehydration_tests.py`
- [ ] Add failing tests for AX/AKATH context and state-over-history precedence.
- [ ] Update adapter identity and validation rules.
- [ ] Validate evidence/verification rather than assuming them from file presence.
- [ ] Keep `execution_authorized=false`.
- [ ] Run focused tests and commit.

### Task 4: Continuity alignment
**Files:** Modify `docs/AX_MISSION_MEMORY_PROTOCOL_V1.md`; review `AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json` and `AX_MASTER_BRAIN/TASK_REPORTING_PROTOCOL.md`
- [ ] Replace obsolete executive identity wording.
- [ ] Preserve stable task IDs and one canonical current_work.
- [ ] Preserve completed mission outcomes as A MASTER BRAIN experience.
- [ ] Run continuity tests and commit.

### Task 5: Legacy audit and cleanup
**Files:** All active files referencing obsolete A/M identity semantics.
- [ ] Search repository for obsolete identity contracts.
- [ ] Classify relevant artifacts KEEP/MIGRATE, REPLACE, LEGACY, or CONFLICT.
- [ ] Trace dependencies before deletion.
- [ ] Migrate required integrations.
- [ ] Delete only proven dead/contradictory artifacts.
- [ ] Never delete valuable brain knowledge/experience merely because naming is legacy.
- [ ] Run affected tests and commit cleanup separately.

### Task 6: ChatGPT rehydration integration
**Files:** Create `AX_MASTER_BRAIN/AX_CHATGPT_REHYDRATION_PROFILE.json`, `docs/AX_CHATGPT_REHYDRATION_PROTOCOL_V1.md`, `AKATH/runtime/ax_chatgpt_rehydration.py`; test `tests/master_brain/chatgpt_rehydration_tests.py`
- [ ] Write failing tests for profile/output contract.
- [ ] Implement AX/AKATH profile and loader.
- [ ] Add provenance and non-authority flags for chat/model memory.
- [ ] Load brain knowledge without authority inversion.
- [ ] Run focused and continuity tests and commit.

### Task 7: Final verification
- [ ] Run focused migration tests and relevant pytest suites.
- [ ] Run runtime rehydration and inspect output.
- [ ] Verify task continuity and `execution_authorized=false`.
- [ ] Search again for obsolete active identity contracts.
- [ ] Review diff for accidental loss/mutation of brain experience.
- [ ] Commit final verified state.
