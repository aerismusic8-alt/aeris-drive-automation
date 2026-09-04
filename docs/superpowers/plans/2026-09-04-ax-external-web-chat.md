# AX External Web Chat Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add a secure externally accessible AX Web Chat on the existing `ax-control-runtime`, with the controlled PC bridge carrying requests to the existing Local Hub and returning verified results.

**Architecture:** Cloudflare Worker remains a thin transport/control boundary and serves the external UI. The Worker stores only short-lived correlated transport/result records in its existing Durable Object; the PC bridge is the only path into the Local Hub. A_MASTER_BRAIN remains authoritative and no Local Hub secret, GitHub token, or PC pull secret reaches the browser.

**Tech Stack:** Cloudflare Workers, Durable Objects, TypeScript, vanilla HTML/CSS/JS, PowerShell bridge, GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-09-04-ax-external-web-chat-design.md`

## Global Constraints

- K remains Final Authority.
- A_MASTER_BRAIN remains the only authoritative source of identity, mission, tasks, state, evidence, and verification.
- `aeris-execution-runtime` remains a separate boundary.
- `FREE_ONLY` remains enforced and `liveFinancialExecution=false`.
- Browser must never receive `AX_PC_PULL_SECRET`, GitHub tokens, or Local Hub credentials.
- Attachments are metadata references only; raw binary/data must not be written into master state.
- Existing `AX External Channel Readiness` must remain green.

---

### Task 1: Add correlated result storage and safe result retrieval

**Files:**
- Modify: `cloudflare/ax-control-runtime/src/index.ts`
- Test: `cloudflare/ax-control-runtime` readiness workflow plus direct endpoint contract checks

**Interfaces:**
- Consumes: existing `/mobile/input`, `/pc/pull`, `/pc/ack`, `AX_GATEWAY_INBOX` transport records.
- Produces: `/web/session`, `/web/input`, `/web/result/:requestId` and result correlation fields for the browser.

- [ ] **Step 1: Write the failing contract probe**

Add readiness assertions that `/chat` exists and an unauthenticated protected web input is rejected. Add a result endpoint assertion for an unknown request returning `404`.

- [ ] **Step 2: Run the probe and verify it fails**

Run `AX External Channel Readiness`; expected failure is the missing `/chat`/web contract.

- [ ] **Step 3: Implement minimal Worker endpoints**

Use the existing Durable Object record model. Add a short-lived `results` record keyed by `request_id`. Keep result payloads limited to Local Hub status/evidence/verification fields and never persist credentials.

- [ ] **Step 4: Run the probe and verify it passes**

Run the public contract checks again; expected `PUBLIC_WEB_CHAT_SURFACE_PASS` plus protected-input rejection.

- [ ] **Step 5: Commit**

Commit message: `feat: add AX external web result channel`

### Task 2: Add dedicated browser session boundary

**Files:**
- Modify: `cloudflare/ax-control-runtime/src/index.ts`
- Modify: `cloudflare/ax-control-runtime/wrangler.jsonc` only if a binding/configuration is required

**Interfaces:**
- Consumes: a dedicated Worker secret for browser authentication.
- Produces: opaque short-lived browser session token used only against web endpoints.

- [ ] **Step 1: Write failing authentication tests**

The web input route must reject missing/invalid session tokens and the browser must not be able to call PC routes with the web token.

- [ ] **Step 2: Verify the tests fail**

Run the readiness contract; expected failure is the missing session boundary.

- [ ] **Step 3: Implement session issuance and validation**

Use a dedicated secret, time-bounded opaque session token, constant-time secret comparison, and no secret value in HTML/JS. Do not reuse `AX_PC_PULL_SECRET`.

- [ ] **Step 4: Verify authentication tests pass**

Confirm valid session access and invalid-session rejection, while `/pc/pull` and `/pc/ack` still require `AX_PC_PULL_SECRET`.

- [ ] **Step 5: Commit**

Commit message: `feat: secure AX external web sessions`

### Task 3: Add external chat UI

**Files:**
- Create: `cloudflare/ax-control-runtime/public/chat/index.html`
- Create: `cloudflare/ax-control-runtime/public/chat/app.js`
- Create: `cloudflare/ax-control-runtime/public/chat/styles.css`
- Modify: `cloudflare/ax-control-runtime/wrangler.jsonc`

**Interfaces:**
- Consumes: `/web/session`, `/web/input`, `/web/result/:requestId`, `/time`.
- Produces: responsive browser chat interface with status/evidence display.

- [ ] **Step 1: Write failing browser contract checks**

Verify the UI contains login/session controls, message composer, attachment metadata input, M-A-CHECK control, status panel, and logout.

- [ ] **Step 2: Verify the checks fail**

Deploy the current Worker; expected `/chat` asset is missing.

- [ ] **Step 3: Implement the static UI**

Serve assets through Cloudflare Workers Static Assets. The UI must call only the Worker web routes, never Local Hub routes. File uploads are represented as safe metadata references unless a controlled storage integration is added later.

- [ ] **Step 4: Verify UI and API integration**

Open `/chat`, authenticate, submit a text task, observe `RECEIVED/CLAIMED/SUBMITTED/COMPLETED/FAILED`, and ensure secret values are never rendered or embedded.

- [ ] **Step 5: Commit**

Commit message: `feat: add AX external web chat UI`

### Task 4: Make the PC bridge return Local Hub results

**Files:**
- Modify: `AX_CONTROL_HUB/AX_PC_MOBILE_BRIDGE.ps1`
- Modify: `cloudflare/ax-control-runtime/src/index.ts` if request/result contract needs final alignment

**Interfaces:**
- Consumes: Worker `/pc/pull` item and Local Hub `/gateway/input` result.
- Produces: Worker `/pc/result` submission followed by `/pc/ack` only after result persistence succeeds.

- [ ] **Step 1: Write failing bridge contract**

Require a pulled request to produce a correlated result record before ACK.

- [ ] **Step 2: Verify failure against current bridge**

Run the controlled bridge E2E probe and confirm the current implementation ACKs without returning the Local Hub result.

- [ ] **Step 3: Implement result-forwarding sequence**

Sequence: pull → local gateway/input → post result → ack. On result-post failure, do not ACK; allow lease expiry/retry.

- [ ] **Step 4: Verify bridge E2E**

Run a text probe and confirm request/task IDs match, result is visible to `/web/result/:requestId`, and ACK occurs only after result persistence.

- [ ] **Step 5: Commit**

Commit message: `feat: return Local Hub results through AX bridge`

### Task 5: Integrate deployment and readiness gates

**Files:**
- Modify: `.github/workflows/cloudflare-runtime.yml`
- Modify: `.github/workflows/ax-external-channel-readiness.yml`

**Interfaces:**
- Consumes: GitHub Actions secrets for deployment/readiness.
- Produces: automated deployment plus external chat readiness checks.

- [ ] **Step 1: Add readiness checks**

Check `/chat`, authentication boundary, submit, result correlation, and final FREE_ONLY guardrails in addition to the existing Mobile→PC pull/ACK checks.

- [ ] **Step 2: Verify new checks fail on missing implementation**

Run readiness against the pre-change Worker and confirm the new checks fail for the intended reason.

- [ ] **Step 3: Update deployment workflow**

Deploy Worker static assets and Worker code together. Ensure deployment preserves the two existing control secrets and any new web-session secret without logging secret values.

- [ ] **Step 4: Run full readiness**

Expected final status: existing mobile readiness plus `WEB_CHAT_SURFACE_PASS`, authenticated external request, PC bridge result, result retrieval, and `AX EXTERNAL CHANNEL READINESS: PASS`.

- [ ] **Step 5: Commit**

Commit message: `test: gate AX external web chat readiness`

### Task 6: Verify production and preserve rollback point

**Files:**
- No code changes unless a verified defect is found.

- [ ] **Step 1: Verify Worker health**

Confirm `ONLINE`, `FREE_ONLY`, `liveFinancialExecution=false`, both existing control auth flags true.

- [ ] **Step 2: Verify external chat**

Confirm `/chat` loads and a request completes through the PC bridge with authoritative Local Hub status/evidence.

- [ ] **Step 3: Verify boundaries**

Confirm Local Hub remains loopback-only, no secret is exposed in browser source, and A_MASTER_BRAIN is not duplicated into the Worker.

- [ ] **Step 4: Create a repository checkpoint/commit**

Commit message: `chore: checkpoint AX external web chat production readiness`
