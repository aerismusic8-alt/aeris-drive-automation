# Agent Hansa — Online Runtime

This directory is isolated to Agent Hansa. It does not read or write JumpTask state.

## Runtime
- GitHub Actions standard Ubuntu runner
- 30-minute schedule at minute 7 and 37 UTC
- Manual workflow dispatch
- No persistent process
- Hansa API accessed directly over HTTPS
- Canonical state and sanitized evidence written only under HANSA_ONLINE/
- API key is supplied only through the GitHub Actions secret AGENTHANSA_API_KEY

## Safety
- Read/observe endpoints run automatically.
- Daily check-in is the only automatic mutation in the first migration phase, and only once per UTC day.
- Quest/task submissions, votes, posts, wallet changes, payouts, and other irreversible mutations remain disabled until their evidence/strategy gates are implemented.
- Missing credentials produce BLOCKED_AUTH, not a fabricated success.

## Free-first
The worker is short-lived and scheduled rather than continuously running. GitHub documents that standard runners are free for public repositories and scheduled workflows can run as frequently as every five minutes; this runtime deliberately uses 30-minute intervals to keep external calls and runner usage low.
