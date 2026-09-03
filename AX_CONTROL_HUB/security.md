# AX Control Hub Security Contract

## Credential handling

- Never commit passwords, API keys, session secrets, cookies, or private keys.
- Store the operator password only as a KDF-derived verifier in local OS-protected configuration.
- Generate a unique random salt per password.
- Prefer Argon2id; if unavailable, use an approved memory-hard or adaptive password KDF supported by the runtime.
- Rotate credentials through an authenticated local administration path.

## Sessions

- Use cryptographically random session identifiers.
- Store sessions server-side or use authenticated, integrity-protected tokens.
- Set expiration and revoke on logout/security events.
- Do not transmit session identifiers in query strings.
- Use Secure and HttpOnly cookies when cookie sessions are used; use SameSite protection.

## Request protection

- Validate JSON schema before authorization-sensitive processing.
- Require a unique request/correlation ID.
- Enforce idempotency for command requests.
- Reject replayed or expired command envelopes.
- Rate-limit authentication and control endpoints.
- Use CSRF protection for cookie-authenticated browser commands.

## Network boundary

- Default bind is loopback only.
- LAN access must be explicitly enabled and restricted by firewall/network policy.
- Remote/mobile access must use authenticated HTTPS or an authenticated secure tunnel.
- Never expose the raw control port directly to the public Internet.

## Audit

Record: timestamp from the trusted runtime, actor/role, endpoint, request ID, decision, result, and evidence reference. Never record passwords, bearer tokens, or other secrets.

## Authority

The Hub cannot modify K authority, redefine A identity, or treat its own health as evidence of task completion. Authoritative state comes from A MASTER BRAIN and verified evidence.
