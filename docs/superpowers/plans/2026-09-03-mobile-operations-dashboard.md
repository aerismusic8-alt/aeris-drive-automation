# Mobile Operations Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Extend the existing AX dashboard into a mobile-first, read-only operations hub showing verified system state, task queue, activity, task detail, and AI/runtime status.

**Architecture:** Keep `dashboard/status.json` and `dashboard/ax-sync.json` as canonical state inputs. Add a small normalized client-side data layer and a queue/events source only where existing canonical data already exposes it; do not create a competing orchestration state store. Upgrade the existing `dashboard/index.html` rather than creating a parallel dashboard.

**Tech Stack:** Static HTML/CSS/JavaScript, browser Fetch API, Node.js built-in test runner for pure data-layer tests. No framework or runtime dependency is required for the first release.

**Spec:** `docs/superpowers/specs/2026-09-03-mobile-operations-dashboard-design.md`

## Global Constraints

- Mobile-first; desktop remains usable.
- Read-only monitoring; no execution/mutation controls in the UI.
- Existing canonical state remains authoritative.
- Missing, stale, invalid, or unverified data must be shown explicitly.
- No secrets, API keys, OAuth tokens, or credentials in dashboard assets.
- Do not rename existing repositories or architecture components.
- Do not reintroduce Apps Script as a required dashboard execution dependency.

---

### Task 1: Establish dashboard data model and tests

**Files:**
- Create: `dashboard/dashboard-data.mjs`
- Create: `tests/dashboard-data.test.mjs`

**Interfaces:**
- Consumes: parsed objects from `status.json`, `ax-sync.json`, and optional task/event/agent payloads.
- Produces: `normalizeDashboardState(status, sync, extras, now, staleMs)` returning `{system, pipeline, sync, selectedTask, tasks, events, agents, evidence}`.

- [ ] **Step 1: Write the failing tests**

Create tests for:
1. Normalizing an ONLINE/PASS/VERIFIED status.
2. Preserving UNKNOWN for absent queue/agent fields rather than inventing values.
3. Marking a source stale when `now - timestamp > staleMs`.
4. Marking sync as verified only when `schema === 'AX_DASHBOARD_SYNC_V1'` and `stateVerified === true`.
5. Returning an explicit invalid-data error for malformed/non-object input.

- [ ] **Step 2: Run the tests to verify they fail**

Run: `node --test tests/dashboard-data.test.mjs`
Expected: FAIL because `dashboard/dashboard-data.mjs` does not yet exist.

- [ ] **Step 3: Implement the minimal normalization module**

Implement pure functions with no network access:
- `normalizeDashboardState(status, sync, extras, now, staleMs)`
- `isStale(timestamp, now, staleMs)`
- `normalizeTask(task)`
- `normalizeEvent(event)`
- `normalizeAgent(agent)`

Rules:
- Never turn missing data into PASS/ONLINE/RUNNING.
- Accept the current status fields `system`, `overall`, `recovery`, `decision`, `dispatch`, `persistence`, `runner`, `mutation`, `selectedTask`, and `timestamp`.
- Compute pipeline progress from recovery/decision/dispatch/persistence using only PASS/VERIFIED as completed stages.
- Carry through task, event, and agent arrays only when supplied.
- Set `sync.verified` only for the exact sync schema and true verification flag.

- [ ] **Step 4: Run the tests to verify they pass**

Run: `node --test tests/dashboard-data.test.mjs`
Expected: PASS for all normalization and stale-data cases.

- [ ] **Step 5: Commit**

```bash
git add dashboard/dashboard-data.mjs tests/dashboard-data.test.mjs
git commit -m "test: add dashboard state normalization"
```

---

### Task 2: Add queue/activity source contract without replacing canonical state

**Files:**
- Create: `dashboard/task-queue.json`
- Create: `dashboard/activity.json`
- Create: `dashboard/agents.json`

**Interfaces:**
- Consumes: records produced by the existing automation/runtime when these files are updated.
- Produces: read-only JSON payloads consumed by the dashboard.

- [ ] **Step 1: Write fixture payloads that exercise the UI contract**

`task-queue.json` must contain an object with `schema: "AX_TASK_QUEUE_V1"` and `tasks: []`.

`activity.json` must contain an object with `schema: "AX_ACTIVITY_V1"` and `events: []`.

`agents.json` must contain an object with `schema: "AX_AGENTS_V1"` and `agents: []`.

- [ ] **Step 2: Validate fixture shape**

Run: `node --test tests/dashboard-data.test.mjs`
Expected: PASS, including empty-source behavior.

- [ ] **Step 3: Keep the files strictly read-only from the browser**

The browser may GET these resources only. Runtime writers remain outside the dashboard.

- [ ] **Step 4: Commit**

```bash
git add dashboard/task-queue.json dashboard/activity.json dashboard/agents.json
git commit -m "feat: add dashboard queue activity and agent contracts"
```

---

### Task 3: Upgrade the existing mobile dashboard UI

**Files:**
- Modify: `dashboard/index.html`

