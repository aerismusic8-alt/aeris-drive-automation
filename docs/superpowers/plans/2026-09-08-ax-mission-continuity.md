# AX Mission Continuity Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make AX mission identity persistent across chat sessions and provide a direct K-to-AX command channel that bypasses ChatGPT and the legacy Gateway Inbox for intake.

**Architecture:** Add a dedicated mission ledger Durable Object for immutable command envelopes and completion evidence. Add `/ax/direct/*` routes in the existing Cloudflare Control Runtime and a direct browser console that submits exact envelopes to the ledger and AX execution queue.

**Tech Stack:** Cloudflare Workers, Durable Objects, Cloudflare Queues, TypeScript, existing AX Control Runtime.

**Spec:** `docs/superpowers/specs/2026-09-08-ax-mission-continuity-design.md`

## Global Constraints

- Chat/session lifecycle must not create duplicate missions.
- Existing AX execution queue remains the execution transport.
- Command content must be preserved exactly at intake.
- Authentication continues to use `AX_MOBILE_INGRESS_SECRET`.
- No financial/live execution is enabled by this change.

---

### Task 1: Add immutable mission ledger

**Files:**
- Create: `cloudflare/ax-control-runtime/src/ax-mission-ledger.ts`
- Modify: `cloudflare/ax-control-runtime/wrangler.jsonc`
- Test: `cloudflare/ax-control-runtime/test/ax-mission-ledger.test.ts`

**Interfaces:**
- `putCommand(record)` returns `CREATED` or `DUPLICATE` when the fingerprint and mission identity match.
- `getMission(missionId)` returns the latest immutable command plus lifecycle fields.
- `markStatus(missionId, status, evidence)` appends completion/recovery state without changing the original command.

- [ ] **Step 1: Write the failing tests** for duplicate command rejection, exact command preservation, and completion evidence persistence.
- [ ] **Step 2: Run the ledger tests** and confirm they fail before implementation.
- [ ] **Step 3: Implement the Durable Object** with deterministic mission keys and fingerprint checks.
- [ ] **Step 4: Run the tests** and confirm they pass.
- [ ] **Step 5: Commit** the ledger and tests.

### Task 2: Add direct AX intake API

**Files:**
- Modify: `cloudflare/ax-control-runtime/src/ax-adapters-route.ts`
- Test: `cloudflare/ax-control-runtime/test/ax-direct-route.test.ts`

**Interfaces:**
- `POST /ax/direct/input` accepts `{ mission_id?, task_id?, content, content_type, request_id? }`.
- Route authenticates with `AX_MOBILE_INGRESS_SECRET`.
- Route computes a fingerprint over the immutable command fields, stores the command in the mission ledger, and sends one `AxEvent` to `AX_EXECUTION_QUEUE` only for a newly created mission command.
- `GET /ax/direct/mission/{mission_id}` returns lifecycle state and evidence.

- [ ] **Step 1: Write failing route tests** for auth, exact payload preservation, duplicate idempotency, and queue-send-once behavior.
- [ ] **Step 2: Run tests** and confirm failure.
- [ ] **Step 3: Implement the route.** Never pass direct commands through `AX_GATEWAY_INBOX`.
- [ ] **Step 4: Run tests** and confirm pass.
- [ ] **Step 5: Commit** the route and tests.

### Task 3: Add direct browser console

**Files:**
- Create: `cloudflare/ax-control-runtime/src/ax-direct-console.ts`
- Modify: `cloudflare/ax-control-runtime/src/ax-adapters-route.ts`
- Test: `cloudflare/ax-control-runtime/test/ax-direct-console.test.ts`

**Interfaces:**
- `GET /ax/direct` renders a small browser UI.
- Browser persists only the direct session token and mission id; it does not generate new task ids for every page load.
- Sending the same message again with the same request id is idempotent.

- [ ] **Step 1: Write the failing console route test.**
- [ ] **Step 2: Implement the console.**
- [ ] **Step 3: Add mission status refresh without altering commands.**
- [ ] **Step 4: Run tests and confirm pass.**
- [ ] **Step 5: Commit.**

### Task 4: Add continuity/recovery policy tests

**Files:**
- Create: `AKATH/tests/mission_continuity_policy_tests.py`
- Create: `AX_MISSION_CONTINUITY_POLICY.json`

**Interfaces:**
- Policy states that `READY/RUNNING/RECOVERING` missions resume by identity.
- `COMPLETED` missions are immutable and cannot be recreated by chat/session events.
- Recovery attempts preserve the original mission fingerprint.

- [ ] **Step 1: Write failing policy tests.**
- [ ] **Step 2: Add the policy and minimal implementation hooks used by tests.**
- [ ] **Step 3: Run the policy tests.**
- [ ] **Step 4: Commit.**

### Task 5: Verify deployment and direct channel

**Files:**
- Modify: existing Cloudflare runtime deployment configuration only if required.

- [ ] **Step 1: Push implementation to `main`.**
- [ ] **Step 2: Run available Cloudflare/runtime tests.**
- [ ] **Step 3: Verify the direct endpoint and stable console URL.**
- [ ] **Step 4: Send one unique test command through the direct channel.**
- [ ] **Step 5: Verify the mission ledger contains the exact command and only one queued execution.**
- [ ] **Step 6: Verify the response/evidence references the same mission/task id.**
- [ ] **Step 7: Record evidence and commit the verification artifact.**
