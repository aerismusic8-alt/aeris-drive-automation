# Authentication Acceptance Gates

These are acceptance requirements; they are not evidence of a passing runtime implementation until executed on the target PC.

- [ ] Plaintext password is rejected from persistent configuration.
- [ ] Password verifier uses Argon2id or approved adaptive KDF with unique salt.
- [ ] Invalid login returns generic `AUTH_FAILED`.
- [ ] Authentication endpoint rate-limits repeated failures.
- [ ] Successful login creates a short-lived session.
- [ ] Logout revokes the session.
- [ ] Protected `/state`, `/tasks`, `/command`, `/evidence`, and `/m-a-check` reject unauthenticated requests.
- [ ] Browser command requests have CSRF protection when cookie sessions are used.
- [ ] Audit records contain actor, role, request ID, timestamp, decision, and result but no secrets.
- [ ] Non-loopback access is rejected unless HTTPS/secure tunnel is active.
