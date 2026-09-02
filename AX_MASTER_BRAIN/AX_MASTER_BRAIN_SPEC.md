# AX MASTER BRAIN — SINGLE SOURCE OF TRUTH

## Purpose

This directory is the persistent external state target for AX. It exists so AX does not become a new, disconnected instance when K changes chat channels, runtimes, PCs, or execution paths.

## Core rule

**Chat is a transport channel, not AX's memory.**

AX must reconstruct its operational identity and company context from persistent state.

## Required cognitive state

1. Identity — AX role, authority boundaries, operating identity.
2. Mission — company mission, current objectives and priorities.
3. K Decisions — authoritative decisions and approvals.
4. Master Tasks — every task from every channel.
5. Knowledge — durable knowledge required to operate the company.
6. Rules — PCSEV and execution/approval rules.
7. Architecture — AX/AERIS/system architecture and dependencies.
8. Execution State — queued, executing, blocked, completed.
9. Evidence — concrete proof of actions.
10. Verification — proof that claimed outcomes are true.
11. Lessons — failures, causes, fixes and learned constraints.
12. Revenue State — revenue missions and verified financial outcomes.
13. Financial Control — operating-cost and tool-budget control state.
14. Input/Limit State — capability, quota, API, subscription, machine and financial limits.
15. Recovery State — resume point after interruption or node failure.
16. Audit Timeline — trusted timestamps and provenance.
17. File/ID Mapping — durable identifiers for external resources.
18. Current AX State — compact state used to reconstruct AX at startup.

## Startup reconstruction protocol

`START → LOAD MASTER STATE → LOAD TASK REGISTRY → LOAD LATEST EVIDENCE/VERIFICATION → RECONSTRUCT CONTEXT → REPORT → CONTINUE`

## Integrity rules

- Single source of truth for authoritative company state.
- Derived dashboards must never outrank the master state.
- Heartbeat is health evidence only.
- Execution registry activity is not proof of business execution by itself.
- Every execution claim requires evidence.
- Every completion claim requires verification.
- No invented timestamps.
- Changes must be versioned and auditable.
- Sensitive credentials/secrets must never be stored in this brain.
- Access must follow least privilege.

## Current implementation boundary

The first persistent master state and master task registry have now been initialized in this repository. This is **not yet declared fully production-complete** until the runtime can automatically read this state at startup, write state changes after execution, verify synchronization, and prove recovery from a fresh chat/channel.

## Next mandatory verification

1. Verify both new files on the default branch.
2. Add runtime load/read integration.
3. Add write-back after task state transitions.
4. Connect evidence + verification records.
5. Connect File ID Persistence.
6. Test fresh-channel reconstruction.
7. Test node interruption and resume.
8. Test conflicting updates and source-of-truth precedence.
9. Only then mark `MASTER_COMPANY_STORAGE = VERIFIED`.
