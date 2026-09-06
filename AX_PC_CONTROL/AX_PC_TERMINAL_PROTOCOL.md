# AX PC Terminal Protocol v1

## Request

A node polls `POST /pc/pull` with the configured `AX_PC_PULL_SECRET`.

The control record must contain a unique `request_id` and `task_id`. Terminal commands are explicit operations, not arbitrary network-accessible shells.

Supported operation families:

- health
- runner-status
- runner-start / runner-stop / runner-restart
- service-status / service-start / service-stop / service-restart
- task-status
- process-status
- git-status
- terminal-powershell

## Terminal command policy

`terminal-powershell` is an administrative execution capability and MUST be locally gated. The node implementation must:

1. Reject empty commands.
2. Enforce a maximum runtime.
3. Enforce a maximum captured output size.
4. Execute with an explicit working directory.
5. Return stdout, stderr and exit code.
6. Never log secrets or bearer tokens.
7. Return the node ID and command ID for audit correlation.

The implementation must not expose the Windows account password, runner registration token, or transport secret to AX output.

## Result

```json
{
  "request_id": "...",
  "task_id": "...",
  "node_id": "PC1-AUTONOMOUS-EXECUTOR",
  "executed": true,
  "verified": true,
  "exit_code": 0,
  "stdout": "...",
  "stderr": "",
  "duration_ms": 1234,
  "evidence": {
    "taskId": "...",
    "nodeId": "..."
  }
}
```

The control runtime remains the transport layer. The node is responsible for local authorization and actual Windows execution.
