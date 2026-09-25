# PC1 MeshCentral Adapter Pilot

Node: PC1
ComputerName: DESKTOP-RGK6JKB

Purpose:
Test MeshCentral as an optional transport/remote-management adapter for PC1 without changing the canonical AERIS architecture.

Canonical authority remains:
AX -> A MASTER BRAIN -> PC1 BRAIN -> PC1 CONTROL -> Desktop/Vision -> VERIFIER

MeshCentral role:
- transport and remote-management adapter only
- never Brain authority
- never intent selector
- never replaces PC1 Control
- never creates VERIFIED without PC1-local evidence

PC1 pilot sequence:
1. Confirm PC1 local identity.
2. Install/start MeshCentral agent on PC1 using a user-approved local installation path.
3. Confirm outbound agent connection to the controlled MeshCentral server.
4. Verify PC1 desktop visibility.
5. Verify a harmless local command through the adapter.
6. Capture PC1-local evidence for each step.
7. Measure CPU, RAM and latency impact.
8. Disconnect/reconnect the agent and verify recovery.
9. Verify operation continues independently after the ChatGPT session ends.

Evidence requirements:
- nodeId=PC1
- computerName=DESKTOP-RGK6JKB
- evidenceScope=PC1_LOCAL
- fresh timestamp
- adapter state
- action/result
- post-action evidence
- verification result

State rules:
NOT_VERIFIED until fresh PC1 evidence exists.
READY requires PC1-local Brain, Control and adapter evidence.
EXECUTING requires a valid PC1 Brain intent.
VERIFIED requires fresh post-action evidence and verifier approval.

Failure handling:
If the adapter is unavailable, PC1 Brain/Control architecture remains authoritative.
If an incident occurs, diagnose it on PC1 where it occurs; do not substitute GitHub or another node as event evidence.

Resource rule:
Do not add Ollama or another local AI runtime for this pilot.
Record baseline and post-install CPU/RAM before accepting the adapter.

Rollback:
Remove only the adapter components and preserve PC1 Brain, Control, Vision, Verifier and their queues/contracts.