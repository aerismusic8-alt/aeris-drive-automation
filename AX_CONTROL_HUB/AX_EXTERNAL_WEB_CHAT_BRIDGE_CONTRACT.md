# AX External Web Chat Bridge Contract

## Flow
`WEB browser -> /web/input -> AX_GATEWAY_INBOX -> /pc/pull -> Local Hub /gateway/input -> /pc/result -> /web/result/{request_id}`

## Security
- `/web/*` uses short-lived web session tokens issued from the existing mobile ingress secret.
- `/pc/*` continues to use `AX_PC_PULL_SECRET` only.
- Local Hub credentials remain on the controlled PC bridge.
- No GitHub credential is accepted by the web surface.

## Result contract
`/pc/result` stores the Local Hub response correlated by `request_id` and `task_id`.
The bridge must store the result before acknowledging the transport item.
If result storage fails, the bridge must not ACK the item.
