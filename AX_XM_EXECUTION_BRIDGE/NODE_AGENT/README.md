# AX XM Execution Node Agent

This is the execution-node side of the XM bridge. It is intentionally separate from AX Core.

## Responsibilities

- Keep XM/MT5 credentials local to the execution node.
- Poll an authenticated AX bridge command endpoint for work.
- Enforce account scope and fail-closed execution gates before handing a command to MT5.
- Return broker-visible results and reconciliation evidence.
- Never accept deposit, withdrawal, account-settings, or credential-export commands.

## Safety defaults

- `LIVE_EXECUTION_ENABLED=false`
- `KILL_SWITCH=true`
- `ACCOUNT_SCOPE=XM_MICRO_K_DESIGNATED_ACCOUNT`
- Missing/invalid authentication => reject.
- Unknown command state => reject.
- Ambiguous broker result => `UNKNOWN_REQUIRES_RECONCILIATION`; never blind-retry a mutating request.

## Transport boundary

The node agent is designed to poll a remote HTTPS bridge. MT5 can communicate with an HTTPS endpoint using MQL5 `WebRequest`, but the MT5 terminal must explicitly allow the endpoint URL. The endpoint must therefore be fixed and allowlisted during node setup.

No broker password, investor password, API key, or bridge secret belongs in this repository.

## Current state

`SCAFFOLD_ONLY` — no live broker command is enabled by this file alone.
