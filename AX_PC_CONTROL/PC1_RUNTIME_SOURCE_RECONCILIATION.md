# PC1 Runtime Source Reconciliation Contract

Purpose: prevent the live PC1 runtime from executing stale Brain/Control source.

Canonical source:
- Repository: aerismusic8-alt/aeris-drive-automation
- Node: PC1 / DESKTOP-RGK6JKB
- Runtime root: C:\\AX-Runtime
- Brain decision worker: AX_PC_CONTROL/brain1-decision-worker.ps1
- Local Control worker: AX_PC_CONTROL/brain1-local-control-worker.ps1
- MeshCentral adapter: AX_PC_CONTROL/pc1-meshcentral-ax-dispatch.ps1

Required gate before autonomous execution is declared READY:
1. PC1 runtime identifies itself as DESKTOP-RGK6JKB.
2. The locally deployed Brain decision worker matches the current canonical repository revision.
3. The locally deployed Control worker matches the current canonical repository revision.
4. The MeshCentral adapter configuration is present locally without storing credentials in Git/A MASTER BRAIN.
5. Brain and Control heartbeats are fresh.
6. A harmless NODE_HEALTH_CHECK is dispatched through the approved adapter path.
7. Control produces node-local execution evidence.
8. Verifier independently validates the evidence.
9. Only then may state transition to VERIFIED.

Important:
- GitHub is source/version control, not runtime authority.
- MeshCentral is transport only.
- AX does not directly declare node execution verified.
- Control must not self-declare VERIFIED.
- Missing or conflicting local evidence means STATE NOT VERIFIED.
- Never overwrite an active PC1 runtime blindly; reconcile and verify component-by-component.
