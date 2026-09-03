# A Communication Gateway Design

**Date:** 2026-09-03
**Status:** APPROVED FOR IMPLEMENTATION
**Authority:** K_FINAL_AUTHORITY

## Goal
Provide one model/provider-independent transport layer through which GPT, PC, and Mobile can submit text, images, files, and commands to A Master Brain and receive authoritative state/results without making the transport layer a competing source of truth.

## Architecture

`GPT / PC / Mobile -> A Communication Gateway -> A MASTER BRAIN -> Task/Execution Layer -> Evidence -> A MASTER BRAIN -> Gateway -> Client`

A Master Brain remains authoritative for identity, mission, decisions, tasks, knowledge, state, and evidence. The gateway stores only transient request/correlation metadata required to transport a request and enforce protocol validation.

## Input Contract

Inputs may include:
- text messages
- structured commands
- images or other visual media references
- documents and files
- machine-generated events
- task result callbacks

Binary payloads should be referenced or streamed through an approved storage mechanism rather than embedded into the A Master Brain state document.

Every accepted request receives:
- `requestId`
- `taskId` when work is task-bound
- trusted server timestamp
- source channel
- content type
- authorization context

## A Rehydration Contract

For an A operation, the gateway must request or invoke rehydration before presenting authoritative A state:

1. Load A Master Brain state.
2. Load authoritative master task registry.
3. Load rehydration contract.
4. Load latest admissible evidence/verification.
5. Reconstruct A identity, mission, authority, tasks, and current state.
6. Check source-of-truth precedence and conflicts.
7. Return `rehydration_status=VERIFIED` only when required gates pass.

A gateway PASS never means the calling model has become A. M remains M and A remains the authoritative identity represented by persistent state.

## Task Contract

A request that creates or continues work must preserve:

`requestId -> taskId -> execution state -> evidence -> verification -> write-back`

Allowed states are explicit and must not be inferred:
`NOT_STARTED`, `QUEUED`, `EXECUTING`, `SUCCEEDED`, `FAILED`, `INTERRUPTED`, `VERIFIED`.

`QUEUED != EXECUTING != COMPLETED`.

## Security

- Authentication is required for protected state and command operations.
- Authorization is evaluated from an explicit role matrix.
- Rate limiting and payload limits are mandatory.
- Secrets remain outside the gateway state and repository documents.
- The public control surface must not expose raw unrestricted execution.
- Financial/live-money actions remain disabled unless separately approved and verified by K.

## PC/Mobile Surface

The first usable client surface may be a responsive Operations Hub. It must expose authoritative state through the gateway and clearly distinguish health, queued work, executing work, verified completion, and blocked work.

The gateway must support the same logical contract from desktop and mobile clients; clients are views/transports, not separate state stores.

## Acceptance Criteria

A release is accepted only when all are demonstrated:

1. Text input reaches the gateway and receives a correlation ID.
2. File/image inputs are accepted as references or controlled uploads without corrupting authoritative state.
3. Fresh client/session can reconstruct A from persistent state.
4. A task can be submitted with stable `taskId` linkage.
5. Client can retrieve authoritative task/evidence status.
6. Verification cannot be upgraded by health/queue activity alone.
7. Write-back is verified before completion is claimed.
8. Two client/runtime paths consume the same source of truth.
9. Unauthorized command attempts are rejected.
10. Gateway remains usable from PC and mobile without duplicating the master state.
