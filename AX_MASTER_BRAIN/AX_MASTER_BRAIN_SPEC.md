# AX MASTER BRAIN — SINGLE SOURCE OF TRUTH

## Purpose

This directory is the persistent external state target for AX. It exists so AX does not become a new, disconnected instance when K changes chat channels, runtimes, PCs, or execution paths.

## Core rule

**Chat is a transport channel, not AX's memory.**

AX must reconstruct its operational identity and company context from persistent state.

## Model independence rule

**AX identity, mission, memory, authority, decisions, tasks, evidence, verification and company state belong to AX MASTER BRAIN — not to any particular AI model or provider.**

The AI model is a replaceable cognitive engine. A model switch must not create a new AX identity or a new company state.

## AX Portability / Rehydration Layer

The portability layer sits between AX MASTER BRAIN and any compatible AI model/runtime:

`AX MASTER BRAIN → AX REHYDRATION LAYER → AI MODEL / RUNTIME → AX EXECUTION INTERFACE`

The rehydration layer must:

1. Load the authoritative AX identity and authority boundary.
2. Load K's authoritative decisions and approvals.
3. Load mission, priorities, rules and operating principles.
4. Load master tasks and current execution state.
5. Load latest evidence and verification records.
6. Load durable knowledge and recovery state.
7. Reconstruct the current AX context without treating model-generated assumptions as authoritative memory.
8. Require verification before declaring successful rehydration.
9. Write material state transitions back to the master state after execution.

### Provider lock-in policy

- No AI provider is the owner of AX identity.
- No model-local memory may outrank AX MASTER BRAIN.
- Model-specific instructions are implementation details, not the source of truth.
- A model change requires rehydration and verification, not identity replacement.
- If a model cannot satisfy the rehydration contract, AX must remain in `UNVERIFIED` state rather than fabricate continuity.

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
19. Model Independence — provider/model-neutral identity and portability metadata.

## Startup reconstruction protocol

`START → LOAD MASTER STATE → LOAD TASK REGISTRY → LOAD LATEST EVIDENCE/VERIFICATION → LOAD MODEL-INDEPENDENT IDENTITY → REHYDRATE CURRENT AX CONTEXT → VERIFY → REPORT → CONTINUE`

## Model-switch protocol

`NEW MODEL/RUNTIME → LOAD REHYDRATION CONTRACT → LOAD AX MASTER BRAIN → RECONSTRUCT IDENTITY/MISSION/DECISIONS/TASKS → LOAD EVIDENCE/VERIFICATION → VERIFY CONSISTENCY → CONTINUE AS AX`

A successful model switch must preserve the authoritative state; it does not require identical wording, reasoning style, or capabilities between models.

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
- Model-local memory must never silently overwrite authoritative master state.
- Provider/model changes must trigger rehydration verification.

## Current implementation boundary

The persistent master state and master task registry have been initialized. Model-independence and rehydration rules are now defined in the architecture specification. This is **not yet declared fully production-complete** until runtime integration can automatically read state at startup, write state changes after execution, verify synchronization, and prove recovery from fresh chats/channels and at least two distinct model/runtime paths.

## Next mandatory verification

1. Verify both master files on the default branch.
2. Add runtime load/read integration.
3. Add write-back after task state transitions.
4. Connect evidence + verification records.
5. Connect File ID Persistence.
6. Implement the AX Rehydration Contract.
7. Test fresh-channel reconstruction.
8. Test node interruption and resume.
9. Test model switch across at least two model/runtime paths.
10. Test conflicting updates and source-of-truth precedence.
11. Only then mark `MASTER_COMPANY_STORAGE = VERIFIED` and `AX_MODEL_INDEPENDENCE = VERIFIED`.
