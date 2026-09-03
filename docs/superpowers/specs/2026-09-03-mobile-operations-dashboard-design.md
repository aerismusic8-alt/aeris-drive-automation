# Mobile Operations Dashboard Design

**Date:** 2026-09-03

## Goal
Provide K with a mobile-first operations view that exposes AX/AERIS system state, the task queue, recent execution activity, and task-level verification without replacing the existing state/registry/heartbeat pipeline.

## Scope

### In scope
- Mobile-first dashboard view.
- Executive system status.
- Live task queue grouped by RUNNING, QUEUED, FAILED/NEED ACTION, and COMPLETED.
- Activity feed sourced from existing dashboard/state evidence.
- Task detail showing task, agent, action, result, verification, error/retry state, and timestamp when available.
- AI/runtime status for AX, M, external agents, runner, GitHub Actions, and external runtime evidence when represented by canonical state.
- Reuse of `dashboard/status.json` and `dashboard/ax-sync.json` as canonical dashboard synchronization inputs.
- Read-only monitoring in the first release; mutation controls are not added to the mobile UI.

### Out of scope
- Replacing the existing orchestrator/runtime.
- Replacing Apps Script or forcing it back into the execution path.
- Adding financial/trading execution controls.
- Changing repository/architecture component names.
- Building a separate task database when existing state/log sources can provide the data.

## Current Evidence
`dashboard/status.json` currently reports `system=ONLINE`, `overall=PASS`, `recovery=PASS`, `decision=PASS`, `dispatch=PASS`, `persistence=VERIFIED`, `runner=VERIFIED`, `mutation=ENABLED`, and selected task `AX-RECOVERED-005` with timestamp `2026-09-03T17:13:12.3482239+07:00`.

`dashboard/ax-sync.json` defines `AX_DASHBOARD_SYNC_V1`, points to `dashboard/status.json`, and reports `stateVerified=true`.

## Architecture

```text
K Mobile Browser
       |
       v
Mobile Operations Dashboard
       |
       +--> dashboard/status.json
       +--> dashboard/ax-sync.json
       +--> canonical task/state/event sources already produced by AERIS
       |
       v
Normalized read-only dashboard model
       |
       +--> Executive Overview
       +--> Task Queue
       +--> Activity Feed
       +--> Task Detail
       +--> System / AI Status
```

The dashboard is a presentation layer over existing canonical state. It must not become a second source of truth. If a field is unavailable, the UI must display an explicit unknown/unavailable state rather than infer success.

## Data Contract

The normalized dashboard model must expose:
- `systemStatus`: ONLINE/OFFLINE/UNKNOWN.
- `overall`: PASS/FAIL/UNKNOWN.
- `recovery`, `decision`, `dispatch`: PASS/FAIL/UNKNOWN.
- `persistence`, `runner`: VERIFIED/UNVERIFIED/UNKNOWN.
- `mutation`: ENABLED/DISABLED/UNKNOWN.
- `selectedTask`: string or null.
- `lastSyncAt`: timestamp or null.
- `syncVerified`: boolean.
- `tasks`: array of task records with id, status, agent, action, result, verification, error/retry, timestamp.
- `events`: array of timestamped activity records.
- `agents`: array of agent/runtime status records.

## UX
- Designed for a phone width first, while remaining usable on desktop.
- Top section answers “Is the system moving?” within one screen.
- Queue counts are prominent and filter the visible task list.
- Activity feed is newest-first.
- Task details are expandable/navigable without exposing raw implementation details by default.
- Refresh must show the source timestamp and verification state.
- Stale or missing data must be visibly labeled.

## Refresh and Failure Behavior
- Initial load reads the canonical dashboard files.
- Refresh may be manual and may use a lightweight periodic refresh if the hosting mechanism supports it.
- The UI must retain the last successfully parsed state while marking the source as stale when refresh fails.
- Invalid JSON or schema mismatch must produce a visible data-quality warning, not a fabricated dashboard state.

## Security
- First release is read-only.
- No secrets, API keys, OAuth tokens, or private credentials are embedded in dashboard assets.
- Existing repository permissions and runtime authentication remain authoritative.

## Acceptance Criteria
1. K can open the dashboard from a phone and immediately see overall system state.
2. The current task queue is visible with status grouping.
3. Recent system movement is visible as a timestamped activity feed.
4. A task can be opened to inspect available execution and verification fields.
5. Dashboard sync verification is visible.
6. Stale/invalid source data is explicitly indicated.
7. The dashboard consumes existing canonical state rather than creating a competing state store.
8. Automated tests cover parsing, normalization, status rendering logic, and stale/invalid data handling.
9. No mutation or financial execution action is exposed by the mobile UI.
