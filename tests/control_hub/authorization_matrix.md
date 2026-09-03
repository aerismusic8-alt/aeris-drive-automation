# AX Control Hub Authorization Acceptance Tests

## Roles

- `K`: full operator authority subject to existing guardrails and approval rules.
- `READ_ONLY`: read state, tasks, evidence, and health only.
- `SERVICE`: machine-to-machine access limited to explicitly assigned operations.

## Matrix

| Operation | K | READ_ONLY | SERVICE |
|---|---:|---:|---:|
| `/health` | yes | yes | yes |
| `/state` | yes | yes | yes* |
| `/tasks` | yes | yes | yes* |
| `/m-a-check` | yes | yes | yes* |
| `/evidence/{request_id}` | yes | yes | yes* |
| `/command` | yes | no | allowlist only |
| emergency stop | yes | no | explicitly allowlisted |
| change K authority | no | no | no |
| redefine A identity | no | no | no |

`*` Service access must be limited to the minimum data required by its function.

## Negative tests

- [ ] READ_ONLY command submission returns `FORBIDDEN`.
- [ ] Unknown command returns `INVALID_REQUEST` or `GUARDRAIL_BLOCKED` before enqueue.
- [ ] SERVICE command outside its allowlist returns `FORBIDDEN`.
- [ ] Missing/invalid session returns `AUTH_REQUIRED`.
- [ ] Replayed idempotency key returns `DUPLICATE_REQUEST` and does not create another job.
- [ ] Hub cannot modify A MASTER BRAIN authority or identity through any API.
