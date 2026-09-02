# Multi-Agent Dispatch Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Enable evidence-gated parallel routing to Gemini and Microsoft Copilot without interrupting existing work or weakening A/K authority.

**Architecture:** A remains the control plane. A canonical selector evaluates dependencies and capabilities, then dispatches eligible tasks through agent-specific adapters using one common execution/evidence contract. Unknown or unverified agents are never treated as executable capacity.

**Tech Stack:** PowerShell, GitHub Actions, Google Apps Script, Cloudflare Workers/Queues, JSON task registry.

**Spec:** `docs/superpowers/specs/2026-09-02-multi-agent-dispatch-design.md`

## Global Constraints
- K is final authority.
- A MASTER BRAIN is the authoritative orchestrator/source of truth.
- M is support/continuity only and is not A.
- APPROVED != EXECUTING; EXECUTING != COMPLETED.
- Completion requires real execution evidence and verification.
- Financial/live-money execution remains disabled.
- Existing running/queued work must not be interrupted by the new routing layer.
- No hidden paid-resource activation.

### Task 1: Discover and formalize agent capabilities
**Files:**
- Read: existing Agent Registry/delegation files and Gemini/Copilot prompt/connector configuration.
- Create: `AX_AGENT_CAPABILITY_REGISTRY.json`
- Test: `tests/AX_AGENT_CAPABILITY_REGISTRY.Tests.ps1`

- [ ] Write failing tests for Gemini/Copilot capability states and unknown/unverified behavior.
- [ ] Inspect existing integration evidence and encode only proven capabilities.
- [ ] Implement registry with `AVAILABLE_FOR_REVIEW`, `READY`, `UNAVAILABLE` states.
- [ ] Run regression tests and commit.

### Task 2: Add canonical multi-agent task routing
**Files:**
- Modify: `AX_TASK_SELECTOR.ps1`
- Create: `AX_MULTI_AGENT_ROUTER.ps1`
- Test: `tests/AX_MULTI_AGENT_ROUTER.Tests.ps1`

- [ ] Write failing tests for capability match, dependency rejection, duplicate execution rejection, and unavailable-agent fallback.
- [ ] Implement routing classes `CLOUD_PREFERRED`, `GEMINI_PREFERRED`, `COPILOT_PREFERRED`, `PC2_REQUIRED`, `WAITING_K`.
- [ ] Keep dependency enforcement centralized and reuse the canonical selector.
- [ ] Run tests and commit.

### Task 3: Implement evidence-gated agent adapter contract
**Files:**
- Create: `AX_AGENT_EXECUTION_CONTRACT.md`
- Create/modify: Gemini and Copilot adapter files identified in Task 1.
- Test: `tests/AX_AGENT_EXECUTION_CONTRACT.Tests.ps1`

- [ ] Write failing tests requiring ACCEPTED → EXECUTING → RESULT → EVIDENCE → VERIFIED → WRITE_BACK.
- [ ] Implement adapters only for actually reachable integrations.
- [ ] Reject synthetic proof artifacts as business completion.
- [ ] Run tests and commit.

### Task 4: Integrate supervisor/dispatcher without interrupting existing work
**Files:**
- Modify: `AX_ACTION_DISPATCHER.ps1`
- Modify: `AX_DECISION_ENGINE.ps1`
- Modify: `AX_SUPERVISOR_TRIGGER.ps1`
- Modify: `AX_EXECUTIVE_CYCLE.ps1`
- Test: existing selector/dispatcher workflows plus new routing tests.

- [ ] Write regression tests proving currently executing jobs are not duplicated.
- [ ] Replace any remaining raw-priority selection with the canonical dependency/capability route.
- [ ] Dispatch independent eligible work in parallel when a verified agent exists.
- [ ] Preserve PC2 as specialized/fallback capacity rather than a universal bottleneck.
- [ ] Run full relevant GitHub Actions tests and commit.

### Task 5: Add durable evidence and task-state write-back
**Files:**
- Modify: `AX_TASK_REGISTRY.json` only through verified state transitions.
- Modify: relevant Control Runtime/AERIS execution bridge files.
- Test: end-to-end state/evidence regression workflow.

- [ ] Write failing tests for missing evidence, missing verification, and missing write-back.
- [ ] Implement task-result linkage with task ID, agent ID, execution timestamp from trusted authority, evidence reference, and verification result.
- [ ] Ensure agent failure returns capacity failure rather than false completion.
- [ ] Run tests and commit.

### Task 6: End-to-end multi-agent verification
**Files:**
- Create: `.github/workflows/ax-multi-agent-dispatch-tests.yml`
- Test: complete routing/evidence/dependency suite.

- [ ] Verify existing queue/runtime health remains intact.
- [ ] Verify Gemini/Copilot status only from real evidence.
- [ ] Verify at least one safe parallel route per agent when capability is actually READY.
- [ ] Verify blocked/unavailable routes do not claim execution.
- [ ] Verify no financial/live-money execution occurs.
- [ ] Record final evidence and commit.
