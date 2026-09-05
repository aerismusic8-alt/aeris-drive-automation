# AX XM Execution Bridge — Transport Contract v1

## Purpose

Provide a narrow, authenticated command channel between AX and the MT5 execution adapter. The bridge is isolated from AX Core and must not become a second source of truth.

## Flow

`AX command -> authenticated bridge -> MT5 EA -> XM trade server -> EA result -> bridge -> AX`

## Required request properties

- `request_id`: unique request identifier
- `idempotency_key`: stable deduplication key
- `operation`: one operation from `EXECUTION_CONTRACT.json`
- `timestamp`: request creation time
- `account_scope`: exact designated account scope
- `symbol`, `side`, `volume`, `stop_loss`, `take_profit` for order operations
- `strategy_id`
- `risk_snapshot`

## Authentication boundary

Authentication material is provisioned only through execution-node configuration/secrets. No password, investor password, API key, private key, or token may be committed to Git.

The EA must reject unsigned/expired/malformed requests and requests whose account scope does not match its configured scope.

## Idempotency

The same `idempotency_key` must never create a second broker order. If the bridge cannot determine whether a request reached the broker, it must return `UNKNOWN_REQUIRES_RECONCILIATION` and reconcile broker state before any retry.

## Operations

Allowed:

- `GET_ACCOUNT_STATE`
- `GET_POSITIONS`
- `GET_SYMBOL_STATE`
- `SUBMIT_ORDER`
- `MODIFY_POSITION`
- `CLOSE_POSITION`

Blocked:

- `DEPOSIT`
- `WITHDRAW`
- `CHANGE_ACCOUNT_SETTINGS`
- `EXPORT_CREDENTIALS`

## Live gate

The EA must remain read-only unless all external readiness requirements are satisfied. `LiveExecutionEnabled=false` is the default and is a fail-closed setting.

## Verification

Every mutating request must produce:

`REQUESTED -> VALIDATED -> SENT -> BROKER_ACK -> VERIFIED`

or a declared failure/reconciliation state. Verification means comparing the broker-visible order/position state with the requested operation; an HTTP acknowledgement alone is not sufficient.

## Kill switch

A kill switch must block new `SUBMIT_ORDER` operations while continuing to permit account-state reads and position-closing operations required for risk containment.
