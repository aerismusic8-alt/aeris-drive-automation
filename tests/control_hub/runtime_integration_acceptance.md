# AX Control Hub Runtime Integration Acceptance

Purpose: prove the local HTTP runtime actually serves the control boundary against a temporary A_MASTER_BRAIN fixture, without enabling live financial execution.

## Acceptance cases

- I1 `/health` returns healthy transport status while execution remains `UNKNOWN`.
- I2 `/auth/login` accepts the configured test credentials and returns a session token.
- I3 `/state` reads identity and authority from A_MASTER_BRAIN fixture files.
- I4 `/tasks` reads the v2 task registry from A_MASTER_BRAIN fixture files.
- I5 `/m-a-check` returns the A_MASTER_BRAIN challenge result and does not synthesize identity.
- I6 protected endpoints reject missing/invalid authentication.
- I7 `/command` accepts only the currently safe `health_check` command and preserves request correlation.
- I8 duplicate idempotency keys are rejected.
- I9 `/evidence/{request_id}` is explicitly pending until execution evidence exists.
- I10 `/auth/logout` revokes the session and subsequent protected access fails.
- I11 the runtime refuses startup when authoritative state/task files are unavailable.
- I12 the test never enables or invokes financial/live execution.

Pass condition: all I1-I12 execute successfully in an automated test process.
