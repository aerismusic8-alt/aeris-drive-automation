# AX Control Hub

Secure transport/control boundary for A MASTER BRAIN.

## Authority boundary

- A MASTER BRAIN is the single source of truth.
- The Hub is transport/API infrastructure, not the brain.
- K is Final Authority.
- M remains M; authentication never changes agent identity.
- A command is not evidence of execution. Completion requires evidence and verification.

## Authentication

The Hub MUST authenticate the caller before any protected operation.

Required properties:

1. Passwords are never stored in plaintext.
2. Password verification uses PBKDF2-HMAC-SHA256 with a unique salt in the reference runtime.
3. K sessions are short-lived and revocable and are never placed in URLs.
4. SERVICE and READ_ONLY tokens are supplied through environment/OS secret storage, never A MASTER BRAIN or Git.
5. Default/demo credentials are forbidden in production.
6. All remote access requires HTTPS or an authenticated secure tunnel.

Environment variables:

```text
AX_CONTROL_HUB_USERNAME=<local-operator>
AX_CONTROL_HUB_PASSWORD=<strong-local-password>
AX_CONTROL_HUB_SERVICE_TOKEN=<random-service-token>
AX_CONTROL_HUB_READ_ONLY_TOKEN=<random-read-only-token>
```

## Roles

- `K`: full operator authority, including approved control and emergency stop.
- `SERVICE`: machine-to-machine least privilege; may read approved state/task/evidence and submit approved gateway input; cannot redefine AX identity or alter K authority.
- `READ_ONLY`: state/task/evidence visibility only; cannot submit input.

## Browser client

`/operations` is the responsive **AX Web Chat** client for PC1, PC2, and Mobile. It is a client of the Hub, not a memory store. Browser storage contains only the short-lived session token and presentation state.

## Standard gateway routes

- `GET /gateway/session` — rehydrate AX context from A MASTER BRAIN.
- `GET /gateway/capabilities` — caller capability set.
- `GET /gateway/state` — authoritative state view.
- `GET /gateway/tasks` — authoritative task registry view.
- `POST /gateway/m-a-check` — identity/rehydration challenge.
- `POST /gateway/input` — input with required unique `idempotency_key`.
- `GET /gateway/input/{request_id}` — durable transport input.
- `GET /gateway/evidence/{request_id}` — execution evidence.

External AI clients use the same standard API boundary and never access Master Brain files directly.

## Safety boundaries

- Failed Master Brain rehydration blocks control input.
- Duplicate idempotency keys are rejected.
- `QUEUED`, `EXECUTING`, and `COMPLETED` remain distinct.
- Completion requires evidence and verification.
- Attachments are metadata/references only; raw binary is rejected.
- Live financial execution is outside this gateway phase.

## Local reference runtime

`AX_CONTROL_HUB/ax_control_hub_server.py` is loopback-first. It reads `A_MASTER_BRAIN/AX_MASTER_STATE.json` and `A_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json` as authoritative sources and fails closed when they are unavailable.
