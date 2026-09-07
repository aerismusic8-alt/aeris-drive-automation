# AX XM Real-Money Monitoring Contract

## Objective

Keep the designated XM/MT5 real-money account continuously observable without enabling live order execution.

## Required telemetry

Each heartbeat from the MT5 EA must report:

- account scope and login
- currency
- balance
- equity
- margin
- free margin
- floating P/L
- open position count
- terminal connection state
- broker trading permission state
- expert trading permission state
- live execution flag
- kill-switch state
- monotonically increasing heartbeat sequence

## Health states

- `HEALTHY`: authenticated heartbeat received within the configured freshness window and terminal connection is true.
- `DEGRADED`: heartbeat transport or broker/terminal state is abnormal but recent telemetry exists.
- `OFFLINE`: heartbeat is older than the freshness window or no authenticated heartbeat has ever been received.

`OFFLINE` is never interpreted as `HEALTHY`.

## Recovery rule

A monitoring failure is a PCSEV incident:

`PROBLEM -> CAUSE -> SOLUTION -> EXECUTE -> VERIFY`

Recovery may restart/reconnect permitted infrastructure, but must not silently enable live trading.

## Execution boundary

This contract does not authorize deposits, withdrawals, credential export, or live trading. The current bridge remains fail-closed until the separately verified live-enable gate is completed.

## Acceptance criteria

1. MT5 EA emits a heartbeat every configured interval.
2. Heartbeat contains the required financial and connection telemetry.
3. Runtime can distinguish fresh, stale, and absent telemetry.
4. Loss of heartbeat becomes an explicit incident.
5. Recovery is verified by a fresh heartbeat.
6. No monitoring recovery step can enable live order execution.
