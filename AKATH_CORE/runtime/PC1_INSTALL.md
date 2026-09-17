# PC1 Autonomous AX Runtime

AX Runtime is an external Node.js supervisor. It continues after the ChatGPT session closes.

## Ownership

- AX: decisions, task state, evidence rules, runtime behavior, canonical workload selection.
- PC1: hosts the runtime continuously and executes the bound Specialist path.
- K: one-time bootstrap only; after activation, K is not required for each execution cycle.
- ChatGPT session: not required for the supervisor loop once PC1 Runtime is online.

## One-time PC1 activation

1. Ensure Node.js 20+ is installed.
2. On PC1, update the repository to `main`.
3. Ensure `GEMINI_API_KEY` is available in the PC1 user environment for AI capability. Never commit the key.
4. From the repository root, run:

```powershell
& .\AKATH_CORE\runtime\install-ax-runtime-autostart.ps1 -StartNow
```

The bootstrap registers the task `AERIS-AKATH-AX-RUNTIME` in Windows Task Scheduler for the current user, starts the runtime immediately, and configures automatic restart on failure. The runtime runs `main.mjs` directly and uses the existing PC1 Specialist path.

5. Verify:

```powershell
& .\AKATH_CORE\runtime\healthcheck.ps1
```

The expected live state is `RuntimeStatus = ONLINE` with a recent `LastHeartbeatAt` and a non-null `ActiveJob` while work is executing.

## What happens after bootstrap

`PC1 Runtime → canonical sync → autonomous planner → CLAIM → SPECIALIST → EXECUTE → EVIDENCE → VERIFY → DONE → NEXT JOB`

The current canonical first workload is `AKATH-JUMPTASK-AI-FIRST-001`. The AI specialist must determine whether the supplied JumpTask workload contains a legitimate autonomous/background action before any external earning action is attempted.

## Removal

```powershell
& .\AKATH_CORE\runtime\uninstall-ax-runtime-autostart.ps1
```

## Autonomous gate

The gate is PASS only when, with the ChatGPT session closed, PC1 independently shows a live heartbeat and completes a non-destructive job with persisted evidence and verification. A Git commit alone does not satisfy the gate.
