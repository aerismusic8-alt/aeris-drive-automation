# AX Control Hub API Contract v0.1

## Purpose

A stable authenticated transport interface for clients to inspect A MASTER BRAIN and submit validated commands to the existing execution layer.

## Common rules

- HTTPS is required for non-loopback access.
- All protected endpoints require authentication.
- Every request has a server-generated trusted timestamp and a client/server correlation ID.
- Command endpoints require an idempotency key.
- Responses expose authoritative status and evidence state separately.
- `health != execution` and `execution != completion`.

## GET /health

Authentication: optional for local health probe; required when sensitive diagnostics are included.

Response semantics:

```json
{
  "ok": true,
  "service": "AX_CONTROL_HUB",
  "health_status": "HEALTHY",
  "execution_status": "UNKNOWN"
}
```

`execution_status` MUST NOT be inferred from `health_status`.

## POST /auth/login

Request:

```json
{
  "username": "K",
  "password": "<provided over protected transport>"
}
```

Success returns an authenticated session. Failure returns a generic authentication error and does not reveal whether a username exists.

## POST /auth/logout

Revokes the current session.

## GET /state

Returns the current A MASTER BRAIN state summary. The Hub must not synthesize a competing state.

Minimum fields:

```json
{
  "source": "A_MASTER_BRAIN",
  "identity": "A",
  "authority": "K_FINAL_AUTHORITY",
  "master_status": "INITIALIZED_PENDING_VERIFICATION",
  "rehydration_status": "<verified runtime result>",
  "last_verified_evidence": "<reference or null>"
}
```

## GET /tasks

Returns the authoritative master task registry without upgrading status based on heartbeat, dashboard, or queue activity.

## POST /m-a-check

Starts the Identity/Rehydration Challenge.

Required checks:

1. Load master state.
2. Load authoritative task registry.
3. Load rehydration contract and latest evidence/verification.
4. Reconstruct A identity, mission, authority, tasks, and current state.
5. Check consistency and source-of-truth precedence.
6. Check model/runtime portability gates.
7. Return PASS only if all required gates have evidence.

A PASS must not mean that the calling model has become A. M remains M.

## POST /command

Only authorized actors may submit commands.

Request envelope:

```json
{
  "request_id": "server-or-client-correlation-id",
  "idempotency_key": "unique-for-command",
  "actor": "K",
  "command": "<allowlisted command>",
  "args": {},
  "requested_at": "trusted-runtime-timestamp"
}
```

The server validates schema, authorization, allowlist, idempotency, and current guardrails before enqueueing.

Response:

```json
{
  "request_id": "...",
  "status": "QUEUED",
  "evidence_status": "PENDING"
}
```

`QUEUED` is not `EXECUTING` and is not `COMPLETED`.

## GET /evidence/{request_id}

Returns execution evidence and verification for the correlated request.

Minimum semantics:

```json
{
  "request_id": "...",
  "execution_status": "<NOT_STARTED|EXECUTING|SUCCEEDED|FAILED|INTERRUPTED>",
  "evidence": [],
  "verification_status": "<PENDING|VERIFIED|REJECTED>"
}
```

A completion claim requires `verification_status=VERIFIED` plus sufficient evidence.

## Emergency stop

An emergency-stop operation must be a separately authorized command with explicit audit logging and verification. It must not be implemented as an unauthenticated hidden endpoint.

## Error contract

Use stable machine-readable error classes:

- `AUTH_REQUIRED`
- `AUTH_FAILED`
- `FORBIDDEN`
- `INVALID_REQUEST`
- `DUPLICATE_REQUEST`
- `GUARDRAIL_BLOCKED`
- `SOURCE_STATE_UNAVAILABLE`
- `EXECUTION_UNAVAILABLE`
- `EVIDENCE_UNAVAILABLE`
- `VERIFICATION_FAILED`

Errors must not expose secrets or internal credentials.
