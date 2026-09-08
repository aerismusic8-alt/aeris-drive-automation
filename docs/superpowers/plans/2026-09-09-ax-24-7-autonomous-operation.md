# AX 24/7 Autonomous Operation Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make AX operate continuously from canonical state with autonomous recovery and verified execution while prioritizing revenue work.

**Architecture:** Bind the runtime to the canonical master task registry, align executable-agent routing with verified capabilities, and verify runtime identity before enabling continuous dispatch. Preserve K as Final Authority for financial and other high-risk actions while allowing routine execution, recovery, persistence, and verification to continue without chat-triggered steps.

**Tech Stack:** GitHub Actions, PowerShell self-hosted runners, existing AX runtime scripts, JSON state/registry, repository tests.

**Spec:** AX_MASTER_BRAIN/AX_MASTER_BRAIN_SPEC.md and the approved AX 24/7 authorization in conversation.

## Global Constraints

- K remains Final Authority.
- Chat is transport/context, not authoritative operational state.
- Canonical current operational truth comes from canonical state, task registry, evidence, and verification.
- APPROVED != EXECUTING; heartbeat != task execution.
- Every execution claim requires evidence; every completion claim requires verification.
- Exactly one canonical current_work may be active.
- XM Live Trade is not an execution target and must not be re-enabled by this work.
- Live financial execution, financial transfers, material new capital, and other high-risk/irreversible external actions remain K-gated.
- No new task is created solely to pad the registry.

---

### Task 1: Canonical Registry Binding

**Files:**
- Inspect: `AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json`
- Inspect/modify: `AX_TASK_REGISTRY.json` and the runtime consumers identified by search
- Test: existing registry/runtime tests identified during implementation

**Interfaces:**
- Consumes: canonical master task registry
- Produces: one runtime task source matching the canonical registry

- [ ] Locate every runtime read of the obsolete task registry.
- [ ] Write a failing regression test proving runtime task loading rejects or detects registry drift.
- [ ] Verify the test fails for the current drift.
- [ ] Implement the smallest binding/alignment change.
- [ ] Run targeted tests and verify green.
- [ ] Verify exact task count and current_work reference against the master registry.

### Task 2: Agent Routing Alignment

**Files:**
- Inspect/modify: `AX_AGENT_ROUTING_BRIDGE.ps1`
- Inspect: agent capability registry and related routing tests
- Test: existing agent routing tests

**Interfaces:**
- Consumes: verified executable agent capability registry
- Produces: routing candidates that exist and are executable in the current environment

- [ ] Identify the authoritative capability registry and current executable agents.
- [ ] Write a failing test for stale `COPILOT` routing.
- [ ] Verify the test fails.
- [ ] Replace stale fallback candidates with verified executors only.
- [ ] Run routing tests and verify green.

### Task 3: Runtime Identity Verification

**Files:**
- Inspect/modify: executive loop, dispatcher, and control-runtime configuration/workflows identified by search
- Test: runtime endpoint identity/health acceptance tests

**Interfaces:**
- Consumes: runtime URLs and health contracts
- Produces: a verified canonical runtime identity used consistently by dispatch paths

- [ ] Enumerate all AX runtime URLs.
- [ ] Write a failing test/acceptance check that detects inconsistent runtime identity.
- [ ] Verify the check fails or exposes the current ambiguity.
- [ ] Implement the minimum configuration/validation needed to prevent silent cross-runtime drift.
- [ ] Run acceptance checks and verify green.

### Task 4: 24/7 Recovery and Autonomous Continuation

**Files:**
- Inspect/modify: existing AX Executive Loop and recovery workflow
- Test: runtime loop/recovery tests

**Interfaces:**
- Consumes: canonical task state, execution evidence, runner/runtime health
- Produces: autonomous observe/dispatch/persist/verify/recovery cycle

- [ ] Write a failing test for continuation after an operational failure without chat input.
- [ ] Verify the test fails.
- [ ] Implement bounded retry/recovery using existing runtime mechanisms.
- [ ] Preserve evidence and state transitions across retries.
- [ ] Run targeted runtime tests and verify green.

### Task 5: Revenue-First Scheduling and XM Retirement Guard

**Files:**
- Inspect/modify: canonical state/registry priority fields and XM-related routing/configuration identified by search
- Test: priority/retirement validation tests

**Interfaces:**
- Consumes: K-approved business priority and canonical registry
- Produces: revenue-first scheduling with XM excluded from active execution paths

- [ ] Write failing tests proving revenue priority outranks speculative XM work and XM cannot be selected as an active execution target.
- [ ] Verify failure against the current state.
- [ ] Implement priority/retirement changes without deleting audit evidence.
- [ ] Verify registry count remains exact and no task padding occurs.

### Task 6: End-to-End 24/7 Verification

**Files:**
- Inspect: all changed workflows/scripts/tests

**Interfaces:**
- Consumes: all previous task outputs
- Produces: evidence that AX can recover, continue, persist, and verify without chat-triggered task-by-task input

- [ ] Run repository test suite relevant to changed components.
- [ ] Run GitHub Actions acceptance workflows available for the runtime.
- [ ] Verify PC1 and PC2 runner health where available.
- [ ] Verify evidence/write-back and current_work continuity.
- [ ] Confirm no live-money execution path was enabled.
- [ ] Record verification evidence and final state.
