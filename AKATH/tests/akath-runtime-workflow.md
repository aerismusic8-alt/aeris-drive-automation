# AKATH Runtime Workflow Validation

## Trigger contract

- `workflow_dispatch` allows a controlled manual proof.
- `schedule` wakes the runtime every five minutes.
- `push` to `main` runs the initial post-merge proof.

GitHub documents five minutes as the shortest supported scheduled-workflow interval. The schedule is only a wake-up mechanism; runner-local state and watchdog provide continuity.

## Execution contract

- `runs-on: self-hosted` prevents the continuous proof from consuming private-repository GitHub-hosted runner minutes.
- `concurrency` serializes the runtime group so overlapping wake-ups do not execute the same runtime concurrently.
- The worker runs in harmless probe mode until an authoritative production queue adapter is connected.
- The verification step requires `state=VERIFIED`, `verification_status=VERIFIED`, and an evidence reference.

## Security contract

- No credentials are stored in the workflow.
- Repository permission is read-only.
- Probe mode performs no financial or public side effects.
