# Revenue-First Cost-Aware Execution Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make revenue generation the primary execution priority while keeping incremental infrastructure cost at ฿0 by default and preventing PC2 availability from blocking cloud-eligible work.

**Architecture:** Keep the existing canonical selector and AX Dispatcher as the control plane. Add cost-aware routing and evidence gates around the existing Cloudflare Control Runtime → Queue → AERIS Runtime path, while retaining PC2 as a specialized/local worker and GitHub-hosted runners only as bounded CI/automation fallback. Do not add a recurring paid VM until measured usage and a revenue/ROI case justify it.

**Tech Stack:** PowerShell, GitHub Actions, Cloudflare Workers/Queues, existing AERIS Execution Runtime, JSON task registry/evidence files.

**Spec:** `docs/superpowers/specs/2026-09-02-revenue-first-cost-aware-execution.md`

## Global Constraints

- Default incremental infrastructure spend: ฿0 until revenue or measured ROI justifies spend.
- Canonical dependency-safe task selection is mandatory.
- Queue acceptance/heartbeat/proof-artifact generation does not equal business execution.
- COMPLETED requires verified business-result evidence and task-state write-back.
- Financial/live-money execution remains disabled until existing gates are satisfied.
- PC2 is not a universal prerequisite for cloud-eligible work.
- Never claim completion without evidence.

---

### Task 1: Map Existing Execution Paths and Cost Signals

**Files:**
- Inspect: `AX_TASK_REGISTRY.json`
- Inspect: `AX_ACTION_DISPATCHER.ps1`
- Inspect: `AX_TASK_SELECTOR.ps1`
- Inspect: `.github/workflows/ax-pc2-runtime-recovery.yml`
- Inspect: Cloudflare runtime source under `cloudflare/`

**Interfaces:**
- Consumes: current task registry, dispatcher, workflow, runtime configuration.
- Produces: verified map of cloud path vs PC2 path and measurable cost signals.

- [ ] Step 1: Identify every current task-selection and dispatch entry point.
- [ ] Step 2: Identify which paths can execute without PC2.
- [ ] Step 3: Identify where execution evidence and task-state write-back currently occur.
- [ ] Step 4: Identify available Cloudflare/GitHub usage signals.
- [ ] Step 5: Record gaps without modifying execution behavior.

### Task 2: Add Cost-Aware Routing Policy

**Files:**
- Modify: `AX_ACTION_DISPATCHER.ps1`
- Create/modify: routing policy file only if an existing configuration location is insufficient.
- Test: routing regression tests.

**Interfaces:**
- Consumes: canonical selected task and domain/dependency state.
- Produces: deterministic route classification such as `CLOUD_PREFERRED`, `PC2_REQUIRED`, or `WAITING_K` with no hidden paid-resource activation.

- [ ] Step 1: Write failing tests for cloud-preferred routing and PC2-required routing.
- [ ] Step 2: Implement the smallest routing policy using existing infrastructure.
- [ ] Step 3: Add a hard guard preventing automatic paid infrastructure provisioning.
- [ ] Step 4: Run routing regression tests.
- [ ] Step 5: Commit the routing policy change.

### Task 3: Enforce Real Business Execution Evidence

**Files:**
- Inspect/modify: existing AERIS execution bridge/runtime integration.
- Test: execution-evidence regression tests.

**Interfaces:**
- Consumes: dispatched task event.
- Produces: evidence containing task ID, execution result, verification result, and trusted timestamp.

- [ ] Step 1: Write a failing test proving that a self-generated proof artifact cannot mark a business task COMPLETED.
- [ ] Step 2: Trace the actual `/execute` result contract.
- [ ] Step 3: Implement the minimum evidence gate needed to distinguish business execution from proof-only execution.
- [ ] Step 4: Run tests and verify negative cases.
- [ ] Step 5: Commit only after evidence is independently verifiable.

### Task 4: Prevent PC2 from Blocking Cloud-Eligible Revenue Work

**Files:**
- Modify: supervisor/dispatch path only where required.
- Test: routing/availability regression tests.

**Interfaces:**
- Consumes: canonical task route and worker capability state.
- Produces: cloud dispatch for cloud-eligible tasks even when PC2 is unavailable; explicit wait for PC2-required tasks.

- [ ] Step 1: Identify whether `AX_SUPERVISOR_TRIGGER.ps1` is an active production selector.
- [ ] Step 2: Replace any remaining raw-priority selection with the canonical selector.
- [ ] Step 3: Add a regression test for PC2-offline/cloud-eligible behavior.
- [ ] Step 4: Verify the supervisor does not falsely report business completion.
- [ ] Step 5: Commit the change.

### Task 5: Verify Cost and Revenue Gate

**Files:**
- Create/modify: cost/evidence ledger only if the repository has no existing authoritative location.
- Test: cost guard tests.

**Interfaces:**
- Consumes: actual usage evidence and execution evidence.
- Produces: bounded incremental-cost record and revenue-first decision evidence.

- [ ] Step 1: Define the minimum usage metrics to capture.
- [ ] Step 2: Verify current vendor pricing references.
- [ ] Step 3: Record actual usage where accessible; label unavailable values as unknown rather than estimate-as-fact.
- [ ] Step 4: Verify no recurring paid resource was activated by the change.
- [ ] Step 5: Commit the cost/revenue gate only after verification.

### Task 6: End-to-End Revenue Path Verification

**Files:**
- Inspect: all changed files and relevant workflows.
- Test: GitHub Actions and runtime evidence.

**Interfaces:**
- Consumes: completed routing, execution evidence, and cost guard.
- Produces: verified end-to-end result or an explicit blocker with evidence.

- [ ] Step 1: Run selector and dispatcher regression tests.
- [ ] Step 2: Run the cloud execution path for a safe, non-financial business task.
- [ ] Step 3: Verify business-result evidence rather than proof-only evidence.
- [ ] Step 4: Verify task-state write-back and trusted timestamps.
- [ ] Step 5: Verify incremental cost remains within the approved policy.
- [ ] Step 6: Only then report the path as VERIFIED; otherwise report the exact blocking gate.
