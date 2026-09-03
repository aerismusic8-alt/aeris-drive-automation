# AX Control Hub API Contract v0.2

## Purpose

A stable authenticated transport interface for clients to inspect A MASTER BRAIN and submit validated inputs/tasks to the existing execution layer.

## Common rules

- HTTPS is required for non-loopback access.
- All protected endpoints require authentication.
- Every request has a server-generated trusted timestamp and a client/server correlation ID.
- Command endpoints require an idempotency key.
- Responses expose authoritative status and evidence state separately.
- `health != execution` and `execution != completion`.
- The communication gateway is a transport layer, not a source of truth.
- A MASTER BRAIN remains authoritative for identity, mission, tasks, state, evidence, and verification.

## GET /health

Authentication: optional for local health probe; required when sensitive diagnostics are included.

`execution_status` MUST NOT be inferred from `health_status`.

## POST /auth/login

Credentials are sent only over protected transport. Success returns a short-lived authenticated session token. Failure returns a generic authentication error.

## POST /auth/logout

Revokes the current session.

## GET /state

Returns the current A MASTER BRAIN state summary. The Hub must not synthesize a competing state.

## GET /tasks

Returns the authoritative master task registry without upgrading status based on heartbeat, dashboard, or queue activity.

## POST /m-a-check

Starts the Identity/Rehydration Challenge. A PASS verifies rehydration; it does not make the calling model A. M remains M.

## Gateway input

### POST /gateway/input

Protected route for GPT, PC, Mobile, or system clients.

Request example:

```json
{
  "request_id": null,
  "task_id": null,
  "source_channel": "MOBILE",
  "content_type": "text",
  "content": "M-A-CHECK",
  "attachments": [],
  "requested_at": null
}
```

Supported `content_type`: `text`, `file`, `image`, `event`, `command`.

Attachments are metadata references only:

```json
{
  "attachment_id": "stable-id",
  "kind": "image",
  "name": "cover.png",
  "media_type": "image/png",
  "reference": "controlled-storage-reference"
}
```

Raw binary/data fields must not be written into A MASTER BRAIN state.

Response contains a generated `request_id` and `task_id`, `rehydration_status`, `evidence_status`, and `verification_status`.

## Gateway state and task views

### GET /gateway/state
Returns A MASTER BRAIN state through the gateway.

### GET /gateway/tasks
Returns the authoritative task registry through the gateway.

### POST /gateway/m-a-check
Runs M-A-CHECK through the gateway and returns the verified A identity context without impersonating A.

### GET /gateway/evidence/{request_id}
Returns evidence from the existing CommandLedger for the correlated request.

## POST /command

Only authorized actors may submit commands. The existing local allowlist remains authoritative; live financial execution remains disabled.

`QUEUED` is not `EXECUTING` and is not `COMPLETED`.

## GET /evidence/{request_id}

Returns execution evidence and verification for the correlated request. A completion claim requires `verification_status=VERIFIED` plus sufficient evidence.

## Operations Hub

`GET /operations` serves the responsive browser surface for PC and Mobile. The browser uses `/auth/login` and the `/gateway/*` routes; it does not maintain a second master state.

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
- `RAW_BINARY_NOT_ALLOWED`

Errors must not expose secrets or internal credentials.
