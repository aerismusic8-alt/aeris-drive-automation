# AX Node Protocol v1

Purpose: make PC1-MAIN and PC2-NIGHT durable execution nodes ("arms") of AX without coupling AX to a single desktop-control application.

## Node lifecycle

REGISTER -> HEARTBEAT -> READY -> DISPATCH -> ACK -> EXECUTE -> RESULT -> VERIFY -> WRITE_BACK.

Connection loss is not task completion. The canonical task state remains authoritative.

## Required node identity

- nodeId: stable identity (PC1-MAIN / PC2-NIGHT)
- role: PRIMARY / SECONDARY
- capabilities: execution / ai / control / browser
- lastHeartbeatAt
- status: ONLINE / OFFLINE / DEGRADED
- activeJob
- lastVerifiedJob

## Reconnect

A node reconnects using the same nodeId. It reports its last completed and active task. The controller reconciles against canonical state before dispatching another side-effecting job.

## Human intervention

A task that genuinely requires K is persisted as a durable pending state. Disconnecting the controller or node does not discard the request.

## Transport

v1 keeps transport pluggable:
- PC1 local process transport
- PC2 HTTP transport
- Browser specialists may use persistent Playwright MCP sessions.

The node protocol is the control plane; Desktop Commander is optional, not authoritative.
