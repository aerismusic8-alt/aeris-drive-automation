# AX PC Remote Control & Terminal v1 Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans (recommended) to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build an authenticated outbound PC1/PC2 node-control layer with a controlled administrative terminal so AX can diagnose and recover the real execution machines remotely.

**Architecture:** Reuse the existing AX node polling pattern, extending it into a dedicated node control protocol and local Windows service. AX Control Runtime remains the controller-facing gateway; PC agents make outbound HTTPS calls and execute only policy-approved commands locally. GitHub Actions remains an execution path, while node control becomes the recovery path when runner infrastructure is unhealthy.

**Tech Stack:** Cloudflare Worker/TypeScript, PowerShell, Windows Service/Task Scheduler, GitHub Actions, JSON over HTTPS, existing AX/AERIS node registration and heartbeat mechanisms.

**Spec:** `docs/superpowers/specs/2026-09-06-ax-pc-remote-control.md`

## Global Constraints

- No unauthenticated public shell.
- No public inbound RDP/WinRM/SMB requirement.
- Per-node authentication and restrictive local secret ACLs.
- All remote commands audited with correlation IDs and exit results.
- Financial/live execution disabled by default.
- High-impact/destructive operations require an explicit policy gate.
- Verification failure stops the chain; never report success without evidence.

---

### Task 1: Map the existing node gateway and command protocol

**Files:** Inspect existing `AX_NODE_RUNNER.ps1`, gateway worker entrypoints, node registration handlers, delegation queue and tests.

- [ ] Identify current node registration, heartbeat, pull and completion handlers.
- [ ] Identify the current runtime `/execute` path and its trust boundary.
- [ ] Identify existing tests covering node authentication and delegation.
- [ ] Record gaps between current node runner behavior and local administrative control.

**Verification:** Produce a repository-grounded interface map before modifying implementation.

### Task 2: Define and test the remote-control command schema

**Files:** Create/modify the gateway command contract and its unit tests.

**Interface:** Authenticated request -> `command_id`, target node, command class, payload, timeout, policy decision and audit metadata.

- [ ] Write failing tests for accepted safe command classes, rejected unauthorized classes, missing authentication and timeout bounds.
- [ ] Run tests and confirm expected failures.
- [ ] Implement the minimal command schema/policy evaluator.
- [ ] Run tests and confirm pass.

### Task 3: Implement the PC local control engine

**Files:** Create a focused PowerShell local execution module under the existing AX/AKATH node structure; extend `AX_NODE_RUNNER.ps1` only where necessary; add tests.

**Interface:** `Invoke-AxNodeCommand(command, args, timeout, policy)` -> normalized result containing command ID, node ID, exit code, stdout, stderr, duration and verification state.

- [ ] Write failing tests for health probes and harmless terminal commands.
- [ ] Implement execution and normalized result capture.
- [ ] Add timeout/error handling.
- [ ] Redact secret-looking output before transport/logging.
- [ ] Run targeted tests.

### Task 4: Add Windows service installation and startup management

**Files:** Create/update node installation/bootstrap PowerShell scripts and service documentation.

- [ ] Write an idempotent installation test/check script.
- [ ] Implement service registration and recovery-on-failure settings.
- [ ] Apply restrictive ACLs to local node credentials/configuration.
- [ ] Add uninstall/repair paths.
- [ ] Verify on a real PC node.

### Task 5: Add gateway-to-node remote terminal dispatch

**Files:** Modify AX Control Runtime gateway entrypoint; add gateway tests.

**Interface:** AX submits authenticated terminal request -> gateway enqueues for target node -> node claims/executes/completes -> gateway returns verified evidence.

- [ ] Write failing end-to-end protocol tests.
- [ ] Implement enqueue/claim/complete flow.
- [ ] Add replay protection and command IDs.
- [ ] Add timeout/failure state transitions.
- [ ] Run targeted tests.

### Task 6: Add runner/service recovery operations

**Files:** Create focused recovery policy and PowerShell operations; add recovery tests.

- [ ] Write failing tests for runner stopped/online states.
- [ ] Implement inspection and restart operations.
- [ ] Verify runner is online after restart before declaring recovery.
- [ ] Add PC1 -> PC2 failover decision logic.
- [ ] Run recovery tests.

### Task 7: Integrate AX Active Executions with node recovery

**Files:** Modify `.github/workflows/ax-active-executions.yml` only after node-control path is verified; modify supervisor scripts/configuration; add integration tests.

- [ ] Detect queued/no-runner conditions.
- [ ] Call node health/recovery path rather than assuming a runner exists.
- [ ] Retry workflow dispatch only after runner verification.
- [ ] Preserve PC1/PC2 target semantics.
- [ ] Verify a real workflow is picked up by a self-hosted runner.

### Task 8: Build the AX terminal operator surface

**Files:** Add a small terminal command interface/API surface in the existing control runtime and machine-readable status/result output.

**Interfaces:** `terminal.exec(target, command, timeout, task_id)` -> verified result/evidence; `terminal.health(target)` -> health and runner status.

- [ ] Add tests for target validation and policy enforcement.
- [ ] Implement terminal request/result surface.
- [ ] Add audit correlation and evidence references.
- [ ] Verify harmless commands on PC1 and PC2.

### Task 9: End-to-end acceptance and failure recovery

**Files:** Update acceptance tests and operational documentation.

- [ ] Verify PC1 registration and heartbeat.
- [ ] Verify PC2 registration and heartbeat.
- [ ] Execute harmless terminal probe on PC1.
- [ ] Execute harmless terminal probe on PC2.
- [ ] Stop/recover the runner service under the approved policy.
- [ ] Dispatch a real `workflow_dispatch` and verify runner pickup.
- [ ] Exercise deterministic PC1 -> PC2 failover.
- [ ] Verify runtime state/Brain rehydration evidence.
- [ ] Verify audit logs contain command and result evidence.
- [ ] Confirm no public inbound administrative port is required.

**Completion gate:** Do not claim complete until the real PC nodes pass the full chain: `AX -> gateway -> node -> local execution -> GitHub runner/worker -> verification -> audit evidence`.
