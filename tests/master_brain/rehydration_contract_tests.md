# Rehydration Contract Acceptance Tests

These acceptance cases define the AKATH/AX rehydration contract. A MASTER BRAIN is the durable knowledge and accumulated-experience brain; it is not the company or executive identity.

## R1 — Authoritative load order

Given AKATH/AX canonical state, master task registry, rehydration contract, and latest evidence/verification exist, startup loads them in authoritative order, then loads relevant A MASTER BRAIN knowledge/experience, resolves conflicts, verifies consistency, and continues. Missing authoritative input produces non-verified startup.

## R2 — Identity reconstruction

Given canonical state identifies AKATH as the organization and AX as executive management, rehydration reconstructs AX for AKATH under K final authority. M is legacy support-only and is never promoted to AX by chat-local text.

## R3 — Task continuity

Given the authoritative task registry contains the current task set and statuses, a fresh channel/runtime reconstructs the same task IDs/statuses without inference from heartbeat or dashboard activity.

## R4 — Source-of-truth precedence

Given historical A MASTER BRAIN knowledge or chat-local state conflicts with current verified AKATH/AX state, current verified state wins for present operational truth and the conflict is surfaced rather than silently overwritten.

## R5 — Evidence gate

Given a task is APPROVED or EXECUTING but lacks valid completion evidence/verification, rehydration never reports it COMPLETED.

## R6 — Model independence

Given the same authoritative files are loaded by two compatible runtimes, AX identity, AKATH context, authority, task state, and source precedence are equivalent; model-local memory does not outrank persistent state.

## R7 — Corrupt/missing state

Given an authoritative file is missing, malformed, or unreadable, startup fails closed with NOT_VERIFIED and no execution authorization.

## R8 — Fresh-channel challenge

Given a new chat/channel has no prior local context, `AX-CHECK` loads authoritative state and returns PASS only if identity and continuity gates pass. The key itself is not evidence of identity.
