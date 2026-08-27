# AX PC2 Worker v2

## Objective
Convert PC2 from IDLE persistence into a real AERIS execution worker.

## Flow
AERIS Queue -> Job Pull -> Claim -> Execute -> Verify -> Result Report -> Retry -> Resume

## Safety
- Live financial execution remains DISABLED.
- A job must be claimed before execution.
- A claim must identify the worker.
- Execution is not COMPLETED unless verification passes.
- Failed reporting must never be treated as successful execution.
- Restart recovery must preserve the current job and attempt state.

## Required Node API
- GET `?action=worker_pull&workerId=WORKER_ID`
- POST `{action:"worker_claim", workerId, jobId, claimToken}`
- POST `{action:"worker_heartbeat", workerId, jobId}`
- POST `{action:"worker_result", workerId, jobId, status, result, error, verified, executed}`

## Pull response
`{success:true, available:true, job:{jobId,command,content,...}}`

When no job exists: `{success:true, available:false}`.

## Claim rules
Only PENDING jobs may be claimed. Claiming must be atomic and verified by read-back. A second worker must receive a claim rejection rather than executing the same job.

## Result rules
COMPLETED requires `verified=true` and `executed=true`. BLOCKED is used for policy-denied commands. FAILED is used after retry exhaustion. No result may claim live financial execution.

## Retry
Default maximum attempts: 3. Retry only transient execution/reporting failures. Preserve the same job ID across attempts.

## Persistence
Worker state must be written locally before and after every state transition. On restart, recover CLAIMED/EXECUTING state and reconcile it with the queue before executing again.

## E2E gate
Full Autonomous Execution remains NOT VERIFIED until real evidence exists for:
1. queue job created;
2. PC2 pull;
3. claim accepted;
4. local execution performed;
5. verification passed;
6. result written to AERIS Queue;
7. duplicate execution prevented;
8. restart/resume verified.
