# MeshCentral Adapter Pilot

Purpose: evaluate MeshCentral as an optional remote-management adapter without changing the canonical AERIS architecture.

Pilot node: PC2 (DESKTOP-M9M4818).

Architecture remains:
AX -> A MASTER BRAIN -> PC2 BRAIN -> PC2 CONTROL -> Desktop/Vision -> Verifier.

MeshCentral is transport/remote-management only. It must not become Brain authority or execution policy.

Pilot gates:
1. Server availability.
2. PC2 agent connectivity.
3. Desktop visibility/control.
4. Local command execution.
5. Evidence capture.
6. CPU/RAM impact.
7. Recovery after disconnect/reconnect.
8. Operation after ChatGPT session ends.

Acceptance:
- PC2 identity must be verified locally.
- Agent connection must be fresh.
- A remote operation must produce PC2-local evidence.
- Brain remains the source of intent.
- Control remains the executor.
- Verifier remains the source of success.
- Failure at any gate is NOT_VERIFIED.

Resource rule:
Do not install Ollama or other additional local AI runtime for this pilot.
Record CPU, RAM, latency and agent/server state before and after.

Rollback:
Pilot components must be removable without changing PC2 Brain, Control, Vision or Verifier contracts.