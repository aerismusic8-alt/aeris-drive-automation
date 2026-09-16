# PC1 Autonomous AX Runtime

AX Runtime is an external Node.js supervisor. It is the process that continues after the ChatGPT session closes.

## Ownership

- AX: defines decisions, contracts, task state, evidence rules, and runtime behavior.
- PC1: hosts and keeps the AX Runtime process alive and executes the bound Specialist command.
- K: only required for the one-time PC1 activation if the existing PC1 executor command is not already exposed to this runtime.
- ChatGPT session: not required for the supervisor loop once PC1 is running.

## One-time PC1 activation

1. Ensure Node.js 20+ is installed.
2. On PC1, clone/update this repository's `main` branch.
3. Set `AX_PC1_EXECUTOR_COMMAND` to the existing local PC1 Specialist/executor command. Do not replace this with a guessed URL.
4. Optionally set `AX_PC1_NODE_ID=PC1-MAIN` and `AX_RUNTIME_INTERVAL_MS=5000`.
5. Run from PowerShell:

```powershell
$env:AX_PC1_EXECUTOR_COMMAND = '<EXISTING_PC1_SPECIALIST_COMMAND>'
$env:AX_PC1_NODE_ID = 'PC1-MAIN'
& .\AKATH_CORE\runtime\start-ax-runtime.ps1
```

6. Check runtime state:

```powershell
& .\AKATH_CORE\runtime\healthcheck.ps1
```

The launcher fails closed when Node.js or the executor binding is missing.

## Autonomous gate

The gate is PASS only when, with the ChatGPT session closed, PC1 independently shows a live heartbeat and completes a non-destructive job with persisted evidence and verification. A code commit alone does not satisfy the gate.
