# AKATH Foundation + Autonomous AX Runtime Build Plan

Goal: build AKATH from clean start and prove one autonomous execution loop before adding other capabilities.

Architecture: AX Executive manages intent and decisions. AX Runtime/Supervisor persists state, dispatches work, monitors execution, validates evidence, and performs recovery. PC1 Main is the first execution node; Specialist is the executor-selection layer.

Canonical state: `AKATH_CORE/CANONICAL_TASK_REGISTRY.json`.
Historical A MASTER BRAIN task records are knowledge/history only and do not create current work.

## Global constraints
- One canonical branch: `main`.
- No duplicate task registries.
- No historical task restoration.
- Every job has a deadline and completion criteria.
- OVERDUE requires cause analysis and corrective action.
- DONE requires result + evidence + verification.
- No live financial or irreversible external action in the foundation test.

## Phase 1 — Foundation
- [x] Create clean AKATH foundation contract.
- [x] Define AX Runtime/Supervisor responsibilities.
- [x] Define canonical execution loop.
- [x] Define time governance.
- [x] Establish empty canonical task registry.

## Phase 2 — Runtime
- [ ] Implement persistent AX Runtime/Supervisor on the execution environment.
- [ ] Implement canonical job lifecycle and state transitions.
- [ ] Implement deadline monitoring and PCSEV recovery.
- [ ] Implement evidence and verification persistence.

## Phase 3 — PC1 execution
- [ ] Register PC1 Main as an execution worker.
- [ ] Implement dispatcher → PC1 protocol.
- [ ] Implement Specialist capability routing.
- [ ] Execute one non-destructive E2E test.

## Phase 4 — Acceptance
- [ ] AX creates job.
- [ ] Runtime dispatches job.
- [ ] PC1 executes.
- [ ] Evidence is returned.
- [ ] Verification passes.
- [ ] Job becomes DONE.
- [ ] Runtime autonomously selects the next eligible job.

The foundation is not considered operational until Phase 4 passes with evidence.