**Interfaces:**
- Consumes: `dashboard/status.json`, `dashboard/ax-sync.json`, `dashboard/task-queue.json`, `dashboard/activity.json`, `dashboard/agents.json`, and `dashboard/dashboard-data.mjs`.
- Produces: mobile-first read-only Operations Hub in the existing dashboard entry point.

- [ ] **Step 1: Add the failing UI contract checks**

Extend `tests/dashboard-data.test.mjs` with assertions for the IDs/labels required by the UI model: `taskQueue`, `activityFeed`, `taskDetail`, `agentStatus`, `syncState`, and `staleState`.

- [ ] **Step 2: Run tests to verify the UI contract is absent**

Run: `node --test tests/dashboard-data.test.mjs`
Expected: FAIL for the new UI contract assertions.

- [ ] **Step 3: Implement the mobile Operations Hub**

Update the existing HTML to include:
- Executive overview with system/overall/persistence/runner state.
- Queue summary cards for RUNNING, QUEUED, FAILED/NEED ACTION, COMPLETED.
- Filterable task list.
- Expandable task detail with task ID, agent, action, result, verification, error/retry, timestamp.
- Newest-first activity feed.
- AX/M/agent/runtime status cards based only on supplied agent payloads.
- Visible source timestamp, sync verification, and stale state.
- A refresh control plus lightweight polling; keep the existing no-store cache-busting behavior.
- Clear read-only labeling and no buttons that mutate runtime state.

Preserve the existing `status.json` executive fields and avoid exposing raw credentials or tokens.

- [ ] **Step 4: Run tests to verify the UI contract passes**

Run: `node --test tests/dashboard-data.test.mjs`
Expected: PASS.

- [ ] **Step 5: Commit**

```bash
git add dashboard/index.html tests/dashboard-data.test.mjs
git commit -m "feat: add mobile operations hub"
```

---

### Task 4: Connect runtime writers to dashboard sources

**Files:**
- Modify: the existing runtime/dashboard writer identified from the repository by the current implementation of `dashboard/status.json` updates.
- Modify: `dashboard/task-queue.json`, `dashboard/activity.json`, `dashboard/agents.json` only through the existing runtime writer path.
- Test: `tests/dashboard-data.test.mjs`

**Interfaces:**
- Consumes: existing runtime task, event, and agent state.
- Produces: the three versioned dashboard JSON contracts without changing the source-of-truth task/runtime model.

- [ ] **Step 1: Locate the current status writer and its exact update path**

Search the repository for the code that writes `dashboard/status.json`, then trace the existing task/registry/heartbeat fields available at that point. Do not add a second scheduler or execution loop.

- [ ] **Step 2: Write failing contract tests against representative writer output**

Add fixtures/assertions requiring valid `AX_TASK_QUEUE_V1`, `AX_ACTIVITY_V1`, and `AX_AGENTS_V1` envelopes whenever corresponding source data exists.

- [ ] **Step 3: Implement the smallest writer extension**

Extend the existing writer to serialize available task, activity, and agent records. If a category has no canonical source at the writer boundary, emit an empty array with the correct schema rather than fabricating records.

- [ ] **Step 4: Run tests and validate JSON**

Run: `node --test tests/dashboard-data.test.mjs`
Expected: PASS.

Validate that generated JSON parses successfully and contains no secret-like fields.

- [ ] **Step 5: Commit**

```bash
git add <exact-writer-files> dashboard/task-queue.json dashboard/activity.json dashboard/agents.json tests/dashboard-data.test.mjs
git commit -m "feat: publish canonical dashboard queue activity and agents"
```

---

### Task 5: End-to-end dashboard verification

**Files:**
- Modify: `tests/dashboard-data.test.mjs` only if verification coverage needs tightening.
- Modify: `dashboard/index.html` only if an observed issue is directly required to meet acceptance criteria.

**Interfaces:**
- Consumes: deployed/static dashboard assets and canonical JSON files.
- Produces: verified evidence that mobile view, queue, activity, task detail, sync, and stale handling work.

- [ ] **Step 1: Run all automated tests**

Run: `node --test tests/dashboard-data.test.mjs`
Expected: PASS with zero failures.

- [ ] **Step 2: Validate every dashboard JSON contract**

Parse `status.json`, `ax-sync.json`, `task-queue.json`, `activity.json`, and `agents.json` with a strict JSON parser.
Expected: all parse successfully and have their expected schema values.

- [ ] **Step 3: Verify the current live state**

Confirm the current status source reports its actual timestamp and verification fields; do not replace current values with hard-coded demo data.

- [ ] **Step 4: Verify mobile behavior**

Open the dashboard at a phone-sized viewport and verify that executive state, queue counts, activity, and task detail remain readable without horizontal scrolling.

- [ ] **Step 5: Verify stale/error behavior**

Temporarily test with an old timestamp and invalid JSON fixture in the local test harness. Confirm the UI shows STALE/DATA OFFLINE and never displays fabricated PASS/ONLINE values.

- [ ] **Step 6: Commit only verification fixes**

```bash
git add tests/dashboard-data.test.mjs dashboard/index.html
 git commit -m "test: verify mobile operations dashboard"
```
