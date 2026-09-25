# PC1 Autonomous Runtime / Brain / Control

## Canonical execution path

PC1 runs:

PC → Runtime → Brain → Control → Vision / OS / Browser → Evidence → Verify → Write-back

AX is the executive/orchestration and upgrade layer. A MASTER BRAIN provides durable knowledge and verified lessons. The local Brain is the decision layer; Control is the execution layer.

## Ownership

- K: final authority and approval boundary.
- AX: architecture, orchestration, Brain upgrades, research direction, and canonical coordination.
- A MASTER BRAIN: durable knowledge, procedures, lessons, and recovery knowledge.
- PC1 Runtime: persistent local supervisor and heartbeat.
- PC1 Brain: local autonomous decision/recovery loop.
- PC1 Control: executes bounded Brain directives.
- Desktop Vision: observes the real desktop/browser and produces evidence.
- Verify: independently confirms effects before completion is recorded.

## Runtime requirements

1. Node.js 20+.
2. Windows Task Scheduler autostart.
3. Persistent heartbeat.
4. Brain and Control processes recoverable without ChatGPT.
5. State/evidence persisted locally and synchronized to canonical state.

The runtime must continue after the ChatGPT session closes.

## Autonomous loop

REGISTER → HEARTBEAT → READY → RECONCILE → BRAIN DECISION → CONTROL DISPATCH → EXECUTE → EVIDENCE → VERIFY → WRITE-BACK → NEXT

On failure:

INSPECT → RESEARCH/KNOWLEDGE → ROOT CAUSE → RECOVER/FIX → RUN → EVIDENCE → VERIFY → WRITE-BACK

No unverified success is accepted.

## PC1 identity

- nodeId: PC1-MAIN
- machine: DESKTOP-RGK6JKB
- role: PRIMARY

## Verification gate

The autonomous gate is PASS only when, with the ChatGPT session closed, PC1 independently maintains a changing heartbeat and completes a legitimate non-destructive job with persisted evidence and independent verification.

A Git commit or configuration file alone is not runtime proof.

## Desktop Commander

Desktop Commander is optional. It is not the authority, scheduler, Brain, or canonical state store.

## Recovery

If PC1 reconnects after interruption, it must report its local state and reconcile against canonical state before performing another side-effecting action.

## Current target

Bring the deployed PC1 runtime into conformance with the Brain → Control architecture, then verify:

Runtime ONLINE → Brain ONLINE → Control ONLINE → Vision LIVE → Evidence changing → Verify PASS → Write-back changing.
