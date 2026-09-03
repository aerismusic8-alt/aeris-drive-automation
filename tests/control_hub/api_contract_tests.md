# API Contract Acceptance Gates

These gates define what must be executed against a real Hub before the API is considered implemented.

- [ ] `/health` reports service health without implying task execution.
- [ ] `/auth/login` authenticates valid local operator credentials and rejects invalid credentials.
- [ ] `/state` returns A MASTER BRAIN as the declared source.
- [ ] `/tasks` matches the authoritative master task registry.
- [ ] `/m-a-check` performs the full Identity/Rehydration Challenge and returns explicit gate results.
- [ ] `/command` rejects missing authentication, malformed envelopes, unauthorized commands, replayed idempotency keys, and guardrail violations.
- [ ] Valid harmless command receives a unique request ID and `QUEUED` only after successful validation/enqueue.
- [ ] `/evidence/{request_id}` correlates execution evidence to the same request ID.
- [ ] A queued/executing result cannot be reported as completed without verification.
- [ ] Stale dashboard/heartbeat/queue state cannot outrank A MASTER BRAIN.
- [ ] Emergency stop requires explicit authorization and is audit logged.
- [ ] Stable error classes are returned without leaking secrets or credentials.
