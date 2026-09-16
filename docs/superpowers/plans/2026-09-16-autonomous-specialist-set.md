# Autonomous Specialist Set Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make PC1 Specialist a capability-routed execution layer that can continue planned AKATH work without waiting for K to issue each next task.

**Architecture:** Add a small canonical specialist registry and capability router. The existing `PC1_MAIN_SPECIALIST` remains the safe default executor; additional deterministic specialists handle self-check and recovery-oriented jobs. Runtime dispatch selects a specialist from job capability, while evidence keeps the selected specialist identity for verification.

**Tech Stack:** Node.js ES modules, JSON registry, existing AKATH runtime tests.

**Spec:** `AKATH_CORE/AX_EXECUTION_LOOP.md`

## Global Constraints

- One canonical branch: `main`.
- No duplicate workflow or task registries.
- PC1 remains the main execution node.
- Every task has a deadline and completion criteria.
- DONE requires result + persisted evidence + verification.
- No irreversible or financial action in the foundation/autonomous test.

---

### Task 1: Specialist routing contract

**Files:**
- Create: `AKATH_CORE/runtime/specialist-registry.test.mjs`
- Create: `AKATH_CORE/runtime/specialist-registry.mjs`

- [ ] Write failing tests for capability lookup, safe default, and unknown capability rejection.
- [ ] Run the test and confirm it fails because the registry does not exist.
- [ ] Implement the minimal registry and lookup API.
- [ ] Run the test and confirm it passes.

### Task 2: Capability-aware PC1 executor

**Files:**
- Modify: `AKATH_CORE/runtime/pc1-specialist.mjs`
- Modify: `AKATH_CORE/runtime/pc1-specialist.test.mjs`

- [ ] Add failing tests for `execution`, `self_check`, and `recovery` capabilities.
- [ ] Run tests and confirm failure.
- [ ] Implement deterministic specialists with explicit executor identity and evidence.
- [ ] Run the specialist tests and confirm all pass.

### Task 3: Autonomous continuation task

**Files:**
- Modify: `AKATH_CORE/CANONICAL_TASK_REGISTRY.json`
- Modify: `AKATH_CORE/runtime/runtime-state.json`

- [ ] Add exactly one non-destructive autonomous continuation task with deadline and capability.
- [ ] Ensure it can be claimed only once and produces evidence.
- [ ] Verify registry/state remain canonical and do not create a second task registry.

### Task 4: Runtime verification

**Files:**
- Modify: `AKATH_CORE/runtime/dispatcher.mjs`
- Modify: `AKATH_CORE/runtime/dispatcher.test.mjs`
- Modify: `AKATH_CORE/AX_EXECUTION_LOOP.md`

- [ ] Route the selected capability through the existing PC1 dispatcher.
- [ ] Test routing without shell command mangling.
- [ ] Update the loop document from foundation-only wording to the verified autonomous specialist path.
- [ ] Run the full runtime test set available on PC1.

### Task 5: Acceptance evidence

**Files:**
- `AKATH_CORE/runtime/evidence.jsonl`
- `AKATH_CORE/runtime/runtime-state.json`
- `AKATH_CORE/CANONICAL_TASK_REGISTRY.json`

- [ ] Confirm autonomous task reaches DONE.
- [ ] Confirm evidence contains selected specialist and verification=true.
- [ ] Confirm runtime remains ONLINE after completion.
- [ ] Record root cause and corrective action if any deadline is missed.
