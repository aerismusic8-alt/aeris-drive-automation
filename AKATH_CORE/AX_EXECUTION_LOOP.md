# AX Canonical Execution Loop

Status: E2E_VERIFIED / AUTONOMOUS_CONTINUATION_ENABLED

The canonical execution path is singular:

1. AX Runtime loads the canonical task registry.
2. If no task is pending and the autonomous plan has remaining approved non-destructive work, the runtime creates exactly one next task with a deadline.
3. Runtime claims the task as EXECUTING.
4. Dispatcher sends it to PC1 Main.
5. Specialist routing selects the executor from the job capability.
6. Executor performs the bounded non-destructive work.
7. Worker returns result plus evidence.
8. AX Runtime verifies evidence against acceptance criteria.
9. PASS → COMPLETE/DONE and persist outcome.
10. FAIL → PCSEV analysis and recovery using the same job identity.
11. OVERDUE → root-cause analysis before any deadline revision.
12. After verified completion, the runtime may plan exactly one next eligible autonomous task.

## Specialist Set

- `PC1_MAIN_SPECIALIST` — default execution capability.
- `PC1_SELF_CHECK_SPECIALIST` — deterministic runtime/evidence self-check capability.
- `PC1_RECOVERY_SPECIALIST` — deterministic recovery-path capability.

Unknown capabilities are rejected rather than silently falling back to an unintended executor. Missing capability uses the safe default execution specialist.

## Autonomous continuation rule

The runtime does not wait for a new chat message when the current canonical task is DONE. It may create only the next task explicitly present in the bounded autonomous plan. Each generated task receives its own deadline, milestones, completion criteria, evidence, and verification requirement.

Autonomous continuation stops when the bounded plan is exhausted or when a task requires K's authority, an external credential, an irreversible action, or a missing execution capability.

## Acceptance gate

The first E2E acceptance path is:
AX → Runtime → Dispatcher → PC1 → Specialist → Execute → Evidence → Verify → DONE.

That E2E path has been verified on PC1. The next phase is Specialist Set execution and bounded autonomous continuation. No revenue, financial, irreversible, or unrelated workflow is introduced by this foundation.
