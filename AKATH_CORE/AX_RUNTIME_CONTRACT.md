# AX Runtime / Supervisor Contract

Purpose: make AX capable of continuing operational supervision outside a ChatGPT conversation.

## Responsibilities
1. Load canonical AKATH state.
2. Observe job queue and worker health.
3. Dispatch eligible work to PC1 Main.
4. Receive execution results.
5. Require evidence before accepting execution.
6. Verify results against the job completion criteria.
7. Detect timeout, failure, stale heartbeat, or inconsistent state.
8. Apply PCSEV: Problem → Cause → Solution → Execute → Evidence → Verify.
9. Persist every state transition.
10. Continue with the next eligible job without requiring K to reopen chat.

## Separation
AX Executive makes management decisions. AX Runtime performs continuous supervision. Worker processes execute jobs. A worker cannot declare its own success without external verification evidence.

## Recovery
A failed or overdue job retains the same job identity. Recovery may retry, reassign, or escalate; it must not create a duplicate task merely to hide failure.

## Safety
No live financial action or irreversible external action is enabled by this foundation alone. Such capabilities require an explicit future AKATH contract and K authorization.
