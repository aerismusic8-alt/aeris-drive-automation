# AX Control Hub

Secure transport/control boundary for A MASTER BRAIN.

## Authority boundary

- A MASTER BRAIN is the single source of truth.
- The Hub is transport/API infrastructure, not the brain.
- K is Final Authority.
- M remains M; authentication never changes agent identity.
- A command is not evidence of execution. Completion requires evidence and verification.

## Authentication

The Hub MUST authenticate the operator before any control operation.

Required properties:

1. Passwords are never stored in plaintext.
2. Password verification uses a memory-hard password KDF such as Argon2id (or an approved equivalent available in the deployment runtime) with a unique salt.
3. Session credentials are short-lived, revocable, and never placed in URLs.
4. Failed authentication is rate-limited.
5. Authentication and authorization events are audit logged without secrets.
6. Secrets are provided through local environment/OS secret storage, never A MASTER BRAIN or Git.
7. Default/demo credentials are forbidden in production.
8. All remote access requires HTTPS or an authenticated secure tunnel.

## Initial roles

- `K`: full operator authority, including approved control and emergency stop.
- `READ_ONLY`: state/task/evidence visibility only.
- `SERVICE`: machine-to-machine execution identity with least privilege; cannot redefine A identity or alter K authority.

## Trust model

`Client -> Authentication -> Authorization -> Command Validation -> Queue/Execution -> Evidence -> Verification`

A health response only proves health. It must never be used as proof that a task executed.
