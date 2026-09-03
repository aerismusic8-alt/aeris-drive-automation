# AERIS / AX OPERATIONS HUB

> Mobile-first entry point for operating, monitoring, and reviewing the AERIS / AX system.

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
- [Workflow files](https://github.com/aerismusic8-alt/aeris-drive-automation/tree/main/.github/workflows)
- [All repository files](https://github.com/aerismusic8-alt/aeris-drive-automation/tree/main)

### PC1 / PC2

PC1 and PC2 are execution nodes. Their live machine status is not exposed by a verified public URL in this repository, so this hub does **not** invent a monitoring URL. When a verified node-status endpoint is available, add it here.

## AERIS MONITOR / JOBS

Only verified GitHub destinations are linked here until runtime endpoints are confirmed from repository configuration.

- [Actions / runtime history](https://github.com/aerismusic8-alt/aeris-drive-automation/actions)
- [Issues / operational incidents](https://github.com/aerismusic8-alt/aeris-drive-automation/issues)

## REPOSITORY DOCUMENTATION

- [AX Control Hub API Contract](https://github.com/aerismusic8-alt/aeris-drive-automation/blob/main/AX_CONTROL_HUB/API_CONTRACT.md) — gateway, authentication, state, task, and evidence semantics.
- [Workflow files](https://github.com/aerismusic8-alt/aeris-drive-automation/tree/main/.github/workflows) — automation definitions.
- [Repository](https://github.com/aerismusic8-alt/aeris-drive-automation/tree/main) — complete source tree.

## CURRENT OPERATING PRIORITY

1. Keep the execution layer reliable.
2. Prioritize PC1 for high availability / 24×7 operation where applicable.
3. Use PC2 for development, testing, and E2E execution.
4. Use coding agents as execution resources without allowing parallel work to interfere with the same code area.
5. Verify every completed change through real execution evidence before treating it as complete.
6. Move toward a revenue-producing MVP on the approved timeline.

## MOBILE USE

Open `/operations` from the running Control Hub in a mobile browser for the responsive client surface. The same gateway is used from desktop browsers; the UI does not create a second master state.

## LINK INTEGRITY RULE

This page intentionally avoids unverified runtime URLs. Runtime endpoints for PC1, PC2, AERIS Monitor, Job Log, and Delegation Queue will be added only after their actual endpoints are verified.
