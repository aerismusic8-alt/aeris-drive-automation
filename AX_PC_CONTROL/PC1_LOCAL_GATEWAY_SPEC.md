# PC1 Local Gateway Protocol

Status: SPEC_READY / RUNTIME_NOT_VERIFIED

## Authority
The PC1 Local Brain is the runtime authority for PC1 state and execution.
GitHub is source/version control only.

## Endpoint
- Bind: 127.0.0.1
- Port: 18761
- Health: GET /health
- Intent: POST /intent

## Flow
AX -> A MASTER BRAIN -> PC1 LOCAL BRAIN -> LOCAL GATEWAY -> CONTROL -> VISION/VERIFIER

The gateway is an adapter. It does not decide actions.

## Intent contract
Required:
- targetNode = PC1
- jobId
- intent

Allowed intents:
- NODE_HEALTH_CHECK
- SYSTEM_DIAGNOSTIC
- CLOSE_STALE_TERMINAL
- CAPTURE_AND_REVERIFY
- RESTART_OWNED_RUNTIME
- INCIDENT_LOCAL_DIAGNOSE

## Evidence rule
Every action must produce local PC1 evidence. Remote/GitHub evidence cannot substitute for event-local evidence.

## Current verification
The gateway script exists in source control, but PC1 runtime installation and /health response are NOT VERIFIED.
