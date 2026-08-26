# AX Autonomous Executive Loop

Status: FOUNDATION

## Purpose
AX continuously observes system state, evaluates priorities, plans the next permitted action, executes through an available executor, verifies the result, records an audit event, and schedules the next cycle.

## Control Loop
1. OBSERVE — collect verified runtime, workflow, queue, AERIS and AICS state.
2. ANALYZE — identify blockers, stale work, failures, priorities and opportunities.
3. PLAN — produce the smallest next actionable step and fallback.
4. PERMISSION — enforce scope, risk and K approval gates.
5. EXECUTE — dispatch only permitted low-risk actions to an executor.
6. VERIFY — require concrete execution evidence before changing state to completed.
7. AUDIT — record decision, action, evidence, result and next state.
8. REPLAN — continue until COMPLETED, BLOCKED, WAITING_K, or a background wait is required.

## Safety Gates
- No live-money trading is enabled by this loop.
- No financial transaction is executed without an explicit K-approved permission path.
- No task is marked complete without verification evidence.
- Secrets are never written to repository files or logs.
- Existing AERIS Runtime components are preserved unless a change is required and verified.

## Current Business Engines
- AERIS Company Engine: planned next layer for research, artist development, production, release, distribution, analytics and revenue optimization.
- AICS Investment Engine: planned next layer for market observation, paper decisions, risk checks, performance analysis and later controlled live execution.

## State Contract
Allowed executive states:
- ACTIVE
- QUEUED
- BLOCKED
- PAUSED
- WAITING_K
- COMPLETED

Every cycle must leave a durable record containing timestamp, cycle id, objective, decision, action, verification result and next state.
