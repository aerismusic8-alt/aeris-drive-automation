# OpenHands Autonomous Deployment Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Connect OpenHands Agent Canvas to the existing AX execution architecture using a free-first, capability-driven deployment path without replacing the existing AX runtime.

**Architecture:** AX remains the controller. OpenHands is the first external execution agent. The integration uses OpenHands Agent Canvas/Agent Server as the agent runtime, with AX supplying jobs and receiving verified results. Native OpenHands automation is preferred; AX bridges are used only where native capability is insufficient.

**Tech Stack:** OpenHands Agent Canvas, OpenHands Agent Server/SDK, GitHub Actions self-hosted runner, PowerShell, existing AX dispatcher/state/persistence layer.

**Spec:** Approved OpenHands deployment design in the AX conversation on 2026-09-01.

## Global Constraints

- Free/Open Source first; no automatic paid API/provider usage.
- A paid dependency requires explicit K approval.
- Do not replace or destabilize the existing AX runtime.
- Verify every installation and execution result with real evidence.
- Prefer native OpenHands automation before adding an AX trigger/bridge.
- Prioritize a monetizable output path over unnecessary infrastructure work.
- OpenHands must not receive broader permissions than the task requires.

---

### Task 1: Detect the self-hosted execution environment

**Files:**
- Create: `.github/workflows/openhands-capability-diagnostic.yml`

**Interfaces:**
- Consumes: existing self-hosted runner.
- Produces: machine capability report covering Node, npm, uv, Docker, OpenHands/Agent Canvas, Ollama/local model availability, and workspace access.

- [ ] Add a manual + safe push-triggered diagnostic workflow.
- [ ] Run it on the existing self-hosted runner.
- [ ] Record only non-secret capability/status data.
- [ ] Verify the workflow result before choosing an installation path.

### Task 2: Install the current OpenHands Agent Canvas path

**Files:**
- Create: `.github/workflows/openhands-bootstrap.yml`

**Interfaces:**
- Consumes: Task 1 capability report.
- Produces: verified local Agent Canvas installation on the selected self-hosted execution node.

- [ ] Use the current Agent Canvas installation path, not the deprecated OpenHands V1 CLI.
- [ ] Install only missing prerequisites.
- [ ] Prefer local/self-hosted execution over cloud infrastructure.
- [ ] Do not install or activate paid model providers automatically.
- [ ] Verify executable/version and startup health.

### Task 3: Connect a free model-access path

**Files:**
- Create: `docs/agents/openhands-free-runtime.md`

**Interfaces:**
- Consumes: Task 1 capability report.
- Produces: selected free/local model path and fallback rules.

- [ ] Prefer an already available free/local model path.
- [ ] If none exists, document the cheapest verified path without activating paid billing.
- [ ] Add limit monitoring and stop-before-paid behavior.

### Task 4: Add AX-specific OpenHands Blueprint

**Files:**
- Create: `docs/agents/OPENHANDS_AX_BLUEPRINT.md`

**Interfaces:**
- Consumes: AX task registry, dispatcher, persistence and verification model.
- Produces: OpenHands-specific operating instructions.

- [ ] Define AX role, task lifecycle, evidence requirements and stop conditions.
- [ ] Define free-first and fallback behavior.
- [ ] Define workspace and permission boundaries.
- [ ] Define how completed work is reported back to AX.

### Task 5: End-to-end proof

**Files:**
- Modify: only the minimum runtime/dispatcher files required after Tasks 1-4 are verified.

**Interfaces:**
- Consumes: installed OpenHands + blueprint.
- Produces: one real completed task with execution evidence, verification, and persisted state.

- [ ] Dispatch one bounded, non-destructive coding task.
- [ ] Verify OpenHands executed it.
- [ ] Verify the artifact/result.
- [ ] Verify AX persistence/audit evidence.
- [ ] Only after PASS, promote the integration as the first reusable Agent Adapter.
