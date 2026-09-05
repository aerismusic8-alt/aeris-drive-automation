# AX XM Execution Node Agent

This is the execution-node side of the XM bridge. It is intentionally separate from AX Core.

## Responsibilities

- Keep XM/MT5 credentials local to the execution node.
- Poll an authenticated AX bridge command endpoint for work.
- Enforce account scope and fail-closed execution gates before handing a command to MT5.
- Return broker-visible results and reconciliation evidence.
- Never accept deposit, withdrawal, account-settings, or credential-export commands.

## Transport

The deployed control runtime exposes an isolated XM namespace:

- `POST /xm/node/pull` — authenticated node polling.
- `POST /xm/node/result` — authenticated result/reconciliation write-back.
- `GET /xm/node/result/{request_id}` — authenticated result retrieval.
- `POST /xm/control/enqueue` — authenticated AX/control-plane command enqueue.
- `GET /xm/status` — sanitized public health/status only.

The queue is backed by a dedicated Durable Object (`AxXmExecutionQueue`) and is not the AX Gateway Inbox. This prevents XM execution state from becoming a second source of truth for normal AX tasks.

## Safety defaults

- `LIVE_EXECUTION_ENABLED=false`
- `KILL_SWITCH=true`
- `ACCOUNT_SCOPE=XM_MICRO_K_DESIGNATED_ACCOUNT`
- Missing/invalid authentication => reject.
- Unknown command state => reject.
- Ambiguous broker result => `UNKNOWN_REQUIRES_RECONCILIATION`; never blind-retry a mutating request.
- Duplicate `idempotency_key` => no second command is created.

## MT5 boundary

MT5 is the broker execution adapter. XM documents Expert Advisor support on MT5. MQL5 `WebRequest()` can send HTTP/HTTPS requests from an EA, but the bridge URL must be explicitly allowlisted in the MT5 Expert Advisors settings. `WebRequest()` is not available in the Strategy Tester, so transport testing and broker execution testing remain separate gates.

## Secrets

No broker password, investor password, API key, or bridge secret belongs in this repository. The execution node must provision `AX_BRIDGE_TOKEN`/the node authentication secret through its local secret store only.

## Current state

`TRANSPORT_READY_READ_ONLY` — authenticated queue transport is implemented, but no live broker execution is enabled by this layer. The node must still complete the handshake/readiness checklist before any live enablement.
