# AX XM Execution Bridge

Isolated execution adapter for the XM Micro account.

## Boundary

- AX may request account state and trade execution through this bridge.
- The bridge must never accept deposit, withdrawal, or credential-export operations.
- Credentials must remain on the execution node/secret store; never commit or paste them into the repository.
- Every execution request must be idempotent and produce an auditable request/response record.
- Live trading must remain explicitly disabled until the execution node reports readiness and K has completed the live-enable step.

## Intended transport

XM supports MT4/MT5 Expert Advisors. The first implementation target is an MT5 Expert Advisor running on a dedicated Windows execution node, with a local authenticated command channel between AX and the EA. XM's official MT5 page confirms Expert Advisors are supported on MT5.

## State machine

`REQUESTED -> VALIDATED -> SENT -> BROKER_ACK -> VERIFIED`

Failure states are terminal for that request and must not be silently retried as a new order.

## Safety boundary

The bridge is an execution adapter, not the trading strategy. Strategy, risk, and capital-allocation decisions remain outside this adapter.

## Current status

`SCAFFOLDED_NOT_LIVE`
