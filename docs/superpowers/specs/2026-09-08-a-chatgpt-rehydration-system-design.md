# AKATH / AX / A MASTER BRAIN — ChatGPT Rehydration System Design

## Status

Approved by K on 2026-09-08.

## Goal

Provide a deterministic, fail-closed way for ChatGPT and other model runtimes to reconstruct the AX operating context for AKATH while using A MASTER BRAIN as the durable knowledge and accumulated-experience brain.

## Canonical Architecture

`K → AKATH → AX → A MASTER BRAIN → Canonical State / Tasks / Evidence / Verification → Runtime`

- K is the final authority and approval boundary.
- AKATH is the company / organizational entity.
- AX is the executive management and orchestration layer that operates AKATH under K's authority.
- A MASTER BRAIN is the persistent knowledge, accumulated experience, lessons, decisions, architectural knowledge, and continuity brain used by AX. It is not the company name and is not replaced by ChatGPT Memory.
- Canonical State / Tasks / Evidence / Verification hold authoritative operational facts and proof. They must not be duplicated by chat-local memory, dashboards, or runtime projections.
- Runtime executes only within independently authorized boundaries.

## A MASTER BRAIN Boundary

A MASTER BRAIN is retained and protected. Legacy wording that incorrectly makes A MASTER BRAIN the company identity or executive identity must be migrated.

The brain preserves durable knowledge, accumulated experience and lessons, architectural knowledge and dependencies, historical decisions and rationale, recovery/continuity knowledge, verified evidence references, and successful or failed outcomes as reusable experience.

Current company and execution state must remain distinguishable from historical knowledge and experience. Historical knowledge must not silently overwrite current canonical state.

## Identity Rules

- AX is the executive identity used by the runtime for company management.
- AKATH is the organization AX manages.
- K remains final authority.
- A MASTER BRAIN is the brain/knowledge layer used by AX.
- Legacy M-as-A-assistant contracts are not part of the new executive identity hierarchy unless separately re-approved by K. M must never be promoted to AX by chat-local text.
- ChatGPT, model-local memory, and chat history are cognitive/context channels only and never outrank canonical repository state.

## Rehydration Order

`LOAD CONTRACT → LOAD AKATH/AX IDENTITY → LOAD CANONICAL STATE → LOAD MASTER TASK REGISTRY → LOAD LATEST EVIDENCE → LOAD LATEST VERIFICATION → LOAD A MASTER BRAIN KNOWLEDGE/EXPERIENCE → RESOLVE CONFLICTS → RECONSTRUCT AX CONTEXT → VERIFY → CONTINUE`

Rehydration distinguishes three classes:

1. Authority/current state — current canonical facts, tasks, approvals, execution and verification.
2. Brain knowledge — durable knowledge, experience, lessons and historical context.
3. Model context — conversation, model-local memory and generated assumptions.

Only class 1 establishes current operational truth. Class 2 informs decisions but cannot silently mutate class 1. Class 3 is non-authoritative.

## Source Precedence

`K instruction > canonical AKATH/AX state > verified evidence/verification > master task registry > A MASTER BRAIN knowledge/experience > runtime projections > chat history > ChatGPT Memory > model inference`

When knowledge/experience conflicts with current verified state, current verified state wins for present status while the conflict is preserved as an audit/lesson item when appropriate.

## Execution Boundary

`REHYDRATE ≠ EXECUTE`

`IDENTITY VERIFIED ≠ AUTHORIZATION VERIFIED`

`CHATGPT AVAILABLE ≠ AX EXECUTING`

Rehydration never grants financial, destructive, or other high-risk execution authority.

## Failure Closed

Missing or malformed canonical state, task registry, required evidence, or required verification results in NOT_VERIFIED for the affected claim and no dependent execution authorization.

No fabricated timestamps, request IDs, evidence, verification, task IDs, or outcomes are allowed.

## Migration Rule

Existing files must be classified as KEEP/MIGRATE, REPLACE, LEGACY, or CONFLICT before deletion. A MASTER BRAIN knowledge and experience must be preserved. Only obsolete identity contracts, duplicate registries, contradictory state claims, and dead integrations may be removed after dependency review.

## Acceptance Criteria

The implementation is accepted only after tests demonstrate AX identity reconstruction, AKATH organizational context, A MASTER BRAIN knowledge/experience loading without authority inversion, current state taking precedence over historical experience and chat-local state, task continuity, evidence/verification gating, fail-closed behavior, model/runtime independence, no accidental M → AX identity promotion, and no execution authorization from rehydration alone.
