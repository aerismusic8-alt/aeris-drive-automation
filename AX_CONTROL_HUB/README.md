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
2. Password verification uses an adaptive password KDF with a unique salt. The reference implementation uses PBKDF2-HMAC-SHA256 from the Python standard library so the foundation has no external dependency requirement; production may use an approved memory-hard KDF such as Argon2id when available.
3. Session credentials are short-lived, revocable, and never placed in URLs.
4. Failed authentication is rate-limited by the production deployment boundary.
5. Authentication and authorization events must be audit logged without secrets.
6. Secrets are provided through local environment/OS secret storage, never A MASTER BRAIN or Git.
7. Default/demo credentials are forbidden in production.
8. All remote access requires HTTPS or an authenticated secure tunnel.

## Initial roles

- `K`: full operator authority, including approved control and emergency stop.
- `READ_ONLY`: state/task/evidence visibility only.
- `SERVICE`: machine-to-machine execution identity with least privilege; cannot redefine A identity or alter K authority.

## Local reference runtime

`AX_CONTROL_HUB/ax_control_hub_server.py` is a loopback-first reference implementation. It reads `A_MASTER_BRAIN/AX_MASTER_STATE.json` and `A_MASTER_BRAIN/AX_MASTER_TASK_REGISTRY_v2.json` as authoritative sources and fails closed when they are unavailable.

Start on Windows:

```powershell
$env:AX_CONTROL_HUB_USERNAME = '<local-operator>'
$env:AX_CONTROL_HUB_PASSWORD = '<strong-local-password>'
python .\AX_CONTROL_HUB\ax_control_hub_server.py
```

Then run:

```powershell
.\AX_CONTROL_HUB\AX_CONTROL_HUB_E2E.ps1
```

The reference command allowlist intentionally contains only `health_check`; financial/live execution is not exposed by this foundation runtime.

## Trust model

`Client -> Authentication -> Authorization -> Command Validation -> Queue/Execution -> Evidence -> Verification`

A health response only proves health. It must never be used as proof that a task executed.
