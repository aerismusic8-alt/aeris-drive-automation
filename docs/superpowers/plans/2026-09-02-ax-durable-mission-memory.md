# AX Durable Mission Memory Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:executing-plans or superpowers:subagent-driven-development. Steps use checkbox syntax.

**Goal:** Build a durable AX Mission Ledger so every K-assigned task has one recoverable Mission ID, persistent lifecycle state, latest conversation/update, evidence, and cross-session continuity.

**Architecture:** Keep transient chat context separate from authoritative durable mission state. `AX_MISSION_LEDGER.json` is the source of truth; `AX_CONTEXT_SYNC.ps1` remains the short-window projection. A mission-sync workflow performs idempotent upserts, integrity verification, and Git persistence so a replacement worker can recover state after session, PC, runner, or process interruption.

**Tech Stack:** PowerShell, JSON, GitHub Actions, self-hosted runner, existing AX context-sync pipeline.

**Spec:** `docs/superpowers/specs/2026-09-02-ai-worker-feasibility-dispatch-design.md` plus K's approved requirement that assigned work must never disappear and latest task state must remain recoverable across channels/sessions.

## Global Constraints

- `NOT VERIFIED ≠ SUCCESS`.
- Every task retains objective, dispatch, worker, output, verification, evidence, certification, and business-extension state.
- Existing running/waiting jobs are not cancelled, overwritten, or delayed.
- Mission IDs remain stable across chat/session/channel changes.
- Completed missions remain searchable.
- No credentials, tokens, passwords, API keys, or authentication material may be persisted.
- Replaying an event must be idempotent.
- A ledger is successful only after schema/integrity verification passes.

## File Map

**Create:**
- `AX_MISSION_LEDGER.ps1` — normalization, deterministic IDs, upsert, projection, resolution, verification.
- `AX_MISSION_LEDGER.json` — durable registry and event history.
- `.github/workflows/ax-mission-ledger-sync.yml` — persistence/recovery workflow.
- `tests/AX_MISSION_LEDGER.Tests.ps1` — Pester tests.
- `docs/AX_MISSION_MEMORY_PROTOCOL_V1.md` — cross-channel mission protocol.

**Modify:**
- `AX_CONTEXT_SYNC.ps1` — expose normalized mission-eligible events while preserving `AX_CANONICAL_STATE_V1` semantics.
- `.github/workflows/ax-context-sync.yml` — run mission persistence only after canonical-state verification.

---

### Task 1: Data contract

**Files:** create protocol and initial ledger.

- [ ] Define `AX_MISSION_LEDGER_V1`, mission fields (`missionId`, objective, deadline, priority, status, channelRefs, lastConversation, workerAllocation, output, verification, evidence, certification, businessExtension, sourceEvents), and event fields (`eventId`, missionId, timestamp, channel, eventType, content, sourceId, sourceHash, actor, verified).
- [ ] Define lifecycle: `CREATED`, `FEASIBILITY`, `APPROVED`, `DISPATCHED`, `EXECUTING`, `OUTPUT`, `VERIFYING`, `EVIDENCE`, `AX_CERTIFIED`, `DELIVERED`, `BUSINESS_EXTENSION`, `FAILED`, `NEEDS_REWORK`, `BLOCKED`, `ARCHIVED`.
- [ ] Initialize an empty ledger with zero counts and integrity metadata.
- [ ] Parse the JSON with PowerShell `ConvertFrom-Json`.
- [ ] Commit: `feat: define AX durable mission ledger contract`.

### Task 2: Ledger engine + TDD

**Files:** `AX_MISSION_LEDGER.ps1`, `tests/AX_MISSION_LEDGER.Tests.ps1`.

