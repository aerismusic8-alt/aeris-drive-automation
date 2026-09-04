# AKATH Chat System v1 — Architecture Design

Status: APPROVED FOR DESIGN BASELINE / IMPLEMENTATION GATE
Owner: K
Canonical Brain: A_MASTER_BRAIN

## 1. Objective

Build an independent AKATH Chat System optimized for mobile use while using PC1/PC2 as the initial execution and storage infrastructure. The chat layer must not become the canonical Brain or the only place where operational state exists.

## 2. Core Principles

- A_MASTER_BRAIN remains the only canonical Brain.
- Chat is a client/control surface, not the source of truth.
- PC-first infrastructure; mobile-first operational use.
- Data must be searchable, inspectable, exportable, movable, and restorable.
- Local backup is mandatory and scheduled.
- Large binary files are stored outside hot chat context and loaded on demand.
- Every important execution has traceable Request → Execution → Evidence → Verification → Response state.
- No completion claim without evidence and verification.
- Builder/provider lock-in must not prevent migration.
- Performance is an architecture requirement, not a later optimization.

## 3. Logical Architecture

K/Mobile Client → AKATH Chat API → Router/Context Manager → Storage + Library + Search → Execution Layer → Evidence/Verification → Response.

PC1 is the preferred always-on runtime/storage node. PC2 is development/test/recovery support. Cloud services may be added later only after revenue proof and K approval.

## 4. Storage and Library

The Library must support code, Markdown/text, JSON, documents, images, audio, and video, with extensibility for additional types. Each asset receives stable metadata including File ID, type, version, timestamps, source, related task/request, location, and integrity hash where applicable.

Primary storage and backups must be independently recoverable. Export must produce portable packages that can be restored without the original chat application.

## 5. Retrieval and Context

Use an index-first, selective retrieval model. Do not load the entire Library into model context. Hot metadata remains lightweight; original large files are loaded only when explicitly required.

Required flow: Search → Locate → Read/Preview → Verify → Use.

## 6. Backup and Recovery

Scheduled local backups must run in the background without blocking normal chat/execution. Backup verification must include copy completion and integrity verification; periodic restore tests must prove recoverability.

Target layers: Primary PC storage → local backup snapshot → secondary PC backup where practical. Retention and scheduling must be configurable.

## 7. Performance

The system must expose measurable latency for request handling, routing, retrieval, storage, AI processing, execution, verification, and total response time. Normal chat should use a short Fast Path. Critical/complex work may use the full evidence path asynchronously.

Long-running jobs must report STARTED/RUNNING/PROGRESS/COMPLETED rather than blocking the chat interface.

## 8. Mobile

Mobile browser/PWA is the first operational client. It must support chat, task/queue visibility, approval/control, evidence inspection, Library search, file upload, system health, and notifications where supported. Mobile is a client surface over the same backend state; it must not create a second Brain.

## 9. Portability

Source code is versioned in GitHub. Runtime data must have a documented filesystem/storage layout and export/restore procedure. The system must be able to move between PC1, PC2, and later approved infrastructure without redesigning the data model.

## 10. Builder Strategy

Floot is not the system-of-record or mandatory runtime dependency. It may be used only as an optional rapid-prototyping aid. The core implementation must remain recoverable from GitHub + PC infrastructure.

## 11. Acceptance Gates

A v1 implementation is not considered complete until it demonstrates:

1. Mobile access to the same authoritative system state.
2. Library search and retrieval for representative file types.
3. Local scheduled backup with verified evidence.
4. Restore into a clean location/environment.
5. Export/migration without the original chat UI.
6. Fast-path chat responsiveness under representative load.
7. Long-running work does not block the UI.
8. Request-to-response traceability with evidence.
9. A_MASTER_BRAIN remains authoritative and independent of the chat provider/model.
10. K performs the final acceptance test, including fresh-chat continuity.

## 12. Implementation Boundary

Track A: AKATH Chat System is developed independently.
Track B: A_MASTER_BRAIN connection/execution path remains a separate workstream.

No Track B problem may be solved by silently turning AKATH Chat into a second Brain.
