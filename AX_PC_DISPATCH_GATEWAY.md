# AX PC Dispatch Gateway — Canonical

Canonical PC execution entrypoint: `AX_PC_DISPATCH_GATEWAY.ps1`

Canonical target node: `PC2-CODING-EXECUTOR`

Canonical runtime: `https://ax-control-runtime.aerismusic8.workers.dev`

Canonical lifecycle:

`QUEUED -> PULLED -> EXECUTED -> RESULT_RECEIVED -> ACK_RECEIVED -> VERIFIED`

Completion is never claimed from queue acceptance alone.

## Search keys

Use any of these terms to locate the implementation:

- `AX_PC_DISPATCH_GATEWAY`
- `PC Dispatch Gateway`
- `PC2-CODING-EXECUTOR`
- `pc/pull`
- `pc/result`
- `pc/ack`

## Safe dispatch example

```powershell
.\AX_PC_DISPATCH_GATEWAY.ps1 -TaskId 'PC2-CANONICAL-TEST' -Command health -NodeId 'PC2-CODING-EXECUTOR' -Enqueue
```

The gateway only reports `accepted=true` / `QUEUED` at enqueue time. The live PC2 node must subsequently pull, execute, post result, ACK, and provide verification evidence before the task can be marked complete.

The existing `AX_PC_CONTROL/AX_PC_NODE.ps1` remains the executor authority. Its protocol is not duplicated here.