**Interfaces:**
- `New-AxEventId` → deterministic SHA-256 ID.
- `New-AxMissionId` → stable ID for an explicitly created mission.
- `Normalize-AxMissionEvent` → normalized, secret-safe event.
- `Upsert-AxMissionEvent` → idempotent ledger update.
- `Get-AxMission` / `Resolve-AxMission` → current mission plus latest conversation.
- `Set-AxMissionStatus` → validated lifecycle transition.
- `Get-AxMissionSummary` → dashboard/report projection.
- `Test-AxMissionLedger` → structured verification evidence and `verified` boolean.

- [ ] Write failing Pester tests for deterministic IDs, duplicate replay, lifecycle validation, secret redaction, cross-channel continuity, restart recovery, completion retention, and corrupted-ledger rejection.
- [ ] Run focused Pester tests and confirm failure before implementation.
- [ ] Implement minimal functions to make each test pass.
- [ ] Run `Invoke-Pester .\tests\AX_MISSION_LEDGER.Tests.ps1 -Output Detailed` and require all PASS.
- [ ] Commit: `feat: add durable mission ledger engine`.

### Task 3: Context integration

**Files:** modify `AX_CONTEXT_SYNC.ps1` and `.github/workflows/ax-context-sync.yml`.

- [ ] Ensure ordinary context events do not create phantom missions.
- [ ] Treat explicit `missionId` as authoritative.
- [ ] Create a new mission only for explicit task-intake events.
- [ ] Preserve existing `AX_CANONICAL_STATE_V1`, 24-hour window, and verification behavior.
- [ ] Run mission synchronization only after canonical-state verification.
- [ ] Fail the workflow if mission persistence fails; never silently report success.
- [ ] Run context-sync regression checks.
- [ ] Commit: `feat: connect canonical context to mission memory`.

### Task 4: Durable workflow

**File:** `.github/workflows/ax-mission-ledger-sync.yml`.

- [ ] Support `workflow_dispatch`, scheduled reconciliation, and relevant file changes.
- [ ] Use the self-hosted runner and full-history checkout.
- [ ] Run ledger synchronization and integrity verification before commit.
- [ ] Emit `AX_MISSION_LEDGER=VERIFIED`, `AX_MISSION_COUNT`, `AX_MISSION_EVENT_COUNT`, and `AX_MISSION_RECOVERY=PASS`.
- [ ] Use a no-change path with no empty commit.
- [ ] Persist only intended files and never force-push.
- [ ] Reload the persisted JSON and verify latest mission/event/status/lastConversation after a fresh process boundary.
- [ ] Commit: `feat: add durable mission memory persistence workflow`.

### Task 5: No-loss proof

**Files:** tests + protocol.

- [ ] Create mission on channel A, update on channel B, reload from disk, and prove the same Mission ID resolves with channel-B as `lastConversation` while channel-A history remains.
- [ ] Persist a mission at `EXECUTING`, simulate process restart, and prove state survives.
- [ ] Replay ten identical events twice and prove exactly ten unique events remain.
- [ ] Prove `AX_CERTIFIED`/`DELIVERED` missions remain searchable.
- [ ] Run the complete Pester suite.
- [ ] Commit: `test: verify AX mission continuity and recovery`.

### Task 6: AX certification

- [ ] Add certification tests for schema, unique IDs, valid timestamps/statuses, projection consistency, and event ordering.
- [ ] Implement complete structured verifier.
- [ ] Run local PowerShell + Pester verification.
- [ ] Run the GitHub Actions workflow and require `AX_MISSION_LEDGER=VERIFIED` and `AX_MISSION_RECOVERY=PASS`.
- [ ] Commit: `cert: verify AX durable mission memory`.

## Final Verification Gate

Delivery to K is allowed only when evidence proves: Mission ID continuity; original request recovery; latest conversation recovery; full event history; process/restart recovery; idempotent replay; completed-mission retention; secret redaction; context-sync regression pass; GitHub Actions persistence pass; ledger verifier `verified=true`; and business-extension evaluation recorded. Only then is **AX CERTIFICATION: PASS** valid.
