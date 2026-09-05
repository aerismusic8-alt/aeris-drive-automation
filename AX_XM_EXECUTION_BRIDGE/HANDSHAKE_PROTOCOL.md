# AX XM Execution Bridge — Handshake Protocol v1

## Phase 0: discovery

The execution node reports MT5 terminal connectivity, account login, account currency, balance/equity, expert-trading permission, and the configured `account_scope`.

## Phase 1: identity

The bridge must match the configured designated XM account. A mismatch is a hard failure. Account credentials are never transmitted to AX and never stored in Git.

## Phase 2: capability

The node must prove:

- MT5 terminal connected to the trade server
- automated trading permitted at terminal level
- EA trading permitted
- account permits Expert Advisor trading
- requested symbol exists and is tradable
- symbol volume min/max/step and filling mode are known

## Phase 3: command authentication

Only authenticated requests with valid timestamps, unique `request_id`, and stable `idempotency_key` are accepted. Expired, replayed, malformed, or wrong-scope requests are rejected.

## Phase 4: read-only proof

Before any mutation, AX must receive a successful account-state and positions response and record the exact account scope and terminal state.

## Phase 5: execution proof

A test order path must be demonstrated in an explicitly authorized test environment before live execution is enabled. Live enablement is a separate state transition and is fail-closed by default.

## Phase 6: reconciliation

After every mutation, the EA reports broker result data and AX reconciles the broker-visible position/order state. If the result is ambiguous, state becomes `UNKNOWN_REQUIRES_RECONCILIATION`; no blind retry is permitted.

## Kill switch

Kill switch blocks new entries. It must not prevent reads or risk-containment actions such as closing an already-open position when explicitly commanded by the risk engine.
