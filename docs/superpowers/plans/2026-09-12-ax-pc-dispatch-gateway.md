# AX PC Dispatch Gateway Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build one searchable canonical dispatch gateway that routes AX tasks to PC2 through the existing Control Runtime and PC node protocol.

**Architecture:** The gateway creates a strict PC-targeted event and sends it to the existing Control Runtime enqueue interface. The PC2 node remains the pull/execute/result/ACK authority. The gateway and dispatcher only claim success after verified evidence.

**Tech Stack:** PowerShell, existing AX Control Runtime HTTP API, existing AX PC Node protocol, repository documentation and contract tests.

**Spec:** `docs/superpowers/specs/2026-09-12-ax-pc-dispatch-gateway-design.md`

## Global Constraints

- Do not modify `AX_PC_CONTROL/AX_PC_NODE.ps1` unless verification proves the existing protocol is insufficient.
- Do not store secrets in Git.
- Do not claim execution from enqueue acceptance alone.
- PC2 target is `PC2-CODING-EXECUTOR`.
- Preserve the existing PC node command allowlist.
- Keep obsolete alternatives in `TRASH/` rather than deleting them.

### Task 1: Contract tests

**Files:**
- Create: `tests/AX_PC_DISPATCH_GATEWAY.Tests.ps1`

- [ ] Write failing tests for canonical event shape, node target, lifecycle states, and rejection of unverified completion.
- [ ] Run the tests and confirm they fail because the gateway does not exist.
- [ ] Keep assertions independent of live secrets or live PC state.

### Task 2: Gateway implementation

**Files:**
- Create: `AX_PC_DISPATCH_GATEWAY.ps1`
- Create: `AX_PC_DISPATCH_GATEWAY.md`

- [ ] Implement event construction with requestId/taskId/nodeId.
- [ ] Implement Control Runtime enqueue using the existing runtime URL.
- [ ] Emit machine-readable lifecycle evidence.
- [ ] Return nonzero on rejected enqueue or unverifiable completion.
- [ ] Document exact canonical location, search terms, protocol, and test invocation.

### Task 3: Dispatcher integration

**Files:**
- Modify: `AX_ACTION_DISPATCHER.ps1`

- [ ] Add the PC2 gateway route before generic canonical runtime fallback.
- [ ] Ensure only PC-targeted tasks use the gateway.
- [ ] Preserve helper-agent routing and financial safety gates.
- [ ] Add explicit `PC_GATEWAY_SELECTED` evidence.

### Task 4: Verification

- [ ] Run contract tests and confirm green.
- [ ] Run PowerShell syntax checks for modified scripts.
- [ ] Verify Git diff contains only intended files.
- [ ] If live PC2 evidence is available, execute one harmless allowlisted command and verify pull/result/ACK; otherwise report the exact remaining runtime blocker rather than claiming E2E success.
