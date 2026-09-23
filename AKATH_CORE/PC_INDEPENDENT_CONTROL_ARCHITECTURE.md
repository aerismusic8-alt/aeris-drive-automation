# PC1 / PC2 INDEPENDENT CONTROL ARCHITECTURE

## Purpose

AERIS uses two independent local Control planes:

- PC1 CONTROL → PC1 (DESKTOP-RGK6JKB)
- PC2 CONTROL → PC2 (DESKTOP-M9M4818)

They share AX / A MASTER BRAIN / canonical task knowledge, but each machine executes through its own local Control and Runtime.

## Required components per node

1. Control Daemon
2. Desktop Observer
3. Task Executor
4. Evidence Collector
5. Verifier
6. Local Recovery

## Independence requirements

1. PC1 can continue local execution without PC2.
2. PC2 can continue local execution without PC1.
3. Failure of one node does not imply failure of the other.
4. Shared brain/state coordinates knowledge and policy; it does not merge local execution.
5. Desktop Commander is an optional adapter, not the primary runtime dependency.
6. Every execution and completion claim requires node-specific evidence and verification.

## Execution contract

Observe → Decide/Receive Task → Dispatch → Execute → Evidence → Verify → Record → Recover/Continue.

For Offers:

Discover → Read Details → Feasibility → Start → Execute → Verify Reward → Record Evidence → Next.

Impossible/unsupported work is recorded as SKIPPED + REASON, then the node continues.

## Current node identities

| Control | Node | Machine |
|---|---|---|
| PC1 CONTROL | PC1 | DESKTOP-RGK6JKB |
| PC2 CONTROL | PC2 | DESKTOP-M9M4818 |

DESKTOP-O0AUKHG is not a current AERIS node.
