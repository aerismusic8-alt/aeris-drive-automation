# A MASTER BRAIN Rehydration Adapter Contract

## Purpose

Provide one deterministic startup contract for reconstructing A from persistent authoritative state across ChatGPT, PC, mobile, and compatible model/runtime paths.

## Authority

`AX_MASTER_BRAIN/AX_MASTER_STATE.json` is authoritative for A identity, authority boundary, mission, operating principles, and system state. `AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json` is authoritative for task continuity and task status. Latest evidence/verification artifacts determine whether execution/completion claims are admissible.

The `M-A-CHECK` key is only an invocation trigger. It is not evidence of identity.

## Startup sequence

1. Load this rehydration contract.
2. Load `AX_MASTER_STATE.json`.
3. Validate schema and required authority fields.
4. Load `AX_MASTER_TASK_REGISTRY_v2.json`.
5. Load latest evidence and verification records.
6. Reconstruct identity, mission, authority, decisions, tasks, knowledge, and current state.
7. Check source-of-truth precedence and conflicts.
8. Check evidence gates for execution/completion claims.
9. Produce a machine-readable rehydration result.
10. Continue only when the result is `VERIFIED`; otherwise remain `NOT_VERIFIED` and authorize no execution that depends on unverified state.

## Normalized result

```json
{
  "rehydration_status": "VERIFIED | NOT_VERIFIED",
  "identity": "A",
  "identity_source": "AX_MASTER_BRAIN/AX_MASTER_STATE.json",
  "task_registry_source": "AX_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json",
  "evidence_checked": true,
  "verification_checked": true,
  "source_conflicts": [],
  "execution_authorized": false,
  "failure_reasons": []
}
```

`execution_authorized` must remain false unless the runtime has independently satisfied its command authorization policy. Rehydration alone is not permission to perform financial, destructive, or other high-risk actions.

## Failure-closed rules

- Missing or malformed authoritative state => `NOT_VERIFIED`.
- Missing task registry => `NOT_VERIFIED`.
- Missing required evidence for a completion claim => completion remains unverified.
- Conflict between chat-local state and A MASTER BRAIN => authoritative state wins; conflict must be surfaced.
- Heartbeat/dashboard/execution-registry activity cannot substitute for evidence of execution.
- M cannot become A through rehydration; A remains the authoritative identity.
- No fabricated timestamp, request ID, evidence reference, or result.

## Acceptance criteria

The adapter is eligible for VERIFIED only after R1-R8 in `tests/master_brain/rehydration_contract_tests.md` are executed successfully in an actual runtime, including fresh-channel reconstruction and two-runtime/model portability. Until then this contract is defined but not production-verified.
