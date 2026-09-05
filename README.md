# AKATH / AERIS / AX OPERATIONS HUB

> **AKATH — Autonomous AI Company**. This repository is the current execution substrate for the AKATH autonomous operating system. A MASTER BRAIN remains authoritative; AX is the executive orchestrator; ChatGPT is a K-facing control/observation channel and is not required for ordinary runtime continuation.

## AKATH IDENTITY

```text
AKATH — Autonomous AI Company
        │
        ▼
A MASTER BRAIN
        │
        ▼
AX — Executive Orchestrator
        │
        ▼
AI Workforce + Autonomous Runtime
        │
        ▼
Execute → Verify → Log → Continue
```

The primary AKATH acceptance criterion is **GPT-independent continuous operation**. Ordinary runtime cycles must advance without requiring a new ChatGPT message between cycles.

## AKATH RUNTIME

- Runtime contract: `AKATH/RUNTIME_CONTRACT.md`
- Current status: `AKATH/STATUS.md`
- Autonomous worker: `AKATH/runtime/akath_worker.ps1`
- Watchdog: `AKATH/runtime/akath_watchdog.ps1`
- E2E probe: `AKATH/probes/akath_e2e_probe.ps1`
- Rehydration adapter: `AKATH/runtime/ax_rehydration_adapter.py`
- GitHub Actions runtime: `.github/workflows/akath-runtime.yml`
- Autonomous acceptance proof: `AKATH/VERIFICATION/three-cycle-proof.json` (created only after a real passing verification run)

### Acceptance Gate

The AKATH runtime workflow performs three successive autonomous cycles in one GitHub Actions execution and verifies, for every cycle:

1. Runtime state reaches `VERIFIED`.
2. A is rehydrated from the authoritative A MASTER BRAIN.
3. Execution authority is not bypassed (`execution_authorized=false` during rehydration).
4. Each cycle has a distinct runtime run ID.
5. The next job is reported ready.
6. A machine-readable three-cycle proof is written and persisted to the repository.

**24/7 verification status:** `PENDING REAL EXECUTION EVIDENCE` until `AKATH/VERIFICATION/three-cycle-proof.json` exists with `acceptance=PASS`. The README must never promote this status based on configuration alone.

## CLIENT ENTRY POINT

The same gateway contract is used from GPT, PC, and Mobile. The client is a transport/view layer; A MASTER BRAIN remains the authoritative source of truth.

- **Operations Hub:** `/operations` when the local Control Hub is running
- **M-A-CHECK:** `/gateway/m-a-check`
- **Input:** `/gateway/input`
- **State:** `/gateway/state`
- **Tasks:** `/gateway/tasks`
- **Evidence:** `/gateway/evidence/{request_id}`

Supported logical input types include text, file references, image references, events, and commands. Raw binary content is not written into A MASTER BRAIN state.

## LIVE CONTROL & STATUS

| Area | Open |
|---|---|
| Repository | [AERIS Drive Automation](https://github.com/aerismusic8-alt/aeris-drive-automation) |
| GitHub Actions | [Workflows & runs](https://github.com/aerismusic8-alt/aeris-drive-automation/actions) |
| Issues | [Issues](https://github.com/aerismusic8-alt/aeris-drive-automation/issues) |
| Copilot | [GitHub Copilot](https://github.com/copilot) |
| Code | [Repository files](https://github.com/aerismusic8-alt/aeris-drive-automation/tree/main) |

## EXECUTION

Use the links below for the execution layer that is verifiable from this repository.

- [GitHub Actions — execution history](https://github.com/aerismusic8-alt/aeris-drive-automation/actions)
- [AKATH runtime workflow](https://github.com/aerismusic8-alt/aeris-drive-automation/blob/main/.github/workflows/akath-runtime.yml)
- [Workflow files](https://github.com/aerismusic8-alt/aeris-drive-automation/tree/main/.github/workflows)
- [All repository files](https://github.com/aerismusic8-alt/aeris-drive-automation/tree/main)
- [Three-cycle proof](https://github.com/aerismusic8-alt/aeris-drive-automation/blob/main/AKATH/VERIFICATION/three-cycle-proof.json) — becomes valid only after a real successful acceptance run.

### PC1 / PC2

PC1 and PC2 are execution nodes. Their live machine status is not exposed by a verified public URL in this repository, so this hub does **not** invent a monitoring URL.

- **PC1:** preferred high-availability / 24×7 execution node where applicable.
- **PC2:** development, testing, and E2E execution node; the AKATH GitHub Actions workflow targets `PC2-CODING-EXECUTOR`.

A node is not considered healthy solely from configuration. Live status must come from execution evidence.

## AERIS MONITOR / JOBS

Only verified GitHub destinations are linked here until runtime endpoints are confirmed from repository configuration.

- [Actions / runtime history](https://github.com/aerismusic8-alt/aeris-drive-automation/actions)
- [Issues / operational incidents](https://github.com/aerismusic8-alt/aeris-drive-automation/issues)

## REPOSITORY DOCUMENTATION

- [AX Control Hub API Contract](https://github.com/aerismusic8-alt/aeris-drive-automation/blob/main/AX_CONTROL_HUB/API_CONTRACT.md) — gateway, authentication, state, task, and evidence semantics.
- [AKATH Runtime Contract](https://github.com/aerismusic8-alt/aeris-drive-automation/blob/main/AKATH/RUNTIME_CONTRACT.md) — autonomous runtime state and invariants.
- [AKATH Status](https://github.com/aerismusic8-alt/aeris-drive-automation/blob/main/AKATH/STATUS.md) — current implementation and verification status.
- [AKATH three-cycle proof](https://github.com/aerismusic8-alt/aeris-drive-automation/blob/main/AKATH/VERIFICATION/three-cycle-proof.json) — machine-readable autonomous acceptance evidence.
- [Workflow files](https://github.com/aerismusic8-alt/aeris-drive-automation/tree/main/.github/workflows) — automation definitions.
- [Repository](https://github.com/aerismusic8-alt/aeris-drive-automation/tree/main) — complete source tree.

## CURRENT OPERATING PRIORITY

1. Keep the execution layer reliable.
2. Preserve GPT-independent runtime continuation.
3. Prioritize PC1 for high availability / 24×7 operation where applicable.
4. Use PC2 for development, testing, and E2E execution.
5. Use coding agents as execution resources without allowing parallel work to interfere with the same code area.
6. Verify every completed change through real execution evidence before treating it as complete.
7. Move toward a revenue-producing MVP on the approved timeline.

## MOBILE USE

Open `/operations` from the running Control Hub in a mobile browser for the responsive client surface. The same gateway is used from desktop browsers; the UI does not create a second master state.

## LINK INTEGRITY RULE

This page intentionally avoids unverified runtime URLs. Runtime endpoints for PC1, PC2, AERIS Monitor, Job Log, and Delegation Queue will be added only after their actual endpoints are verified.

## STATUS INTEGRITY RULE

A green dashboard, heartbeat, or configuration entry is **not** by itself proof of autonomous 24/7 operation. Acceptance requires real execution evidence and a persisted three-cycle proof generated by the runtime itself.
