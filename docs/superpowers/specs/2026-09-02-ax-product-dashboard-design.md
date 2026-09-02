# AX Product Dashboard V1 Design

## Objective
Upgrade the existing AX Command Center into a mobile-first, product-ready V1 without disrupting active jobs. The dashboard remains read-only for execution control in this phase.

## Approved scope
- Mobile-first responsive UX.
- PWA install metadata and home-screen launch support.
- AX Command Center product identity.
- Preserve live runtime polling from `dashboard/status.json` and LIVE/STALE semantics.
- Preserve executive state, pipeline, AI network, activity, and evidence views.
- Modular front-end structure so future modules can be added without rebuilding V1.
- Future-ready module boundaries for Missions, AI Workers, Revenue, Projects, Automation, Evidence, Alerts, Analytics, Costs, and Customers.
- Notification integration point for important events; notification delivery must be verified before it is treated as successful.

## Non-goals
- No replacement of the existing execution engine.
- No simultaneous edits to active execution paths that could interfere with current jobs.
- No control actions from the dashboard in V1.
- No claim of physical-device installation success unless tested on a device/browser that supports it.

## Architecture
```text
AX Command Center
  UI / Mobile PWA
      |
      +-- Runtime State Adapter
      +-- Mission / Task modules
      +-- AI Worker modules
      +-- Verification / Evidence
      +-- Notification event interface
      +-- Future Revenue / Business modules
```

The runtime data adapter remains the source of truth. UI health labels must not invent state not supplied by runtime evidence.

## PWA
Add a web manifest, suitable icon assets, mobile theme metadata, and standalone launch behavior. The implementation should preserve normal browser access when installation is unavailable.

## Notification contract
Important events are classified at minimum as:
- JOB_COMPLETED
- AX_CERTIFIED
- ACTION_REQUIRED
- VERIFICATION_FAILED
- SYSTEM_CRITICAL
- BUSINESS_EVENT

Notification success requires: event detected -> classified -> notification dispatched -> delivery/ack evidence where supported -> AX verification.

## Success gate
`EXECUTE -> OUTPUT -> VERIFY -> EVIDENCE -> AX CERTIFICATION PASS -> DELIVER TO K`

`NOT VERIFIED != SUCCESS`.

## Business extension
The UI should expose a product identity and modular navigation foundation that can later support commercial AX offerings. V1 prioritizes usability and reliable runtime visibility over feature volume.

## Acceptance criteria
1. Dashboard remains functional using the existing runtime state source.
2. Mobile layout is usable at narrow viewport widths.
3. PWA metadata is valid and home-screen installation is supported where the browser permits it.
4. Existing LIVE/STALE detection remains intact.
5. Existing evidence view remains intact.
6. Active execution jobs are not modified or stopped by dashboard work.
7. Notification events have a defined integration path and are verified before certification.
8. AX performs final certification before delivery to K.
