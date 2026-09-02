# Apps Script OAuth Bridge Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build a secure bridge that lets K authorize once in Google and then allows controlled Apps Script source read/update/deploy/verify operations without putting Google credentials in chat.

**Architecture:** A local/controlled bridge performs the Google OAuth authorization-code flow, stores refresh credentials outside Git, retrieves Apps Script project content before any mutation, creates a backup, applies narrowly scoped patches, updates the complete project content, and verifies the resulting deployment. The bridge must fail closed when OAuth, script ID, backup, or verification prerequisites are missing.

**Tech Stack:** Node.js, Google OAuth 2.0, Apps Script API v1, HTTPS localhost callback, Git/GitHub for source-of-truth and audit artifacts.

**Spec:** docs/superpowers/specs/2026-09-02-revenue-first-cost-aware-execution.md

## Global Constraints

- Never place OAuth client secrets, access tokens, or refresh tokens in Git or chat.
- First-time Google authorization remains a human approval gate.
- `getContent` must succeed before any `updateContent` operation.
- `updateContent` must receive the complete preserved project content because it clears existing project files.
- Production success requires real Apps Script evidence, not local proof artifacts.
- Do not claim deployment or verification until Google returns the corresponding evidence.

---

### Task 1: OAuth bridge contract and failing tests

**Files:**
- Create: `tools/apps-script-oauth-bridge/src/oauth.ts`
- Create: `tools/apps-script-oauth-bridge/tests/oauth.test.mjs`
- Create: `tools/apps-script-oauth-bridge/package.json`

**Interfaces:**
- Produces deterministic authorization URL construction, state validation, callback parsing, and token persistence interfaces.

- [ ] Write tests for state generation/validation, authorization URL scope construction, callback error handling, and secret-file permissions.
- [ ] Run tests and confirm they fail because the bridge implementation is absent.
- [ ] Implement the minimal OAuth helpers.
- [ ] Run tests and confirm they pass.

### Task 2: Apps Script API client

**Files:**
- Create: `tools/apps-script-oauth-bridge/src/apps-script.ts`
- Modify: `tools/apps-script-oauth-bridge/tests/oauth.test.mjs` or create `tests/apps-script.test.mjs`

**Interfaces:**
- `getProjectContent(scriptId, accessToken)` returns complete Apps Script content.
- `updateProjectContent(scriptId, accessToken, content)` sends the preserved complete content.
- `listDeployments(scriptId, accessToken)` reads deployment evidence.

- [ ] Write mocked HTTP tests for GET content and update content, including rejection on non-2xx responses.
- [ ] Verify tests fail first.
- [ ] Implement the API client with no token logging.
- [ ] Run tests and confirm they pass.

### Task 3: Backup and patch pipeline

**Files:**
- Create: `tools/apps-script-oauth-bridge/src/pipeline.ts`
- Create: `tools/apps-script-oauth-bridge/tests/pipeline.test.mjs`

**Interfaces:**
- `backup(content)` writes a timestamped immutable backup outside production mutation.
- `applyPatch(content, patch)` produces a complete new content payload.
- `verifyPreflight(content)` rejects empty/incomplete project content and missing manifest.

- [ ] Write failing tests for backup-before-update, manifest preservation, and fail-closed behavior.
- [ ] Implement the pipeline.
- [ ] Run tests and confirm green.

### Task 4: One-click launcher and callback server

**Files:**
- Create: `tools/apps-script-oauth-bridge/src/server.ts`
- Create: `tools/apps-script-oauth-bridge/start-bridge.ps1`
- Create: `tools/apps-script-oauth-bridge/.env.example`
- Create: `tools/apps-script-oauth-bridge/README.md`

**Interfaces:**
- Launcher opens the local authorization endpoint automatically.
- Callback exchanges the authorization code for tokens and stores them locally.
- Missing client configuration produces a clear human gate instead of silently failing.

- [ ] Add tests for callback success/error and one-time state consumption.
- [ ] Implement localhost callback and browser launch.
- [ ] Verify secrets are excluded from Git.

### Task 5: Controlled Apps Script operation

**Files:**
- Create: `tools/apps-script-oauth-bridge/src/operate.ts`
- Create: `tools/apps-script-oauth-bridge/tests/operate.test.mjs`

**Interfaces:**
- `inspect()` performs read-only project inspection.
- `patchAndUpdate()` performs backup → patch → preflight → update.
- `verify()` checks post-update content/deployment evidence.

- [ ] Write failing tests enforcing inspect-before-update and verification-before-success.
- [ ] Implement the operation controller.
- [ ] Run all bridge tests.

### Task 6: GitHub integration and audit workflow

**Files:**
- Create: `.github/workflows/apps-script-bridge-validation.yml`
- Modify: `tools/apps-script-oauth-bridge/README.md`

- [ ] Validate the bridge code on every change without requiring real OAuth credentials.
- [ ] Confirm no secrets are printed by CI.
- [ ] Document the exact evidence required before declaring production connected.

### Task 7: Production connection gate

**Files:**
- No production source mutation until live OAuth is available.

- [ ] Run the bridge on the controlled runtime.
- [ ] K performs only the Google authorization approval when prompted.
- [ ] Retrieve the real Apps Script project content.
- [ ] Create and verify a real backup.
- [ ] Apply the approved trigger-scope fix.
- [ ] Deploy/update only after the source backup is confirmed.
- [ ] Verify a real Apps Script trigger execution with no `ReferenceError: data is not defined`.
- [ ] Record the real timestamp and evidence in A MASTER BRAIN state.
