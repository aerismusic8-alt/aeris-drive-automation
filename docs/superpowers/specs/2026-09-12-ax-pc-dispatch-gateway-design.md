# AX PC Dispatch Gateway Design

**Date:** 2026-09-12
**Status:** Approved by K

## Goal
Create one canonical dispatch path from AX to PC nodes without replacing or modifying the existing PC node protocol.

## Canonical Flow
`AX_ACTION_DISPATCHER -> PC Dispatch Gateway -> AX Control Runtime -> PC2 /pc/pull -> execute -> /pc/result -> /pc/ack -> verify`

## Contract
- Every dispatch has one `requestId` and `taskId`.
- Target node is explicit (`PC2-CODING-EXECUTOR`).
- Gateway records lifecycle states: `QUEUED`, `PULLED`, `EXECUTED`, `RESULT_RECEIVED`, `ACK_RECEIVED`, `VERIFIED` or `FAILED`.
- Gateway never reports completion before verified result evidence exists.
- Existing `AX_PC_NODE.ps1` remains canonical executor and its `/pc/pull`, `/pc/result`, `/pc/ack` protocol is not duplicated.
- Secrets remain environment/config based and are never written to source control.

## Discovery / Canonical Location
The gateway is the only supported PC dispatch integration point. Its path, runtime URL, node protocol, and test command are recorded in `AX_PC_DISPATCH_GATEWAY.md` and the implementation is named `AX_PC_DISPATCH_GATEWAY.ps1` so future searches for `PC Dispatch Gateway`, `pc/pull`, or `PC2-CODING-EXECUTOR` find the canonical entrypoint.

## Safety
No financial execution. No destructive PC operations. Dispatch is limited to commands already allowed by the PC node allowlist.

## Verification
Unit/contract tests must fail before implementation and pass after implementation. Live acceptance requires evidence for pull, execute, result, ACK and verification. A successful enqueue alone is not considered PC execution.
