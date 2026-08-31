# AX Runtime Execution Timing Policy

Status: ACTIVE
Scope: AX / AERIS execution infrastructure
Purpose: Separate fast diagnostic feedback from production execution timing so workflow timeouts do not get mistaken for code/script failures.

## Rules

1. Diagnostic Mode may use short trigger intervals and short feedback cycles to expose connectivity, routing, authentication, and integration problems quickly.
2. Diagnostic timing is temporary. It must not be treated as the production cadence.
3. Production Mode must size timeouts and scheduling from measured execution duration of the actual script/workflow chain.
4. In a dependent script chain, a downstream script must not start until the upstream script has reported verified completion.
5. A timeout must be recorded separately from a script/process failure. Never collapse both into a generic FAILED status.
6. Every execution stage should preserve at least: startedAt, completedAt, duration, exitCode/status, and verification result.
7. Final workflow status should become FINAL_VERIFIED only after the complete chain has finished and the final verification passes.
8. When execution is intentionally stopped because a timeout threshold was reached, record TIMEOUT/ABORTED distinctly so it is possible to determine whether the code failed or the runtime stopped it first.
9. Before changing a production timeout, use observed execution evidence from the relevant script chain rather than arbitrary values.
10. When multiple workflows overlap or trigger each other, concurrency and dependency controls must prevent premature cancellation or false failure attribution.

## Operating Model

Diagnostic Mode:
Trigger -> observe quickly -> isolate failure boundary -> fix -> re-run.

Production Mode:
Trigger -> Script 1 -> verified completion -> Script 2 -> verified completion -> ... -> Final Verify.

## Verification Requirement

A workflow is not considered healthy merely because the GitHub Actions run is marked `completed`. The individual steps and their verification evidence must be inspected before declaring success.

## Known Evidence

- AX Status Monitor demonstrated a working pattern using `cmd` to invoke `powershell.exe -NoProfile -ExecutionPolicy Bypass`, while several self-hosted workflows using plain `shell: powershell` were blocked by execution policy before their scripts started.
- AICS Persistence Auto-Save reached the live Apps Script endpoint but received `UNKNOWN_COMMAND:` for `CREATE_SAVEPOINT`, showing that deployment/runtime drift must be distinguished from runner execution failures.

## Change Control

This policy is a runtime-efficiency and verification rule. It should be applied before increasing automation frequency, parallelism, or production workload.
