# AKATH Self-Managed Execution & External Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Remove GitHub-hosted runner dependence from ordinary AX execution, strengthen autonomous executor routing, and deploy the read-only dashboard outside GitHub Actions.

**Architecture:** PC1/PC2 self-hosted runners remain the execution substrate. Cloudflare ingress/ledger/queue remain the control boundary. AI workers are selected by AX from available providers; provider failure triggers retry/failover. The dashboard is external and read-only.

**Tech Stack:** GitHub Actions, Windows self-hosted runners, Cloudflare Workers/Durable Objects/Queues, Node.js, Python, static dashboard hosting.

**Spec:** `docs/superpowers/specs/2026-09-08-akath-self-managed-execution-design.md`

## Global Constraints

- `COMPLETED + VERIFIED` is the only successful mission state.
- GitHub Actions budget is `$0`; ordinary execution must not require GitHub-hosted runners.
- Scheduled execution uses self-hosted runners.
- Dashboard is read-only and must not contain secrets.
- Existing queue/ledger contracts must be preserved.
- AI-provider failure must cause recovery/reroute rather than silent mission loss.

---

### Task 1: Eliminate automatic hosted execution paths

**Files:**
- Modify: `.github/workflows/ax-gemini-api-worker.yml`
- Modify: `.github/workflows/ax-openai-dispatcher.yml`
- Modify: `.github/workflows/ax-external-channel-readiness.yml`
- Modify: `.github/workflows/ax-control-runtime-acceptance.yml`
- Modify: `.github/workflows/ax-core-adapters-test.yml`
- Modify: `.github/workflows/ax-gemini-adapter-test.yml`
- Modify: `.github/workflows/ax-openai-code-stream-tests.yml`
- Modify: `.github/workflows/ax-dashboard-tests.yml`
- Modify: `.github/workflows/ax-dashboard-pages.yml`

**Interfaces:**
- Consumes: Existing workflow inputs, secrets, and repository paths.
- Produces: Workflows that are self-hosted/manual where appropriate and no longer burn hosted minutes automatically.

- [x] **Step 1: Change active worker runners and remove periodic polling**
  - Gemini API worker: `[self-hosted, Windows, X64]`, remove `schedule`.
  - OpenAI dispatcher: `[self-hosted, Windows, X64]`, remove `schedule`.

- [x] **Step 2: Disable automatic hosted acceptance/readiness triggers**
  - External readiness: keep `workflow_dispatch` only.
  - Control Runtime Acceptance: keep `workflow_dispatch` only for hosted provisioning stage unless migrated as a complete self-hosted pipeline.

- [x] **Step 3: Move push-triggered unit/contract tests to self-hosted**
  - Core adapter, Gemini adapter, OpenAI stream tests, dashboard tests use `[self-hosted, Windows, X64]`.

- [x] **Step 4: Prevent dashboard Pages deployment from consuming Actions automatically**
  - Keep GitHub Pages deployment manual-only; do not auto-deploy on every dashboard change.

- [x] **Step 5: Verify workflow source contracts**
  - Search workflow tree/source for `ubuntu-latest`, `windows-latest`, and `cron:`.
  - Confirm remaining hosted use is manual-only/non-core before proceeding.

- [ ] **Step 6: Commit the cost-protection changes**
  - Commit message: `chore: protect AKATH from hosted Actions quota exhaustion`

### Task 2: Make AX executor routing resilient

**Files:**
- Inspect and modify: `AKATH/runtime/` executor/routing modules selected from current tree.
- Test: existing routing/queue tests plus new regression test where applicable.

**Interfaces:**
- Consumes: `AX_MULTI_AI_DISPATCH_QUEUE.json`, mission ledger state, existing provider metadata.
- Produces: deterministic provider selection, retry/fallback evidence, and terminal `COMPLETED + VERIFIED` only after verification.

- [ ] **Step 1: Add a failing regression test** for provider-unavailable fallback.
- [ ] **Step 2: Run the targeted test and verify failure.**
- [ ] **Step 3: Implement the smallest fallback/reroute change using existing queue/ledger contracts.**
- [ ] **Step 4: Run targeted tests and verify pass.**
- [ ] **Step 5: Commit** with `feat: add AX executor fallback routing`.

### Task 3: Make cross-chat mission identity deterministic

**Files:**
- Modify: `cloudflare/ax-control-runtime/src/ax-adapters-route.ts`
- Modify: `cloudflare/ax-control-runtime/src/ax-mission-ledger.ts`
- Modify: `cloudflare/ax-control-runtime/src/ax-direct-console.ts`
- Test: `cloudflare/ax-control-runtime/test/` relevant mission/direct-console tests.

**Interfaces:**
- Consumes: mission ID, stable client command/message ID, content fingerprint.
- Produces: one logical task for one logical command across chat/context changes.

- [ ] **Step 1: Add failing idempotency tests** showing a new transport request ID does not create a second task for the same logical command.
- [ ] **Step 2: Verify the tests fail against current request-ID-derived identity.**
- [ ] **Step 3: Implement stable logical command identity independent of transport request ID.**
- [ ] **Step 4: Verify direct mission load resumes the latest unfinished task.**
- [ ] **Step 5: Run the focused suite and commit** with `fix: enforce cross-chat mission idempotency`.

### Task 4: External dashboard deployment

**Files:**
- Inspect/modify: `dashboard/index.html`
- Inspect/modify: `dashboard/dashboard-data.test.mjs`
- Add: hosting configuration only where required by the selected external host.

**Interfaces:**
- Consumes: existing public read-only runtime endpoints.
- Produces: verified public dashboard URL independent of GitHub-hosted Actions.

- [ ] **Step 1: Verify dashboard has no secret-bearing configuration and uses read-only runtime endpoints.**
- [ ] **Step 2: Test dashboard locally/static-contract test.**
- [ ] **Step 3: Deploy to external static hosting using the available connected deployment platform, preferring Cloudflare/Vercel without introducing a new paid dependency.**
- [ ] **Step 4: Verify the deployed URL returns the dashboard and live state polling works.**
- [ ] **Step 5: Record the verified URL in the repository operations documentation and commit** with `feat: deploy external AX operations dashboard`.

### Task 5: End-to-end autonomous proof

**Files:**
- Modify only where needed by verified failures.
- Evidence: mission ledger/queue/run artifacts and Git history.

**Interfaces:**
- Consumes: READY tasks already present in `AX_MULTI_AI_DISPATCH_QUEUE.json`.
- Produces: durable execution evidence from READY → RUNNING/RECOVERING → COMPLETED + VERIFIED.

- [ ] **Step 1: Select one existing READY mission with a non-destructive target.**
- [ ] **Step 2: Dispatch through the self-hosted execution path.**
- [ ] **Step 3: Verify executor output and write-back evidence.**
- [ ] **Step 4: Verify mission ledger terminal state is `COMPLETED + VERIFIED`.**
- [ ] **Step 5: Verify no manual K intervention was needed between execution stages.**
- [ ] **Step 6: Commit the proof/evidence update if repository state requires it.**

## Final Verification

- [ ] Confirm no required automatic workflow depends on GitHub-hosted runners.
- [ ] Confirm self-hosted Supervisor remains scheduled.
- [ ] Confirm queue and mission ledger are intact.
- [ ] Confirm external dashboard URL is reachable.
- [ ] Confirm one real mission reaches `COMPLETED + VERIFIED` with evidence.
