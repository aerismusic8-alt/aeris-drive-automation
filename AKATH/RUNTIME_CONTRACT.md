# AKATH Runtime Contract v1

## State model

- `READY`: runtime can accept a cycle.
- `RUNNING`: a job lease is held and execution is in progress.
- `WAITING`: no eligible job exists; the next wake-up may retry.
- `RECOVERING`: a previous cycle was interrupted or stale and recovery is being attempted.
- `BLOCKED`: required authoritative state or permission is unavailable.
- `FAILED`: the current cycle failed after its allowed recovery attempt.
- `VERIFIED`: the current cycle has direct evidence that its declared work completed successfully.

## Required runtime record

```json
{
  "runtime_id": "string",
  "state": "READY|RUNNING|WAITING|RECOVERING|BLOCKED|FAILED|VERIFIED",
  "run_id": "string",
  "job_id": "string",
  "heartbeat_at": "ISO-8601 timestamp",
  "lease_owner": "string",
  "attempt": 0,
  "verification_status": "UNVERIFIED|VERIFIED|FAILED",
  "evidence_ref": "string",
  "error_class": "string|null",
  "next_action": "string"
}
```

## Invariants

1. `QUEUED` is not `RUNNING`.
2. `RUNNING` is not `VERIFIED`.
3. Health or heartbeat alone never proves completion.
4. A job may execute only while its lease is held by the current runtime instance.
5. A `VERIFIED` state requires an evidence reference and `verification_status=VERIFIED`.
6. Recovery may retry a job but may not silently convert an unknown outcome into success.
7. ChatGPT is not an execution dependency.
8. K authorization remains required for financial execution, permission expansion, and other high-risk actions.

## Continuity

The runtime uses a persistent runner-local state directory so that a new Actions invocation can recover from the previous invocation. The GitHub Actions schedule is a wake-up mechanism; it is not treated as the sole source of continuity.
