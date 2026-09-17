# AX PowerShell Control Gate

The runtime is a continuous service. K does not create or advance individual execution cycles.

## Runtime contract
- ONLINE until an explicit operator shutdown.
- Supervisor cycles automatically.
- When no work is active, planner creates the next authorized system task.
- PowerShell execution is allowlisted; arbitrary shell commands are rejected.
- Every PowerShell action returns stdout, stderr, and exit code.
- DONE requires evidence and verification.
- A PowerShell failure creates FAILED evidence; it must never be reported as DONE.

## Operator shutdown
The runtime is not designed to self-stop after completing a task. Shutdown is an explicit operator action. OS termination remains an external failure/restart concern and is handled separately by the host/service layer.
