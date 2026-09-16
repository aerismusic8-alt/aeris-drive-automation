# AX Canonical Execution Loop

Status: FOUNDATION_DEFINED / NOT_YET_EXECUTING

The first executable path is intentionally singular:

1. AX creates one canonical job.
2. Job receives trusted start/deadline data.
3. AX Runtime marks it DISPATCHABLE.
4. Dispatcher sends it to PC1 Main.
5. Specialist on PC1 selects the executor for the job capability.
6. Executor performs the work.
7. Worker returns result plus evidence.
8. AX Runtime verifies evidence against acceptance criteria.
9. PASS → COMPLETE and persist outcome.
10. FAIL → PCSEV analysis and recovery using the same job identity.
11. OVERDUE → root-cause analysis before any deadline revision.
12. After verified completion, AX Runtime selects the next eligible job.

## First acceptance test
One non-destructive test job must complete the full path:
AX → Runtime → Dispatcher → PC1 → Execute → Evidence → Verify → COMPLETE.

No additional specialist, mission, dashboard, revenue workflow, or parallel execution path is required until this acceptance test passes.
